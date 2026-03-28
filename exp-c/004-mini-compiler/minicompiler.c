/*
 * Portable FreeForth2 — Experiment 004: Minimal Forth Compiler
 *
 * Question: Can we build the smallest possible Forth compiler in C
 * that uses GCC global register variables for TOS/NOS/DSP, discovers
 * primitive code bytes at runtime, and compiles Forth definitions by
 * copying those bytes?
 *
 * This compiler supports:
 *   - Integer literals (decimal only for simplicity)
 *   - Primitive words: + drop dup @ !
 *   - : and ; for defining colon definitions
 *   - Immediate execution of words outside definitions
 *   - .  (print TOS)
 *   - cr (newline)
 *
 * Test case: `: double dup + ; 21 double .` should print 42.
 *
 * Architecture: x86-64 only (for now). The RET byte (0xC3) and
 * CALL instruction (0xE8 + rel32) are hardcoded.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

/* --- Register pinning (x86-64) --- */
register long    tos  asm("rbx");
register long    nos  asm("r13");
register long   *dsp  asm("r15");

/* ================================================================
 * Primitives — each is a normal C function.  GCC with global
 * register variables produces clean, prologue-free code.
 * ================================================================ */

void __attribute__((noinline)) prim_add(void) {
    tos += nos;
    nos = *dsp;
    dsp++;
}

void __attribute__((noinline)) prim_drop(void) {
    tos = nos;
    nos = *dsp;
    dsp++;
}

void __attribute__((noinline)) prim_dup(void) {
    dsp--;
    *dsp = nos;
    nos = tos;
}

void __attribute__((noinline)) prim_fetch(void) {
    tos = *(long *)tos;
}

void __attribute__((noinline)) prim_store(void) {
    *(long *)tos = nos;
    tos = *dsp;
    nos = *(dsp + 1);
    dsp += 2;
}

void __attribute__((noinline)) prim_end_sentinel(void) {
    asm volatile("nop");
}

/* ================================================================
 * Literal push — needs special handling because the value is
 * embedded in the instruction stream.
 *
 * For x86-64, a literal push is:
 *   dsp--;  *dsp = nos;  nos = tos;  tos = <immediate>;
 *
 * But the immediate comes from the instruction stream at compile
 * time, so we emit: "dup" body + "movabs rbx, imm64" (REX.W + B8+r)
 * Actually simpler: emit dup body, then mov rbx, imm64.
 *
 * x86-64 encoding: 48 BB <8 bytes little-endian> = movabs rbx, imm64
 * ================================================================ */

#define LIT_PREFIX_SIZE 2   /* 48 BB */
#define LIT_IMM_SIZE    8
#define LIT_TOTAL_SIZE  (LIT_PREFIX_SIZE + LIT_IMM_SIZE)

/* ================================================================
 * Compiler state
 * ================================================================ */

#define CODEBUF_SIZE  (64 * 1024)
#define DICT_MAX      256
#define DATA_STACK_SZ 256

static uint8_t *codebuf;        /* mmap'd RWX code space */
static size_t   here;           /* compilation pointer */

static long data_stack[DATA_STACK_SZ];

/* Dictionary entry */
typedef struct {
    const char *name;
    uint8_t    *code;     /* start of machine code */
    size_t      code_len; /* length WITHOUT trailing RET */
    int         is_prim;  /* true if discovered from C function */
} dict_entry;

static dict_entry dictionary[DICT_MAX];
static int dict_count = 0;

/* Compiling state */
static int compiling = 0;
static size_t def_start = 0;    /* start of current definition */

/* ================================================================
 * Primitive table — for discovering code bytes
 * ================================================================ */

typedef struct {
    const char *name;
    void       (*func)(void);
} prim_info;

static prim_info prim_table[] = {
    { "+",   prim_add   },
    { "drop", prim_drop  },
    { "dup",  prim_dup   },
    { "@",    prim_fetch },
    { "!",    prim_store },
    { NULL,   prim_end_sentinel }
};

/* ================================================================
 * Initialization
 * ================================================================ */

static size_t find_ret(uint8_t *start, size_t maxscan) {
    for (size_t i = 0; i < maxscan; i++) {
        if (start[i] == 0xC3) return i;
    }
    return 0;
}

