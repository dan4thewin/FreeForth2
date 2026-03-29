/*
 * Portable FreeForth2 — Experiment 008: FLAGS-based Flow Control
 *
 * Decomposes primitives into:
 *   1. C ALU ops — register-to-register, GCC picks instructions
 *   2. Inline asm macros — WE pick instructions (LEA on x86-64)
 *   3. Composed Forth words — ALU + macros combined
 *
 * FLAGS flow through stack operations because FreeForth (not GCC)
 * controls the stack plumbing, using LEA on x86-64 and post-indexed
 * LDR on ARM64 — both flags-preserving.
 *
 * Conditionals use CPU FLAGS (not stack booleans):
 *   0- (test_tos) sets flags.
 *   0= / 0<> are compile-time Jcc selectors — NO runtime code.
 *   drop is flags-preserving (LEA, not ADD).
 *   IF / UNTIL read the flags set by 0-.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

/* ================================================================
 * Architecture-specific: registers, find_ret, emit_call, emit_load_imm
 * ================================================================ */

#if defined(__aarch64__)

register long    tos  asm("x19");
register long    nos  asm("x20");
register long   *dsp  asm("x21");

static size_t find_ret(uint8_t *start, size_t maxscan)
{
	for (size_t i = 0; i + 3 < maxscan; i += 4) {
		if (start[i]   == 0xC0 && start[i+1] == 0x03 &&
		    start[i+2] == 0x5F && start[i+3] == 0xD6)
			return i;
	}
	return 0;
}

static void emit_call(uint8_t *wbuf, uint8_t *xbuf, size_t *here,
                       uint8_t *target)
{
	uint8_t *exec_site = xbuf + *here;
	int32_t offset = (int32_t)(target - exec_site);
	uint32_t instr = 0x94000000 | ((offset >> 2) & 0x03FFFFFF);
	memcpy(wbuf + *here, &instr, 4);
	*here += 4;
}

static void emit_load_imm(uint8_t *codebuf, size_t *here, long value)
{
	uint64_t v = (uint64_t)value;
	uint32_t instrs[4];
	instrs[0] = 0xD2800013 | (((v >>  0) & 0xFFFF) << 5);
	instrs[1] = 0xF2A00013 | (((v >> 16) & 0xFFFF) << 5);
	instrs[2] = 0xF2C00013 | (((v >> 32) & 0xFFFF) << 5);
	instrs[3] = 0xF2E00013 | (((v >> 48) & 0xFFFF) << 5);
	memcpy(codebuf + *here, instrs, 16);
	*here += 16;
}

/* ---- Per-arch branch emission ---------------------------------- */

/*
 * cond: 0 = EQ (zero), 1 = NE (nonzero)
 * ARM64 B.cond: 0101_0100 imm19 0 cond[3:0]
 */
static size_t emit_cond_forward(uint8_t *buf, size_t *here, int cond)
{
	size_t patch = *here;
	uint32_t instr = 0x54000000 | (cond & 0xF);
	memcpy(buf + *here, &instr, 4);
	*here += 4;
	return patch;
}

static void patch_forward_branch(uint8_t *buf, size_t patch, size_t here)
{
	int32_t offset = (int32_t)(here - patch);
	uint32_t imm19 = (offset >> 2) & 0x7FFFF;
	uint32_t instr;
	memcpy(&instr, buf + patch, 4);
	instr = (instr & 0xFF00001F) | (imm19 << 5);
	memcpy(buf + patch, &instr, 4);
}

static void emit_cond_backward(uint8_t *buf, size_t *here, int cond,
                                size_t target)
{
	int32_t offset = (int32_t)(target - *here);
	uint32_t imm19 = (offset >> 2) & 0x7FFFF;
	uint32_t instr = 0x54000000 | (imm19 << 5) | (cond & 0xF);
	memcpy(buf + *here, &instr, 4);
	*here += 4;
}

#elif defined(__x86_64__)

register long    tos  asm("rbx");
register long    nos  asm("r13");
register long   *dsp  asm("r15");

static size_t find_ret(uint8_t *start, size_t maxscan)
{
	/*
	 * Scan backward — the LAST 0xC3 in the range is the real
	 * RET.  Forward scan can false-match on ModRM bytes (e.g.,
	 * 0xC3 = rbx in MOV r/m64, r64 encoding).
	 */
	for (size_t i = maxscan; i > 0; i--) {
		if (start[i - 1] == 0xC3)
			return i - 1;
	}
	return 0;
}

