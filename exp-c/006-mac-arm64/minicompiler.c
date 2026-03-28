/*
 * Portable FreeForth2 — Experiment 006: Mac ARM64 native test
 *
 * The mini-compiler from exp 004, made portable to ARM64 (macOS).
 * Architecture-specific pieces isolated into an arch header section.
 *
 * On ARM64, the calling convention is:
 *   BL  = branch-with-link (CALL equivalent), 4 bytes, PC-relative
 *   RET = return, encoded as 0xD65F03C0
 *   Literal: MOVZ + MOVK sequence to build 64-bit immediate
 *
 * On x86-64:
 *   CALL rel32 = 0xE8 + 4-byte offset
 *   RET = 0xC3
 *   Literal: REX.W MOV imm64 = 0x48 0xBB + 8 bytes
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

/* ================================================================
 * Architecture-specific register pinning and code emission
 * ================================================================ */

#if defined(__aarch64__)

register long    tos  asm("x19");
register long    nos  asm("x20");
register long   *dsp  asm("x21");

/* ARM64 BL = 0x94000000 | (imm26) — PC-relative, 4 bytes */

/* Find RET instruction in a byte sequence (ARM64: 4-byte pattern) */
static size_t find_ret(uint8_t *start, size_t maxscan)
{
	for (size_t i = 0; i + 3 < maxscan; i += 4) {
		if (start[i]   == 0xC0 && start[i+1] == 0x03 &&
		    start[i+2] == 0x5F && start[i+3] == 0xD6)
			return i;
	}
	return 0;
}

static void emit_call(uint8_t *wbuf, uint8_t *xbuf, size_t *here, uint8_t *target)
{
	/* Write bytes to wbuf, but calculate offset from xbuf (execution addr) */
	uint8_t *exec_site = xbuf + *here;
	int32_t offset = (int32_t)(target - exec_site);
	/* BL encodes offset>>2 in bits 25:0 */
	uint32_t instr = 0x94000000 | ((offset >> 2) & 0x03FFFFFF);
	memcpy(wbuf + *here, &instr, 4);
	*here += 4;
}

/*
 * ARM64 literal: we need dup body (to push current TOS), then
 * load an immediate into x19 (TOS).  For a 64-bit value:
 *   MOVZ x19, #(imm16_0), LSL #0
 *   MOVK x19, #(imm16_1), LSL #16
 *   MOVK x19, #(imm16_2), LSL #32
 *   MOVK x19, #(imm16_3), LSL #48
 * Each is 4 bytes = 16 bytes total.
 */
static void emit_load_imm(uint8_t *codebuf, size_t *here, long value)
{
	uint64_t v = (uint64_t)value;
	uint32_t instrs[4];

	/* MOVZ x19, #imm16, LSL #0 */
	instrs[0] = 0xD2800013 | (((v >>  0) & 0xFFFF) << 5);
	/* MOVK x19, #imm16, LSL #16 */
	instrs[1] = 0xF2A00013 | (((v >> 16) & 0xFFFF) << 5);
	/* MOVK x19, #imm16, LSL #32 */
	instrs[2] = 0xF2C00013 | (((v >> 32) & 0xFFFF) << 5);
	/* MOVK x19, #imm16, LSL #48 */
	instrs[3] = 0xF2E00013 | (((v >> 48) & 0xFFFF) << 5);

	memcpy(codebuf + *here, instrs, 16);
	*here += 16;
}

#elif defined(__x86_64__)

register long    tos  asm("rbx");
register long    nos  asm("r13");
register long   *dsp  asm("r15");

static size_t find_ret(uint8_t *start, size_t maxscan)
{
	for (size_t i = 0; i < maxscan; i++) {
		if (start[i] == 0xC3)
			return i;
	}
	return 0;
}

static void emit_call(uint8_t *wbuf, uint8_t *xbuf, size_t *here, uint8_t *target)
{
	/* Write bytes to wbuf, calculate offset from xbuf (execution addr) */
	uint8_t *exec_site = xbuf + *here;
	wbuf[(*here)++] = 0xE8;
	int32_t rel = (int32_t)(target - (exec_site + 5));
	memcpy(wbuf + *here, &rel, 4);
	*here += 4;
}

/* x86-64: movabs rbx, imm64 = 48 BB + 8 bytes */
static void emit_load_imm(uint8_t *codebuf, size_t *here, long value)
{
	codebuf[(*here)++] = 0x48;
	codebuf[(*here)++] = 0xBB;
	memcpy(codebuf + *here, &value, 8);
	*here += 8;
}

#else
#error "Unsupported architecture"
#endif