static int init(void) {
    codebuf = mmap(NULL, CODEBUF_SIZE, PROT_READ | PROT_WRITE | PROT_EXEC,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (codebuf == MAP_FAILED) return -1;
    here = 0;

    /* Discover primitive code bytes and register in dictionary */
    for (int i = 0; prim_table[i].name != NULL; i++) {
        uint8_t *start = (uint8_t *)prim_table[i].func;
        uint8_t *next  = (uint8_t *)prim_table[i + 1].func;
        size_t   gap   = next - start;
        size_t   body  = find_ret(start, gap);

        if (body == 0) {
            fprintf(stderr, "init: no RET in %s\n", prim_table[i].name);
            return -1;
        }

        dictionary[dict_count].name     = prim_table[i].name;
        dictionary[dict_count].code     = start;
        dictionary[dict_count].code_len = body;
        dictionary[dict_count].is_prim  = 1;
        dict_count++;
    }

    return 0;
}

/* ================================================================
 * Code emission
 * ================================================================ */

static void emit_bytes(const uint8_t *src, size_t len) {
    memcpy(codebuf + here, src, len);
    here += len;
}

static void emit_byte(uint8_t b) {
    codebuf[here++] = b;
}

/* Emit an inlined copy of a word's body (no RET) */
static void emit_inline(dict_entry *e) {
    emit_bytes(e->code, e->code_len);
}

/* Emit a CALL rel32 to an address in codebuf */
static void emit_call(uint8_t *target) {
    uint8_t *call_site = codebuf + here;
    emit_byte(0xE8);  /* CALL rel32 */
    int32_t rel = (int32_t)(target - (call_site + 5));
    emit_bytes((uint8_t *)&rel, 4);
}

/* Emit a literal: dup body + movabs rbx, imm64 */
static void emit_literal(long value) {
    /* First, emit dup body to push current TOS */
    dict_entry *dup_entry = NULL;
    for (int i = 0; i < dict_count; i++) {
        if (strcmp(dictionary[i].name, "dup") == 0) {
            dup_entry = &dictionary[i];
            break;
        }
    }
    if (dup_entry) emit_inline(dup_entry);

    /* Then overwrite TOS: movabs rbx, imm64 */
    emit_byte(0x48);  /* REX.W */
    emit_byte(0xBB);  /* MOV rbx, imm64 */
    emit_bytes((uint8_t *)&value, 8);
}

static void emit_ret(void) {
    emit_byte(0xC3);
}

/* ================================================================
 * Dictionary lookup
 * ================================================================ */

static dict_entry *dict_find(const char *name) {
    for (int i = dict_count - 1; i >= 0; i--) {
        if (strcmp(dictionary[i].name, name) == 0)
            return &dictionary[i];
    }
    return NULL;
}

/* ================================================================
 * Interpreter / compiler
 * ================================================================ */

static int is_number(const char *s, long *val) {
    char *end;
    *val = strtol(s, &end, 10);
    return (*end == '\0' && end != s);
}

/* Execute the code at codebuf[start..here), then reset here to start */
static void execute_anon(size_t start) {
    emit_ret();
    void (*fn)(void) = (void (*)(void))(codebuf + start);
    fn();
    here = start;  /* reclaim the anonymous block */
}

static void process_word(const char *word) {
    long num;

    /* : — start a colon definition */
    if (strcmp(word, ":") == 0) {
        compiling = 1;
        def_start = here;
        return;  /* next word is the name — handled by caller */
    }

    /* ; — end definition */
    if (strcmp(word, ";") == 0) {
        if (!compiling) return;
        emit_ret();
        compiling = 0;
        return;
    }

    /* . — print TOS and drop (special: uses C printf) */
    if (strcmp(word, ".") == 0) {
        if (compiling) {
            /* Can't easily inline printf — emit a CALL to a helper */
            /* For this experiment, we don't support . in definitions */
            fprintf(stderr, "warning: . in definitions not supported yet\n");
        } else {
            printf("%ld ", tos);
            tos = nos;
            nos = *dsp;
            dsp++;
        }
        return;
    }

    /* cr — print newline */
    if (strcmp(word, "cr") == 0) {
        if (!compiling) printf("\n");
        return;
    }

    /* Dictionary lookup */
    dict_entry *e = dict_find(word);
    if (e) {
        if (compiling) {
            if (e->is_prim) {
                emit_inline(e);  /* inline primitive */
            } else {
                emit_call(e->code);  /* CALL colon definition */
            }
        } else {
            /* Execute immediately — wrap in anon block */
            size_t save = here;
            emit_inline(e);
            execute_anon(save);
        }
        return;
    }

    /* Number? */
    if (is_number(word, &num)) {
        if (compiling) {
            emit_literal(num);
        } else {
            /* Push to stack directly */
            dsp--;
            *dsp = nos;
            nos = tos;
            tos = num;
        }
        return;
    }

    fprintf(stderr, "? %s\n", word);
}

/* ================================================================
 * Tokenizer
 * ================================================================ */

static void eval(const char *input) {
    char buf[256];
    const char *p = input;
    int in_colon_name = 0;  /* next word is a definition name */

    while (*p) {
        /* Skip whitespace */
        while (*p == ' ' || *p == '\t' || *p == '\n') p++;
        if (!*p) break;

        /* Read word */
        int i = 0;
        while (*p && *p != ' ' && *p != '\t' && *p != '\n' && i < 255)
            buf[i++] = *p++;
        buf[i] = '\0';

        if (in_colon_name) {
            /* This word is the name of the definition being compiled */
            dictionary[dict_count].name     = strdup(buf);
            dictionary[dict_count].code     = codebuf + def_start;
            dictionary[dict_count].code_len = 0;  /* filled at ; */
            dictionary[dict_count].is_prim  = 0;
            dict_count++;
            in_colon_name = 0;
            continue;
        }

        if (strcmp(buf, ":") == 0) {
            process_word(":");
            in_colon_name = 1;
            continue;
        }

        if (strcmp(buf, ";") == 0 && compiling) {
            /* Update the dict entry's code_len */
            dict_entry *e = &dictionary[dict_count - 1];
            e->code_len = here - (e->code - codebuf);
            process_word(";");
            continue;
        }

        process_word(buf);
    }

    /* If there's uncommitted anonymous code, execute it */
    /* (In FreeForth, ; at top level executes anonymous code) */
}

/* ================================================================
 * Main — test cases with automated pass/fail
 * ================================================================ */

static int test_count = 0, pass_count = 0;

static void check(const char *desc, long expected_tos) {
    test_count++;
    if (tos == expected_tos) {
        printf("  %s: TOS=%ld — PASSED\n", desc, tos);
        pass_count++;
    } else {
        printf("  %s: TOS=%ld expected %ld — FAILED\n",
               desc, tos, expected_tos);
    }
}

int main(void) {
    dsp = &data_stack[DATA_STACK_SZ / 2];
    tos = 0;
    nos = 0;

    if (init() != 0) {
        fprintf(stderr, "FAILED — init\n");
        return 1;
    }

    printf("Primitives discovered:\n");
    for (int i = 0; i < dict_count; i++) {
        printf("  %-6s %zu bytes\n", dictionary[i].name, dictionary[i].code_len);
    }
    printf("\n");

    /* Test 1: literal */
    eval("42");
    check("42 literal", 42);

    /* Test 2: dup + (inline) */
    eval("21");                 /* reset TOS */
    eval("dup +");
    check("21 dup +", 42);

    /* Test 3: colon definition */
    eval(": double dup + ;");
    eval("21");
    eval("double");
    check(": double dup + ; 21 double", 42);

    /* Test 4: nested colon definitions */
    eval(": quadruple double double ;");
    eval("10");
    eval("quadruple");
    check(": quadruple double double ; 10 quadruple", 40);

    /* Test 5: another nested call */
    eval("7");
    eval("quadruple");
    check("7 quadruple", 28);

    printf("\n%d/%d tests passed\n", pass_count, test_count);
    if (pass_count == test_count) {
        printf("PASSED\n");
        return 0;
    } else {
        printf("FAILED\n");
        return 1;
    }
}