static void emit_call(uint8_t *wbuf, uint8_t *xbuf, size_t *here,
                       uint8_t *target)
{
	uint8_t *exec_site = xbuf + *here;
	wbuf[(*here)++] = 0xE8;
	int32_t rel = (int32_t)(target - (exec_site + 5));
	memcpy(wbuf + *here, &rel, 4);
	*here += 4;
}

static void emit_load_imm(uint8_t *codebuf, size_t *here, long value)
{
	codebuf[(*here)++] = 0x48;
	codebuf[(*here)++] = 0xBB;
	memcpy(codebuf + *here, &value, 8);
	*here += 8;
}

/* ---- Per-arch branch emission ---------------------------------- */

/*
 * cond: 0 = JZ (0F 84), 1 = JNZ (0F 85)
 * x86-64 Jcc rel32: 0F 8x rel32 (6 bytes total)
 */
static size_t emit_cond_forward(uint8_t *buf, size_t *here, int cond)
{
	buf[(*here)++] = 0x0F;
	buf[(*here)++] = 0x84 | (cond & 1);
	size_t patch = *here;
	int32_t placeholder = 0;
	memcpy(buf + *here, &placeholder, 4);
	*here += 4;
	return patch;
}

static void patch_forward_branch(uint8_t *buf, size_t patch, size_t here)
{
	int32_t rel = (int32_t)(here - (patch + 4));
	memcpy(buf + patch, &rel, 4);
}

static void emit_cond_backward(uint8_t *buf, size_t *here, int cond,
                                size_t target)
{
	buf[(*here)++] = 0x0F;
	buf[(*here)++] = 0x84 | (cond & 1);
	int32_t rel = (int32_t)(target - (*here + 4));
	memcpy(buf + *here, &rel, 4);
	*here += 4;
}

#else
#error "Unsupported architecture"
#endif

/* ================================================================
 * C ALU primitives — register-to-register only
 *
 * GCC picks optimal instructions.  We extract the bytes.
 * These set flags on x86-64 (ADD/SUB always do).  On ARM64
 * they do NOT set flags (ADD without S suffix).  Use the
 * explicit test_tos macro for flag setting on all platforms.
 * ================================================================ */

void __attribute__((noinline)) alu_add(void)  { tos += nos; }
void __attribute__((noinline)) alu_sub(void)  { tos = nos - tos; }
void __attribute__((noinline)) alu_dec(void)  { tos--; }
void __attribute__((noinline)) alu_inc(void)  { tos++; }
void __attribute__((noinline)) alu_end(void)  { asm volatile("nop"); }

/* ================================================================
 * Inline asm macros — WE pick the instructions
 *
 * Stack operations use LEA on x86-64 (flags-preserving) and
 * post-indexed LDR/STR on ARM64.  test_tos sets flags explicitly.
 *
 * Extracted at runtime just like ALU prims — same find_ret scan.
 * ================================================================ */

void __attribute__((noinline)) macro_drop_tos(void)
{
	asm volatile(
#if defined(__x86_64__)
		"mov %%r13, %%rbx\n\t"
		"mov (%%r15), %%r13\n\t"
		"lea 8(%%r15), %%r15"
#elif defined(__aarch64__)
		"mov x19, x20\n\t"
		"ldr x20, [x21], #8"
#endif
		::: "memory"
	);
}

void __attribute__((noinline)) macro_drop_nos(void)
{
	asm volatile(
#if defined(__x86_64__)
		"mov (%%r15), %%r13\n\t"
		"lea 8(%%r15), %%r15"
#elif defined(__aarch64__)
		"ldr x20, [x21], #8"
#endif
		::: "memory"
	);
}

void __attribute__((noinline)) macro_push_nos(void)
{
	asm volatile(
#if defined(__x86_64__)
		"lea -8(%%r15), %%r15\n\t"
		"mov %%r13, (%%r15)"
#elif defined(__aarch64__)
		"str x20, [x21, #-8]!"
#endif
		::: "memory"
	);
}

void __attribute__((noinline)) macro_dup(void)
{
	asm volatile(
#if defined(__x86_64__)
		"lea -8(%%r15), %%r15\n\t"
		"mov %%r13, (%%r15)\n\t"
		"mov %%rbx, %%r13"
#elif defined(__aarch64__)
		"str x20, [x21, #-8]!\n\t"
		"mov x20, x19"
#endif
		::: "memory"
	);
}