/* ================================================================
 * Primitives — portable C, architecture-selected registers
 * ================================================================ */

void __attribute__((noinline)) prim_add(void)  { tos += nos; nos = *dsp; dsp++; }
void __attribute__((noinline)) prim_drop(void) { tos = nos; nos = *dsp; dsp++; }
void __attribute__((noinline)) prim_dup(void)  { dsp--; *dsp = nos; nos = tos; }
void __attribute__((noinline)) prim_fetch(void) { tos = *(long *)tos; }
void __attribute__((noinline)) prim_store(void)
{
	*(long *)tos = nos;
	tos = *dsp;
	nos = *(dsp + 1);
	dsp += 2;
}
void __attribute__((noinline)) prim_end_sentinel(void) { asm volatile("nop"); }

/*
 * Non-leaf function template — GCC emits save/restore of the link
 * register (LR).  We extract the prologue and epilogue bytes and use
 * them to frame colon definitions so nested CALLs work correctly.
 * On x86-64 CALL/RET manage the return address via the stack, so the
 * prologue is empty and epilogue is just RET.  On ARM64 BL writes x30
 * without pushing, so GCC emits STP/LDP to save/restore it.
 */
void __attribute__((noinline)) template_nonleaf(void)
{
	prim_dup();
	asm volatile("");  /* prevent tail-call optimization */
}
void __attribute__((noinline)) template_nonleaf_end(void)
{
	asm volatile("nop");
}

static uint8_t prologue_buf[64];
static size_t  prologue_len;
static uint8_t epilogue_buf[64];
static size_t  epilogue_len;

static int extract_nonleaf_frame(void)
{
	uint8_t *start = (uint8_t *)template_nonleaf;
	uint8_t *limit = (uint8_t *)template_nonleaf_end;
	size_t span = (size_t)(limit - start);

#if defined(__aarch64__)
	size_t first_bl = span;
	for (size_t i = 0; i + 3 < span; i += 4) {
		uint32_t w;
		memcpy(&w, start + i, 4);
		if ((w & 0xFC000000) == 0x94000000) {
			first_bl = i;
			break;
		}
	}
	if (first_bl == span)
		return -1;

	size_t ret_off = span;
	for (size_t i = first_bl + 4; i + 3 < span; i += 4) {
		uint32_t w;
		memcpy(&w, start + i, 4);
		if (w == 0xD65F03C0) {
			ret_off = i;
			break;
		}
	}
	if (ret_off == span)
		return -1;

	prologue_len = first_bl;
	memcpy(prologue_buf, start, prologue_len);
	size_t epi_start = first_bl + 4;
	epilogue_len = (ret_off + 4) - epi_start;
	memcpy(epilogue_buf, start + epi_start, epilogue_len);

#elif defined(__x86_64__)
	size_t first_call = span;
	for (size_t i = 0; i < span; i++) {
		if (start[i] == 0xE8) {
			first_call = i;
			break;
		}
	}
	if (first_call == span)
		return -1;

	size_t ret_off = span;
	for (size_t i = first_call + 5; i < span; i++) {
		if (start[i] == 0xC3) {
			ret_off = i;
			break;
		}
	}
	if (ret_off == span)
		return -1;

	prologue_len = first_call;
	memcpy(prologue_buf, start, prologue_len);
	size_t epi_start = first_call + 5;
	epilogue_len = (ret_off + 1) - epi_start;
	memcpy(epilogue_buf, start + epi_start, epilogue_len);
#endif

	return 0;
}

/* ================================================================
 * Compiler state
 * ================================================================ */

#define CODEBUF_SIZE  (64 * 1024)
#define DICT_MAX      256
#define DATA_STACK_SZ 256

static uint8_t *codebuf_w;   /* writable view — compiler writes here */
static uint8_t *codebuf_x;   /* executable view — CPU runs from here */
static size_t   here;
static long data_stack[DATA_STACK_SZ];

typedef struct {
	const char *name;
	uint8_t    *code;
	size_t      code_len;  /* body without RET */
	int         is_prim;
} dict_entry;

static dict_entry dictionary[DICT_MAX];
static int dict_count = 0;
static int compiling = 0;
static size_t def_start = 0;

/* Primitive discovery table */
typedef struct {
	const char *name;
	void       (*func)(void);
} prim_info;

static prim_info prim_table[] = {
	{ "+",    prim_add   },
	{ "drop", prim_drop  },
	{ "dup",  prim_dup   },
	{ "@",    prim_fetch },
	{ "!",    prim_store },
	{ NULL,   prim_end_sentinel }
};

