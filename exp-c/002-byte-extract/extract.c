/*
 * Portable FreeForth2 — Experiment 002: Runtime Byte Extraction
 *
 * Question: Can we read the machine code bytes of our own
 * functions at runtime, without object-file surgery?
 *
 * Approach: Each primitive is a normal C function whose address is
 * the start of its code.  We use symbol sizes (via a size sentinel
 * or linker tricks) OR simply place functions in known order and
 * measure the gap.  For this experiment, we use a simpler approach:
 * compile with -ffunction-sections and use the symbol table sizes,
 * OR we just hardcode the known sizes from exp 001 and verify.
 *
 * Actually, simplest approach: we compile all primitives plus a
 * sentinel, all marked noinline, and rely on order within a single
 * TU.  GCC with -O2 preserves source order for non-static functions.
 *
 * Compile:  gcc -O2 -fomit-frame-pointer -fcf-protection=none -o extract extract.c
 * Run:      ./extract
 */

#include <stdio.h>
#include <stdint.h>

/* --- Register pinning (x86-64) --- */
register long    tos  asm("rbx");
register long    nos  asm("r13");
register long   *dsp  asm("r15");

/* --- Primitives --- */

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

/* Sentinel — marks the end of the last primitive */
void __attribute__((noinline)) prim_end_sentinel(void) {
    asm volatile("nop");
}

/* --- Primitive table --- */

typedef struct {
    const char *name;
    void       (*func)(void);
} prim_entry;

static prim_entry prims[] = {
    { "add",   prim_add   },
    { "drop",  prim_drop  },
    { "dup",   prim_dup   },
    { "fetch", prim_fetch },
    { "store", prim_store },
    { NULL,    prim_end_sentinel }
};

static void dump_prim(const char *name, uint8_t *start, size_t size) {
    printf("%-6s (%2zu bytes): ", name, size);
    for (size_t i = 0; i < size; i++)
        printf("%02x ", start[i]);
    printf("\n");
}

int main(void) {
    printf("=== Runtime byte extraction ===\n\n");

    int ok = 1;
    for (int i = 0; prims[i].name != NULL; i++) {
        uint8_t *start = (uint8_t *)prims[i].func;
        uint8_t *end   = (uint8_t *)prims[i + 1].func;
        size_t   size  = end - start;

        if (size > 64) {
            printf("%-6s: ERROR — size %zu too large (padding/reorder?)\n",
                   prims[i].name, size);
            ok = 0;
            continue;
        }

        /* Find RET (0xC3) to get true code size */
        size_t code_size = 0;
        for (size_t j = 0; j < size; j++) {
            if (start[j] == 0xC3) {
                code_size = j + 1;
                break;
            }
        }

        if (code_size == 0) {
            printf("%-6s: ERROR — no RET found in %zu bytes\n",
                   prims[i].name, size);
            ok = 0;
            continue;
        }

        dump_prim(prims[i].name, start, code_size);
    }

    printf("\n%s\n", ok ? "PASSED" : "FAILED");
    return ok ? 0 : 1;
}