void __attribute__((noinline)) macro_swap(void)
{
	asm volatile(
#if defined(__x86_64__)
		"xchg %%rbx, %%r13"
#elif defined(__aarch64__)
		"mov x0, x19\n\t"
		"mov x19, x20\n\t"
		"mov x20, x0"
#endif
		:::
	);
}

void __attribute__((noinline)) macro_test_tos(void)
{
	asm volatile(
#if defined(__x86_64__)
		"test %%rbx, %%rbx"
#elif defined(__aarch64__)
		"tst x19, x19"
#endif
		:::
	);
}

void __attribute__((noinline)) macro_end(void) { asm volatile("nop"); }

/* ================================================================
 * Nonleaf template (from exp 006)
 * ================================================================ */

void __attribute__((noinline)) template_nonleaf(void)
{
	alu_add();
	asm volatile("");
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
 * C reference functions — porting aid
 *
 * NEVER called at runtime.  Disassemble with objdump -d to see
 * what GCC emits for each pattern on your target architecture.
 * ================================================================ */

void __attribute__((noinline, used)) ref_flags_through_drop(void)
{
	/* After test_tos, drop should preserve flags */
	long saved = tos;
	macro_drop_tos();
	if (saved == 0)
		alu_inc();
	asm volatile("");
}

void __attribute__((noinline, used)) ref_loop_pattern(void)
{
	do {
		alu_dec();
	} while (tos != 0);
	asm volatile("");
}

/* ================================================================
 * Compiler state
 * ================================================================ */

#define CODEBUF_SIZE  (64 * 1024)
#define DICT_MAX      256
#define DATA_STACK_SZ 256

static uint8_t *codebuf_w;
static uint8_t *codebuf_x;
static size_t   here;
static long data_stack[DATA_STACK_SZ];

typedef struct {
	const char *name;
	uint8_t    *code;
	size_t      code_len;
	int         is_prim;   /* 1 = inline, 0 = call */
} dict_entry;

static dict_entry dictionary[DICT_MAX];
static int dict_count = 0;
static int compiling = 0;
static size_t def_start = 0;

/* Flow control */
#define FLOW_STACK_SZ 32
static size_t flow_stack[FLOW_STACK_SZ];
static int flow_sp = 0;

/* Jcc selector: 0 = JZ/B.EQ, 1 = JNZ/B.NE */
static int cond_jmp = 0;

/* ================================================================
 * Byte extraction tables
 * ================================================================ */

typedef struct {
	const char *name;
	void       (*func)(void);
} func_info;

/* ALU prims — extracted from C code */
static func_info alu_table[] = {
	{ "alu_add", alu_add },
	{ "alu_sub", alu_sub },
	{ "alu_dec", alu_dec },
	{ "alu_inc", alu_inc },
	{ NULL,      alu_end }
};

/* Inline asm macros — extracted from our hand-picked instructions */
static func_info macro_table[] = {
	{ "drop_tos",  macro_drop_tos  },
	{ "drop_nos",  macro_drop_nos  },
	{ "push_nos",  macro_push_nos  },
	{ "dup",       macro_dup       },
	{ "swap",      macro_swap      },
	{ "test_tos",  macro_test_tos  },
	{ NULL,        macro_end       }
};

/* Discovered bytes */
typedef struct {
	uint8_t *code;
	size_t   len;
} fragment;

enum { ALU_ADD, ALU_SUB, ALU_DEC, ALU_INC, ALU_COUNT };
enum { MAC_DROP_TOS, MAC_DROP_NOS, MAC_PUSH_NOS,
       MAC_DUP, MAC_SWAP, MAC_TEST_TOS, MAC_COUNT };

static fragment alu[ALU_COUNT];
static fragment mac[MAC_COUNT];

/* ================================================================
 * Code buffer allocation
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

/* ================================================================
 * Initialization
 * ================================================================ */

static void emit_bytes(const uint8_t *src, size_t len)
{
	memcpy(codebuf_w + here, src, len);
	here += len;
}

static void dict_add(const char *name, uint8_t *code, size_t len,
                     int is_prim)
{
	dictionary[dict_count].name     = name;
	dictionary[dict_count].code     = code;
	dictionary[dict_count].code_len = len;
	dictionary[dict_count].is_prim  = is_prim;
	dict_count++;
}

static int discover(func_info *table, fragment *out, int count)
{
	for (int i = 0; i < count; i++) {
		uint8_t *start = (uint8_t *)table[i].func;
		uint8_t *next  = (uint8_t *)table[i + 1].func;
		size_t gap = (size_t)(next - start);
		size_t body = find_ret(start, gap);
		if (body == 0) {
			fprintf(stderr, "discover: no RET in %s\n",
			        table[i].name);
			return -1;
		}
		out[i].code = start;
		out[i].len  = body;
	}
	return 0;
}

static int init(void)
{
#ifdef __APPLE__
	codebuf_w = mmap(NULL, CODEBUF_SIZE,
	                 PROT_READ | PROT_WRITE | PROT_EXEC,
	                 MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT,
	                 -1, 0);
	if (codebuf_w == MAP_FAILED) {
		perror("mmap");
		return -1;
	}
	codebuf_x = codebuf_w;
	jit_write_mode();
#else
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

	/* Discover ALU prims and macros */
	if (discover(alu_table, alu, ALU_COUNT) != 0)
		return -1;
	if (discover(macro_table, mac, MAC_COUNT) != 0)
		return -1;
	if (extract_nonleaf_frame() != 0) {
		fprintf(stderr, "init: nonleaf frame extraction failed\n");
		return -1;
	}

	/*
	 * Compose Forth words from ALU + macro fragments.
	 * Each composed word is position-independent (no relative
	 * jumps), so it gets is_prim=1 (inlined when compiled).
	 */
	size_t start;

	/* + = alu_add + drop_nos */
	start = here;
	emit_bytes(alu[ALU_ADD].code, alu[ALU_ADD].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("+", codebuf_x + start, here - start, 1);

	/* - = alu_sub + drop_nos */
	start = here;
	emit_bytes(alu[ALU_SUB].code, alu[ALU_SUB].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("-", codebuf_x + start, here - start, 1);

	/* 1- = alu_dec */
	start = here;
	emit_bytes(alu[ALU_DEC].code, alu[ALU_DEC].len);
	dict_add("1-", codebuf_x + start, here - start, 1);

	/* 1+ = alu_inc */
	start = here;
	emit_bytes(alu[ALU_INC].code, alu[ALU_INC].len);
	dict_add("1+", codebuf_x + start, here - start, 1);

	/* drop = macro_drop_tos */
	start = here;
	emit_bytes(mac[MAC_DROP_TOS].code, mac[MAC_DROP_TOS].len);
	dict_add("drop", codebuf_x + start, here - start, 1);

	/* dup = macro_dup */
	start = here;
	emit_bytes(mac[MAC_DUP].code, mac[MAC_DUP].len);
	dict_add("dup", codebuf_x + start, here - start, 1);

	/* swap = macro_swap */
	start = here;
	emit_bytes(mac[MAC_SWAP].code, mac[MAC_SWAP].len);
	dict_add("swap", codebuf_x + start, here - start, 1);

	/* 0- = macro_test_tos (sets flags, no stack change) */
	start = here;
	emit_bytes(mac[MAC_TEST_TOS].code, mac[MAC_TEST_TOS].len);
	dict_add("0-", codebuf_x + start, here - start, 1);

	return 0;
}

/* ================================================================
 * Code emission helpers
 * ================================================================ */

static void emit_inline(dict_entry *e)
{
	emit_bytes(e->code, e->code_len);
}

static void emit_literal(long value)
{
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

	/* ---- Jcc selectors (compile-time only, NO runtime code) ---- */

	if (strcmp(word, "0=") == 0) {
		if (compiling)
			cond_jmp = 0;  /* JZ / B.EQ */
		return;
	}

	if (strcmp(word, "0<>") == 0) {
		if (compiling)
			cond_jmp = 1;  /* JNZ / B.NE */
		return;
	}

	/* ---- Flow control ---- */

	if (strcmp(word, "IF") == 0) {
		if (!compiling)
			return;
		/*
		 * FLAGS were set by 0- (test_tos).
		 * User wrote "drop" to consume the tested value.
		 * drop is flags-preserving (LEA on x86-64).
		 * Emit INVERTED conditional forward branch.
		 */
		int inverted = cond_jmp ^ 1;
		flow_stack[flow_sp++] =
			emit_cond_forward(codebuf_w, &here, inverted);
		return;
	}

	if (strcmp(word, "THEN") == 0) {
		if (!compiling || flow_sp == 0)
			return;
		patch_forward_branch(codebuf_w, flow_stack[--flow_sp], here);
		return;
	}

	if (strcmp(word, "BEGIN") == 0) {
		if (!compiling)
			return;
		flow_stack[flow_sp++] = here;
		return;
	}

	if (strcmp(word, "UNTIL") == 0) {
		if (!compiling || flow_sp == 0)
			return;
		/* Same inversion as IF: loop when condition FALSE */
		int inverted = cond_jmp ^ 1;
		emit_cond_backward(codebuf_w, &here, inverted,
		                   flow_stack[--flow_sp]);
		return;
	}

	/* ---- Dictionary lookup ---- */

	dict_entry *e = dict_find(word);
	if (e) {
		if (compiling) {
			if (e->is_prim)
				emit_inline(e);
			else
				emit_call(codebuf_w, codebuf_x,
				          &here, e->code);
		}
		else {
			size_t save = here;
			emit_bytes(prologue_buf, prologue_len);
			if (e->is_prim)
				emit_inline(e);
			else
				emit_call(codebuf_w, codebuf_x,
				          &here, e->code);
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

	printf("ALU prims:\n");
	for (int i = 0; i < ALU_COUNT; i++)
		printf("  %-10s %zu bytes\n",
		       alu_table[i].name, alu[i].len);
	printf("Stack macros:\n");
	for (int i = 0; i < MAC_COUNT; i++)
		printf("  %-10s %zu bytes\n",
		       macro_table[i].name, mac[i].len);
	printf("Composed words:\n");
	for (int i = 0; i < dict_count; i++)
		printf("  %-6s %zu bytes%s\n",
		       dictionary[i].name, dictionary[i].code_len,
		       dictionary[i].is_prim ? " (inline)" : " (call)");
	printf("Nonleaf frame: prologue %zu, epilogue %zu\n\n",
	       prologue_len, epilogue_len);

	/* --- Basic arithmetic --- */

	eval("42");
	check("literal", 42);

	eval("21");
	eval("dup +");
	check("dup +", 42);

	eval("10");
	eval("3");
	eval("-");
	check("10 3 -", 7);

	eval("10");
	eval("1-");
	check("10 1-", 9);

	/* --- Colon definitions --- */

	eval(": double dup + ;");
	eval("21");
	eval("double");
	check(": double", 42);

	eval(": quadruple double double ;");
	eval("10");
	eval("quadruple");
	check(": quadruple (nested)", 40);

	/* --- FLAGS-based IF...THEN --- */

	/* IF taken: 0 is zero, so "0= IF" body executes */
	eval(": test-if-take 0 0- 0= drop IF drop 42 THEN ;");
	eval("99");
	eval("test-if-take");
	check("IF taken (0=)", 42);

	/* IF not taken: 5 is nonzero, so "0= IF" body skipped */
	eval(": test-if-skip 5 0- 0= drop IF drop 42 THEN ;");
	eval("99");
	eval("test-if-skip");
	check("IF not taken (0=)", 99);

	/* IF with 0<>: 5 is nonzero, so "0<> IF" body executes */
	eval(": test-if-nz 5 0- 0<> drop IF drop 77 THEN ;");
	eval("99");
	eval("test-if-nz");
	check("IF taken (0<>)", 77);

	/* IF with 0<>: 0 is zero, so "0<> IF" body skipped */
	eval(": test-if-nz2 0 0- 0<> drop IF drop 77 THEN ;");
	eval("99");
	eval("test-if-nz2");
	check("IF not taken (0<>)", 99);

	/* --- FLAGS-based BEGIN...UNTIL --- */

	/* Count down from 5 to 0.  0= UNTIL = "until zero" = loop while NZ */
	eval(": countdown 5 BEGIN 1 - dup 0- 0= drop UNTIL ;");
	eval("countdown");
	check("BEGIN..UNTIL countdown", 0);

	/* Accumulate: sum 1+2+3+4+5 using counter on return stack */
	eval(": sum5 0 5 BEGIN swap 1 + swap 1 - dup 0- 0= drop UNTIL drop ;");
	eval("sum5");
	check("BEGIN..UNTIL sum5", 5);

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