/* ================================================================
 * Code buffer allocation
 *
 * Linux:  Dual mapping — two virtual addresses over the same
 *         physical memory.  codebuf_w is RW, codebuf_x is RX.
 *         No toggling, no icache flush needed.
 *
 * macOS:  MAP_JIT — single mapping that toggles between W and X
 *         via pthread_jit_write_protect_np().  codebuf_w == codebuf_x
 *         (same pointer, different modes).  Dual mapping doesn't
 *         work — Apple's kernel rejects PROT_EXEC on MAP_SHARED.
 * ================================================================ */

#ifdef __linux__
#include <sys/syscall.h>
static int memfd_create_(const char *name, unsigned int flags)
{
	return syscall(SYS_memfd_create, name, flags);
}
#endif

#ifdef __APPLE__
#include <pthread.h>
#include <libkern/OSCacheControl.h>

static void jit_write_mode(void) { pthread_jit_write_protect_np(0); }
static void jit_exec_mode(void)
{
	pthread_jit_write_protect_np(1);
	sys_icache_invalidate(codebuf_x, CODEBUF_SIZE);
}
#else
static void jit_write_mode(void) {}
static void jit_exec_mode(void) {}
#endif

#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif

static int init(void)
{
#ifdef __APPLE__
	/* macOS: single MAP_JIT mapping, toggled between W and X */
	codebuf_w = mmap(NULL, CODEBUF_SIZE,
	                 PROT_READ | PROT_WRITE | PROT_EXEC,
	                 MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT,
	                 -1, 0);
	if (codebuf_w == MAP_FAILED) {
		perror("mmap");
		return -1;
	}
	codebuf_x = codebuf_w;  /* same pointer, toggled modes */
	jit_write_mode();
#else
	/* Linux: dual mapping */
	int fd = memfd_create_("ffcode", 0);
	if (fd == -1) {
		perror("memfd_create");
		return -1;
	}
	if (ftruncate(fd, CODEBUF_SIZE) == -1) {
		perror("ftruncate");
		close(fd);
		return -1;
	}
	codebuf_w = mmap(NULL, CODEBUF_SIZE, PROT_READ | PROT_WRITE,
	                 MAP_SHARED, fd, 0);
	codebuf_x = mmap(NULL, CODEBUF_SIZE, PROT_READ | PROT_EXEC,
	                 MAP_SHARED, fd, 0);
	close(fd);
	if (codebuf_w == MAP_FAILED || codebuf_x == MAP_FAILED) {
		perror("mmap");
		return -1;
	}
#endif
	here = 0;

	for (int i = 0; prim_table[i].name != NULL; i++) {
		uint8_t *start = (uint8_t *)prim_table[i].func;
		uint8_t *next  = (uint8_t *)prim_table[i + 1].func;
		size_t   gap   = next - start;
		size_t   body  = find_ret(start, gap);

		if (body == 0) {
			fprintf(stderr, "init: no RET in %s\n",
			        prim_table[i].name);
			return -1;
		}

		dictionary[dict_count].name     = prim_table[i].name;
		dictionary[dict_count].code     = start;
		dictionary[dict_count].code_len = body;
		dictionary[dict_count].is_prim  = 1;
		dict_count++;
	}

	if (extract_nonleaf_frame() != 0) {
		fprintf(stderr, "init: nonleaf frame extraction failed\n");
		return -1;
	}

	return 0;
}

/* ================================================================
 * Code emission (portable)
 * ================================================================ */

static void emit_bytes(const uint8_t *src, size_t len)
{
	memcpy(codebuf_w + here, src, len);
	here += len;
}

static void emit_inline(dict_entry *e)
{
	emit_bytes(e->code, e->code_len);
}

static void emit_literal(long value)
{
	/* dup body to push current TOS */
	dict_entry *dup_entry = NULL;
	for (int i = 0; i < dict_count; i++) {
		if (strcmp(dictionary[i].name, "dup") == 0) {
			dup_entry = &dictionary[i];
			break;
		}
	}
	if (dup_entry)
		emit_inline(dup_entry);

	emit_load_imm(codebuf_w, &here, value);
}

/* ================================================================
 * Dictionary and interpreter
 * ================================================================ */

static dict_entry *dict_find(const char *name)
{
	for (int i = dict_count - 1; i >= 0; i--) {
		if (strcmp(dictionary[i].name, name) == 0)
			return &dictionary[i];
	}
	return NULL;
}

static int is_number(const char *s, long *val)
{
	char *end;
	*val = strtol(s, &end, 10);
	return (*end == '\0' && end != s);
}

static void process_word(const char *word)
{
	long num;

	if (strcmp(word, ":") == 0) {
		compiling = 1;
		def_start = here;
		return;
	}

	if (strcmp(word, ";") == 0) {
		if (!compiling)
			return;
		emit_bytes(epilogue_buf, epilogue_len);
		compiling = 0;
		return;
	}

	if (strcmp(word, ".") == 0) {
		if (!compiling) {
			printf("%ld ", tos);
			tos = nos;
			nos = *dsp;
			dsp++;
		}
		return;
	}

	if (strcmp(word, "cr") == 0) {
		if (!compiling)
			printf("\n");
		return;
	}

	dict_entry *e = dict_find(word);
	if (e) {
		if (compiling) {
			if (e->is_prim)
				emit_inline(e);
			else
				emit_call(codebuf_w, codebuf_x, &here, e->code);
		}
		else {
			/*
			 * Interpret mode: wrap in prologue/epilogue and
			 * execute.  Prims are inlined (position-independent).
			 * Non-prims must be CALLed — copying their body
			 * would break relative jump offsets.
			 */
			size_t save = here;
			emit_bytes(prologue_buf, prologue_len);
			if (e->is_prim)
				emit_inline(e);
			else
				emit_call(codebuf_w, codebuf_x, &here,
				          e->code);
			emit_bytes(epilogue_buf, epilogue_len);
			jit_exec_mode();
			((void (*)(void))(codebuf_x + save))();
			jit_write_mode();
			here = save;
		}
		return;
	}

	if (is_number(word, &num)) {
		if (compiling)
			emit_literal(num);
		else {
			dsp--;
			*dsp = nos;
			nos = tos;
			tos = num;
		}
		return;
	}

	fprintf(stderr, "? %s\n", word);
}

static void eval(const char *input)
{
	char buf[256];
	const char *p = input;
	int in_colon_name = 0;

	while (*p) {
		while (*p == ' ' || *p == '\t' || *p == '\n')
			p++;
		if (!*p)
			break;

		int i = 0;
		while (*p && *p != ' ' && *p != '\t' && *p != '\n' && i < 255)
			buf[i++] = *p++;
		buf[i] = '\0';

		if (in_colon_name) {
			dictionary[dict_count].name     = strdup(buf);
			dictionary[dict_count].code     = codebuf_x + def_start;
			dictionary[dict_count].code_len = 0;
			dictionary[dict_count].is_prim  = 0;
			dict_count++;
			in_colon_name = 0;
			emit_bytes(prologue_buf, prologue_len);
			continue;
		}

		if (strcmp(buf, ":") == 0) {
			process_word(":");
			in_colon_name = 1;
			continue;
		}

		if (strcmp(buf, ";") == 0 && compiling) {
			process_word(";");
			dict_entry *e = &dictionary[dict_count - 1];
			e->code_len = here - (e->code - codebuf_x);
			continue;
		}

		process_word(buf);
	}
}

/* ================================================================
 * Tests
 * ================================================================ */

static int test_count = 0, pass_count = 0;

static void check(const char *desc, long expected_tos)
{
	test_count++;
	if (tos == expected_tos) {
		printf("  %s: TOS=%ld -- PASSED\n", desc, tos);
		pass_count++;
	}
	else
		printf("  %s: TOS=%ld expected %ld -- FAILED\n",
		       desc, tos, expected_tos);
}

int main(void)
{
	dsp = &data_stack[DATA_STACK_SZ / 2];
	tos = 0;
	nos = 0;

	if (init() != 0) {
		fprintf(stderr, "FAILED — init\n");
		return 1;
	}

	printf("Architecture: %s\n",
#if defined(__aarch64__)
	       "ARM64"
#elif defined(__x86_64__)
	       "x86-64"
#else
	       "unknown"
#endif
	);

	printf("Primitives discovered:\n");
	for (int i = 0; i < dict_count; i++)
		printf("  %-6s %zu bytes\n",
		       dictionary[i].name, dictionary[i].code_len);
	printf("Nonleaf frame: prologue %zu bytes, epilogue %zu bytes\n\n",
	       prologue_len, epilogue_len);

	eval("42");
	check("42 literal", 42);

	eval("21");
	eval("dup +");
	check("21 dup +", 42);

	eval(": double dup + ;");
	eval("21");
	eval("double");
	check(": double dup + ; 21 double", 42);

	eval(": quadruple double double ;");
	eval("10");
	eval("quadruple");
	check(": quadruple ; 10 quadruple", 40);

	eval("7");
	eval("quadruple");
	check("7 quadruple", 28);

	printf("\n%d/%d tests passed\n", pass_count, test_count);
	if (pass_count == test_count) {
		printf("PASSED\n");
		return 0;
	}
	else {
		printf("FAILED\n");
		return 1;
	}
}
