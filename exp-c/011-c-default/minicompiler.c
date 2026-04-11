/*
 * Portable FreeForth2 — Experiment 011: C-default, asm-optional
 *
 * Builds on exp 010 (auto-calibrating stack operations).
 *
 * KEY PRINCIPLE: C is the default.  Asm is the escape hatch.
 *
 * A new port starts with ZERO asm.  The C sacrifice functions and
 * C stack operations are the ONLY source.  At init time, calibration
 * tests whether GCC's output preserves CPU flags.  If it does, the
 * C version is used.  If not, the system looks for an asm override
 * in an optional per-architecture header (overrides_x86_64.h, etc.).
 * If no override exists, it's a hard error with a clear diagnostic.
 *
 * On ARM64, no overrides file is needed — C works for everything.
 * On x86-64, overrides exist for the 3 stack ops where GCC emits
 * ADD (which clobbers flags) instead of LEA.
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

/* ARM64 B.cond encoding: condition in bits [3:0] */
#define JCC_EQ  0x0
#define JCC_NE  0x1
#define JCC_MI  0x4
#define JCC_GT  0xC
#define JCC_LT  0xB
#define JCC_GE  0xA

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

static int invert_jcc(int cond) { return cond ^ 1; }

#elif defined(__x86_64__)

register long    tos  asm("rbx");
register long    nos  asm("r13");
register long   *dsp  asm("r15");

static size_t find_ret(uint8_t *start, size_t maxscan)
{
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

/* x86-64 Jcc near: 0F 8x rel32 */
#define JCC_EQ  0x84
#define JCC_NE  0x85
#define JCC_MI  0x88
#define JCC_GT  0x8F
#define JCC_LT  0x8C
#define JCC_GE  0x8D

static size_t emit_cond_forward(uint8_t *buf, size_t *here, int cond)
{
	buf[(*here)++] = 0x0F;
	buf[(*here)++] = (uint8_t)cond;
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
	buf[(*here)++] = (uint8_t)cond;
	int32_t rel = (int32_t)(target - (*here + 4));
	memcpy(buf + *here, &rel, 4);
	*here += 4;
}

static int invert_jcc(int cond) { return cond ^ 1; }

#else
#error "Unsupported architecture"
#endif

/* ================================================================
 * C ALU primitives — TWO versions of each
 *
 * "plain":     just the operation
 * "sacrifice": operation + `return tos == 0` to coerce flag-setting
 *
 * On x86-64, plain already sets flags (SUB/ADD always do).
 * On ARM64, sacrifice coerces SUBS/ADDS (flag-setting variants).
 *
 * These are the ONLY ALU source.  No per-arch asm alternatives.
 * ================================================================ */

void __attribute__((noinline)) alu_add_p(void) { tos += nos; }
void __attribute__((noinline)) alu_sub_p(void) { tos = nos - tos; }
void __attribute__((noinline)) alu_dec_p(void) { tos--; }
void __attribute__((noinline)) alu_inc_p(void) { tos++; }
void __attribute__((noinline)) alu_and_p(void) { tos &= nos; }
void __attribute__((noinline)) alu_or_p(void)  { tos |= nos; }
void __attribute__((noinline)) alu_xor_p(void) { tos ^= nos; }
void __attribute__((noinline)) alu_neg_p(void) { tos = -tos; }
void __attribute__((noinline)) alu_end_p(void) { asm volatile("nop"); }

long __attribute__((noinline)) alu_add_s(void) { tos += nos;         return tos == 0; }
long __attribute__((noinline)) alu_sub_s(void) { tos = nos - tos;    return tos == 0; }
long __attribute__((noinline)) alu_dec_s(void) { tos--;              return tos == 0; }
long __attribute__((noinline)) alu_inc_s(void) { tos++;              return tos == 0; }
long __attribute__((noinline)) alu_and_s(void) { tos &= nos;         return tos == 0; }
long __attribute__((noinline)) alu_or_s(void)  { tos |= nos;         return tos == 0; }
long __attribute__((noinline)) alu_xor_s(void) { tos ^= nos;         return tos == 0; }
long __attribute__((noinline)) alu_neg_s(void) { tos = -tos;         return tos == 0; }
void __attribute__((noinline)) alu_end_s(void) { asm volatile("nop"); }

/* Non-consuming binary CMP (sacrifice only) */
long __attribute__((noinline)) alu_cmp_s(void) { return nos == tos; }
void __attribute__((noinline)) alu_cmp_end(void) { asm volatile("nop"); }

/* ================================================================
 * C-compiled stack operations — the DEFAULT for all architectures
 *
 * No inline asm.  GCC picks instructions.  If the output clobbers
 * flags, the calibration loop will detect it and look for an asm
 * override.  If none exists, it's a hard error.
 * ================================================================ */

void __attribute__((noinline)) c_drop_tos(void)
{
	tos = nos;
	nos = *dsp;
	dsp++;
}

void __attribute__((noinline)) c_drop_nos(void)
{
	nos = *dsp;
	dsp++;
}

void __attribute__((noinline)) c_push_nos(void)
{
	--dsp;
	*dsp = nos;
}

void __attribute__((noinline)) c_dup(void)
{
	--dsp;
	*dsp = nos;
	nos = tos;
}

void __attribute__((noinline)) c_swap(void)
{
	long t = tos;
	tos = nos;
	nos = t;
}

void __attribute__((noinline)) c_over(void)
{
	--dsp;
	*dsp = nos;
	long t = tos;
	tos = nos;
	nos = t;
}

void __attribute__((noinline)) c_2drop(void)
{
	tos = *dsp;
	nos = dsp[1];
	dsp += 2;
}

/* test_tos via C sacrifice — works on both arches */
long __attribute__((noinline)) c_test_tos_s(void) { return tos == 0; }
void __attribute__((noinline)) c_test_tos_end(void) { asm volatile("nop"); }

void __attribute__((noinline)) c_end(void) { asm volatile("nop"); }

/* ================================================================
 * Asm overrides — conditionally included per architecture
 *
 * If overrides_<arch>.h exists, it defines HAS_ASM_OVERRIDES and
 * provides an override_table[].  If it doesn't exist, there are
 * no overrides — C must work for everything on that arch.
 * ================================================================ */

#if defined(__x86_64__) && __has_include("overrides_x86_64.h")
#include "overrides_x86_64.h"
#elif defined(__aarch64__) && __has_include("overrides_aarch64.h")
#include "overrides_aarch64.h"
#endif

#ifndef HAS_ASM_OVERRIDES
#define HAS_ASM_OVERRIDES 0
/* Empty override table — nothing to fall back to */
typedef struct {
	const char *name;
	void       (*func)(void);
} override_info;
static override_info override_table[] = {
	{ NULL, NULL }, { NULL, NULL }, { NULL, NULL },
	{ NULL, NULL }, { NULL, NULL }, { NULL, NULL },
	{ NULL, NULL }, { NULL, NULL }, { NULL, NULL },
};
#endif

/* ================================================================
 * Nonleaf template (from exp 006)
 * ================================================================ */

void __attribute__((noinline)) template_nonleaf(void)
{
	alu_add_p();
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

/* Jcc selector */
static int cond_jmp = JCC_EQ;

/* ================================================================
 * Byte extraction
 * ================================================================ */

typedef struct {
	uint8_t *code;
	size_t   len;
} fragment;

enum {
	MAC_DROP_TOS, MAC_DROP_NOS, MAC_PUSH_NOS,
	MAC_DUP, MAC_SWAP, MAC_TEST_TOS, MAC_OVER,
	MAC_2DROP, MAC_COUNT
};

static const char *mac_names[] = {
	"drop_tos", "drop_nos", "push_nos", "dup",
	"swap", "test_tos", "over", "2drop"
};

enum {
	ALU_ADD, ALU_SUB, ALU_DEC, ALU_INC,
	ALU_AND, ALU_OR, ALU_XOR, ALU_NEG,
	ALU_CMP, ALU_COUNT
};

static fragment alu[ALU_COUNT];
static fragment mac[MAC_COUNT];           /* selected (C or asm override) */
static fragment c_mac[MAC_COUNT];         /* C-compiled versions */
static fragment ov_mac[MAC_COUNT];        /* asm override versions (if any) */
static const char *mac_source[MAC_COUNT]; /* "C" or "asm" for diagnostics */

static int extract_one(void *func, void *next, fragment *out)
{
	uint8_t *start = (uint8_t *)func;
	size_t gap = (size_t)((uint8_t *)next - start);
	size_t body = find_ret(start, gap);
	if (body == 0)
		return -1;
	out->code = start;
	out->len  = body;
	return 0;
}

/*
 * Self-calibrating ALU extraction.
 *
 * Compare plain vs sacrifice.  If plain bytes are found as a
 * subsequence inside sacrifice, the arch already sets flags (x86-64).
 * Otherwise the sacrifice changed the instruction (ARM64 SUB→SUBS);
 * use sacrifice bytes trimmed to plain length.
 */
static int extract_alu_calibrated(void *func_plain, void *next_plain,
                                  void *func_sacrifice, void *next_sacrifice,
                                  fragment *out, const char *name)
{
	fragment plain, sacrifice;

	if (extract_one(func_plain, next_plain, &plain) != 0) {
		fprintf(stderr, "extract: no RET in %s (plain)\n", name);
		return -1;
	}
	if (extract_one(func_sacrifice, next_sacrifice, &sacrifice) != 0) {
		fprintf(stderr, "extract: no RET in %s (sacrifice)\n", name);
		return -1;
	}

	if (sacrifice.len <= plain.len) {
		*out = plain;
		return 0;
	}

	size_t common = 0;
	while (common < plain.len && common < sacrifice.len &&
	       plain.code[common] == sacrifice.code[common])
		common++;

	size_t p_tail = plain.len - common;
	size_t s_tail = sacrifice.len - common;

	int found = 0;
	if (p_tail == 0) {
		found = 1;
	} else {
		for (size_t off = 0; off + p_tail <= s_tail; off++) {
			if (memcmp(sacrifice.code + common + off,
			           plain.code + common, p_tail) == 0) {
				found = 1;
				break;
			}
		}
	}

	if (found) {
		*out = plain;
	} else {
		out->code = sacrifice.code;
		out->len  = plain.len;
	}

	return 0;
}

/*
 * CMP extraction — sacrifice only (no plain version).
 */
static int extract_cmp(void *func, void *next, fragment *out,
                       const char *name)
{
	fragment raw;
	if (extract_one(func, next, &raw) != 0) {
		fprintf(stderr, "extract: no RET in %s\n", name);
		return -1;
	}

#if defined(__aarch64__)
	if (raw.len >= 4) {
		out->code = raw.code;
		out->len  = raw.len - 4;  /* trim CSET */
	} else {
		*out = raw;
	}
#elif defined(__x86_64__)
	size_t cmp_start = 0;
	int found_cmp = 0;
	for (size_t i = 0; i + 2 < raw.len; i++) {
		if ((raw.code[i] == 0x4C && raw.code[i+1] == 0x39) ||
		    (raw.code[i] == 0x49 && raw.code[i+1] == 0x39)) {
			cmp_start = i;
			found_cmp = 1;
			break;
		}
	}
	if (found_cmp) {
		out->code = raw.code + cmp_start;
		out->len  = 3;
	} else {
		*out = raw;
	}
#endif
	return 0;
}

/*
 * test_tos extraction — C sacrifice: `return tos == 0`.
 * Trim the return-value suffix (SETE on x86-64, CSET on ARM64).
 */
static int extract_test_tos(fragment *out)
{
	fragment raw;
	if (extract_one((void *)c_test_tos_s, (void *)c_test_tos_end,
	                &raw) != 0) {
		fprintf(stderr, "extract: no RET in c_test_tos\n");
		return -1;
	}

#if defined(__aarch64__)
	if (raw.len >= 4) {
		out->code = raw.code;
		out->len  = raw.len - 4;
	} else {
		*out = raw;
	}
#elif defined(__x86_64__)
	int found = 0;
	for (size_t i = 0; i + 2 < raw.len; i++) {
		if (raw.code[i] == 0x48 && raw.code[i+1] == 0x85 &&
		    raw.code[i+2] == 0xDB) {
			out->code = raw.code + i;
			out->len  = 3;
			found = 1;
			break;
		}
	}
	if (!found)
		*out = raw;
#endif
	return 0;
}

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
 * Flag-preservation calibration
 *
 * Composes: [prologue] [alu_sub] [c_stack_op] [JZ fwd] [load 42] [epilogue]
 *
 * Test A: TOS=5, NOS=5 → sub=0, ZF=1 → JZ taken → TOS per stackop
 * Test B: TOS=3, NOS=5 → sub=2, ZF=0 → JZ not taken → TOS=42
 *
 * If both match → flags survived → use C version.
 * ================================================================ */

static void emit_bytes(const uint8_t *src, size_t len)
{
	memcpy(codebuf_w + here, src, len);
	here += len;
}

static int calibrate_one(fragment *frag, long expect_a)
{
	size_t save_here = here;

	emit_bytes(prologue_buf, prologue_len);
	emit_bytes(alu[ALU_SUB].code, alu[ALU_SUB].len);
	emit_bytes(frag->code, frag->len);
	size_t patch = emit_cond_forward(codebuf_w, &here, JCC_EQ);
	emit_load_imm(codebuf_w, &here, 42);
	patch_forward_branch(codebuf_w, patch, here);
	emit_bytes(epilogue_buf, epilogue_len);

	jit_exec_mode();

	/* Test A: TOS=5, NOS=5 → sub=0, ZF=1 → JZ taken */
	dsp = &data_stack[DATA_STACK_SZ / 2];
	data_stack[DATA_STACK_SZ / 2]     = 777;
	data_stack[DATA_STACK_SZ / 2 + 1] = 888;
	tos = 5; nos = 5;
	((void (*)(void))(codebuf_x + save_here))();
	long result_a = tos;

	/* Test B: TOS=3, NOS=5 → sub=2, ZF=0 → JZ not taken → TOS=42 */
	dsp = &data_stack[DATA_STACK_SZ / 2];
	data_stack[DATA_STACK_SZ / 2]     = 777;
	data_stack[DATA_STACK_SZ / 2 + 1] = 888;
	tos = 3; nos = 5;
	((void (*)(void))(codebuf_x + save_here))();
	long result_b = tos;

	jit_write_mode();
	here = save_here;

	return (result_a == expect_a && result_b == 42);
}

/*
 * Expected TOS for test A after each stack op
 * (after alu_sub(5,5): TOS=0, NOS=5, dsp=[777, 888, ...])
 */
static const long calib_expect_a[] = {
	[MAC_DROP_TOS] = 5,
	[MAC_DROP_NOS] = 0,
	[MAC_PUSH_NOS] = 0,
	[MAC_DUP]      = 0,
	[MAC_SWAP]     = 5,
	[MAC_TEST_TOS] = 0,  /* unused — test_tos calibrated separately */
	[MAC_OVER]     = 5,
	[MAC_2DROP]    = 777,
};

/* ================================================================
 * Initialization
 * ================================================================ */

static void dict_add(const char *name, uint8_t *code, size_t len,
                     int is_prim)
{
	dictionary[dict_count].name     = name;
	dictionary[dict_count].code     = code;
	dictionary[dict_count].code_len = len;
	dictionary[dict_count].is_prim  = is_prim;
	dict_count++;
}

/*
 * C stack op function table — ordered by function address for
 * extraction.  test_tos slot uses c_over as boundary marker
 * (test_tos is extracted separately via sacrifice).
 */
typedef struct {
	const char *name;
	void       (*func)(void);
} func_info;

static func_info c_func_table[] = {
	{ "drop_tos",  c_drop_tos  },
	{ "drop_nos",  c_drop_nos  },
	{ "push_nos",  c_push_nos  },
	{ "dup",       c_dup       },
	{ "swap",      c_swap      },
	{ NULL,        c_over      },  /* boundary for test_tos slot */
	{ "over",      c_over      },
	{ "2drop",     c_2drop     },
	{ NULL,        c_end       },  /* sentinel */
};

static int init(void)
{
	/* Allocate code buffer */
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

	/* ---- Extract ALU prims ---- */

	const char *alu_names[] = {
		"add", "sub", "dec", "inc", "and", "or", "xor", "neg"
	};
	void (*plain_funcs[])(void) = {
		alu_add_p, alu_sub_p, alu_dec_p, alu_inc_p,
		alu_and_p, alu_or_p, alu_xor_p, alu_neg_p
	};
	void (*plain_nexts[])(void) = {
		alu_sub_p, alu_dec_p, alu_inc_p, alu_and_p,
		alu_or_p, alu_xor_p, alu_neg_p, alu_end_p
	};
	void (*sacrifice_funcs[])(void) = {
		(void(*)(void))alu_add_s, (void(*)(void))alu_sub_s,
		(void(*)(void))alu_dec_s, (void(*)(void))alu_inc_s,
		(void(*)(void))alu_and_s, (void(*)(void))alu_or_s,
		(void(*)(void))alu_xor_s, (void(*)(void))alu_neg_s
	};
	void (*sacrifice_nexts[])(void) = {
		(void(*)(void))alu_sub_s, (void(*)(void))alu_dec_s,
		(void(*)(void))alu_inc_s, (void(*)(void))alu_and_s,
		(void(*)(void))alu_or_s, (void(*)(void))alu_xor_s,
		(void(*)(void))alu_neg_s, (void(*)(void))alu_end_s
	};

	printf("ALU extraction:\n");
	for (int i = 0; i < 8; i++) {
		fragment fp = {0}, fs = {0};
		extract_one(plain_funcs[i], plain_nexts[i], &fp);
		extract_one(sacrifice_funcs[i], sacrifice_nexts[i], &fs);
		printf("  %-4s plain=%2zu  sacrifice=%2zu",
		       alu_names[i], fp.len, fs.len);

		if (extract_alu_calibrated(
				plain_funcs[i], plain_nexts[i],
				sacrifice_funcs[i], sacrifice_nexts[i],
				&alu[i], alu_names[i]) != 0)
			return -1;

		printf("  -> using %zu bytes (%s)\n", alu[i].len,
		       alu[i].code == fs.code ? "sacrifice" : "plain");
	}

	if (extract_cmp((void *)alu_cmp_s, (void *)alu_cmp_end,
	                &alu[ALU_CMP], "cmp") != 0)
		return -1;
	printf("  cmp   -> using %zu bytes\n", alu[ALU_CMP].len);

	/* ---- Extract C-compiled stack ops ---- */
	printf("\nC stack op extraction:\n");
	for (int i = 0; i < MAC_COUNT; i++) {
		if (i == MAC_TEST_TOS) {
			if (extract_test_tos(&c_mac[i]) != 0) {
				fprintf(stderr,
					"FATAL: cannot extract test_tos from C\n");
				return -1;
			}
			printf("  %-10s %2zu bytes (sacrifice)\n",
			       mac_names[i], c_mac[i].len);
			continue;
		}
		if (extract_one((void *)c_func_table[i].func,
		                (void *)c_func_table[i + 1].func,
		                &c_mac[i]) != 0) {
			fprintf(stderr,
				"FATAL: cannot extract C version of %s\n",
				mac_names[i]);
			return -1;
		}
		printf("  %-10s %2zu bytes\n", mac_names[i], c_mac[i].len);
	}

	/* ---- Extract asm overrides (if any) ---- */
	if (HAS_ASM_OVERRIDES) {
		printf("\nAsm override extraction:\n");
		for (int i = 0; i < MAC_COUNT; i++) {
			if (override_table[i].name == NULL) {
				printf("  %-10s (none)\n", mac_names[i]);
				continue;
			}
			if (extract_one((void *)override_table[i].func,
			                (void *)override_table[i + 1].func,
			                &ov_mac[i]) != 0) {
				fprintf(stderr,
					"FATAL: cannot extract asm override %s\n",
					mac_names[i]);
				return -1;
			}
			printf("  %-10s %2zu bytes\n",
			       mac_names[i], ov_mac[i].len);
		}
	}

	/* ---- Nonleaf frame ---- */
	if (extract_nonleaf_frame() != 0) {
		fprintf(stderr, "FATAL: nonleaf frame extraction failed\n");
		return -1;
	}

	/* ---- Flag-preservation calibration ---- */
	printf("\nCalibration (C is default, asm is escape hatch):\n");
	int fatal = 0;

	for (int i = 0; i < MAC_COUNT; i++) {
		if (i == MAC_TEST_TOS) {
			/*
			 * test_tos SETS flags — different calibration.
			 * Test: compose c_test_tos + JZ + load_42
			 *   TOS=0 → ZF=1 → JZ taken → TOS stays 0
			 *   TOS=5 → ZF=0 → JZ not taken → TOS=42
			 */
			size_t save = here;
			emit_bytes(prologue_buf, prologue_len);
			emit_bytes(c_mac[MAC_TEST_TOS].code,
			           c_mac[MAC_TEST_TOS].len);
			size_t patch = emit_cond_forward(codebuf_w,
			                                 &here, JCC_EQ);
			emit_load_imm(codebuf_w, &here, 42);
			patch_forward_branch(codebuf_w, patch, here);
			emit_bytes(epilogue_buf, epilogue_len);

			jit_exec_mode();

			dsp = &data_stack[DATA_STACK_SZ / 2];
			tos = 0; nos = 777;
			((void (*)(void))(codebuf_x + save))();
			long ra = tos;

			dsp = &data_stack[DATA_STACK_SZ / 2];
			tos = 5; nos = 777;
			((void (*)(void))(codebuf_x + save))();
			long rb = tos;

			jit_write_mode();
			here = save;

			int ok = (ra == 0 && rb == 42);
			if (ok) {
				mac[i] = c_mac[i];
				mac_source[i] = "C";
				printf("  %-10s C (%zu bytes) — sets flags correctly\n",
				       mac_names[i], c_mac[i].len);
			} else {
				fprintf(stderr,
					"FATAL: C test_tos does not set flags correctly on "
#if defined(__aarch64__)
					"aarch64"
#elif defined(__x86_64__)
					"x86_64"
#else
					"this architecture"
#endif
					".\n"
					"  This should not happen — the sacrifice pattern "
					"works on all known architectures.\n"
					"  ra=%ld (expected 0), rb=%ld (expected 42)\n",
					ra, rb);
				fatal = 1;
			}
			continue;
		}

		/* Normal stack ops: test C, fall back to asm override */
		int c_ok = calibrate_one(&c_mac[i], calib_expect_a[i]);
		if (c_ok) {
			mac[i] = c_mac[i];
			mac_source[i] = "C";
			printf("  %-10s C (%zu bytes) — flags preserved\n",
			       mac_names[i], c_mac[i].len);
		} else if (HAS_ASM_OVERRIDES && ov_mac[i].code != NULL) {
			/* Verify the asm override actually works */
			int asm_ok = calibrate_one(&ov_mac[i],
			                           calib_expect_a[i]);
			if (asm_ok) {
				mac[i] = ov_mac[i];
				mac_source[i] = "asm";
				printf("  %-10s asm override (%zu bytes) — "
				       "C clobbers flags, asm ok\n",
				       mac_names[i], ov_mac[i].len);
			} else {
				fprintf(stderr,
					"FATAL: %s — both C and asm override "
					"clobber flags.\n", mac_names[i]);
				fatal = 1;
			}
		} else {
			fprintf(stderr,
				"FATAL: C version of '%s' clobbers flags, "
				"but no asm override found for "
#if defined(__aarch64__)
				"aarch64"
#elif defined(__x86_64__)
				"x86_64"
#else
				"this architecture"
#endif
				".\n"
				"  Create overrides_"
#if defined(__aarch64__)
				"aarch64"
#elif defined(__x86_64__)
				"x86_64"
#else
				"ARCH"
#endif
				".h with an asm version of '%s'.\n",
				mac_names[i], mac_names[i]);
			fatal = 1;
		}
	}

	if (fatal) {
		fprintf(stderr, "\nCalibration failed.  Cannot continue.\n");
		return -1;
	}

	/* ---- Compose dictionary words ---- */
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

	/* & = alu_and + drop_nos */
	start = here;
	emit_bytes(alu[ALU_AND].code, alu[ALU_AND].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("&", codebuf_x + start, here - start, 1);

	/* | = alu_or + drop_nos */
	start = here;
	emit_bytes(alu[ALU_OR].code, alu[ALU_OR].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("|", codebuf_x + start, here - start, 1);

	/* ^ = alu_xor + drop_nos */
	start = here;
	emit_bytes(alu[ALU_XOR].code, alu[ALU_XOR].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("^", codebuf_x + start, here - start, 1);

	/* negate = alu_neg */
	start = here;
	emit_bytes(alu[ALU_NEG].code, alu[ALU_NEG].len);
	dict_add("negate", codebuf_x + start, here - start, 1);

	/* cmp = alu_cmp */
	start = here;
	emit_bytes(alu[ALU_CMP].code, alu[ALU_CMP].len);
	dict_add("cmp", codebuf_x + start, here - start, 1);

	/* drop */
	start = here;
	emit_bytes(mac[MAC_DROP_TOS].code, mac[MAC_DROP_TOS].len);
	dict_add("drop", codebuf_x + start, here - start, 1);

	/* dup */
	start = here;
	emit_bytes(mac[MAC_DUP].code, mac[MAC_DUP].len);
	dict_add("dup", codebuf_x + start, here - start, 1);

	/* swap */
	start = here;
	emit_bytes(mac[MAC_SWAP].code, mac[MAC_SWAP].len);
	dict_add("swap", codebuf_x + start, here - start, 1);

	/* over */
	start = here;
	emit_bytes(mac[MAC_OVER].code, mac[MAC_OVER].len);
	dict_add("over", codebuf_x + start, here - start, 1);

	/* 2drop */
	start = here;
	emit_bytes(mac[MAC_2DROP].code, mac[MAC_2DROP].len);
	dict_add("2drop", codebuf_x + start, here - start, 1);

	/* 0- = test_tos */
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

	/* Jcc selectors (compile-time only) */
	if (strcmp(word, "0=") == 0) {
		if (compiling) cond_jmp = JCC_EQ;
		return;
	}
	if (strcmp(word, "0<>") == 0) {
		if (compiling) cond_jmp = JCC_NE;
		return;
	}
	if (strcmp(word, "0<") == 0) {
		if (compiling) cond_jmp = JCC_MI;
		return;
	}
	if (strcmp(word, "0>") == 0) {
		if (compiling) cond_jmp = JCC_GT;
		return;
	}

	/* Compound comparisons */
	if (strcmp(word, "=") == 0) {
		if (compiling) {
			emit_inline(dict_find("cmp"));
			cond_jmp = JCC_EQ;
		}
		return;
	}
	if (strcmp(word, "<>") == 0) {
		if (compiling) {
			emit_inline(dict_find("cmp"));
			cond_jmp = JCC_NE;
		}
		return;
	}
	if (strcmp(word, "<") == 0) {
		if (compiling) {
			emit_inline(dict_find("cmp"));
			cond_jmp = JCC_LT;
		}
		return;
	}
	if (strcmp(word, ">") == 0) {
		if (compiling) {
			emit_inline(dict_find("cmp"));
			cond_jmp = JCC_GT;
		}
		return;
	}

	/* Flow control */
	if (strcmp(word, "IF") == 0) {
		if (!compiling)
			return;
		int inverted = invert_jcc(cond_jmp);
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
		int inverted = invert_jcc(cond_jmp);
		emit_cond_backward(codebuf_w, &here, inverted,
		                   flow_stack[--flow_sp]);
		return;
	}

	/* Dictionary lookup */
	dict_entry *e = dict_find(word);
	if (e) {
		if (compiling) {
			if (e->is_prim)
				emit_inline(e);
			else
				emit_call(codebuf_w, codebuf_x,
				          &here, e->code);
		} else {
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
 * Tests — same suite as exp 010
 * ================================================================ */

static int test_count = 0, pass_count = 0;

static void check(const char *desc, long expected_tos)
{
	test_count++;
	if (tos == expected_tos) {
		printf("  PASS  %s (TOS=%ld)\n", desc, tos);
		pass_count++;
	} else {
		printf("  FAIL  %s (TOS=%ld, expected %ld)\n",
		       desc, tos, expected_tos);
	}
}

static void reset_stack(void)
{
	dsp = &data_stack[DATA_STACK_SZ / 2];
	tos = 0;
	nos = 0;
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

	printf("\nArchitecture: %s\n",
#if defined(__aarch64__)
	       "ARM64"
#elif defined(__x86_64__)
	       "x86-64"
#else
	       "unknown"
#endif
	);

	printf("Selected macros:\n");
	for (int i = 0; i < MAC_COUNT; i++)
		printf("  %-10s %2zu bytes [%s]\n",
		       mac_names[i], mac[i].len, mac_source[i]);
	printf("Nonleaf frame: prologue %zu, epilogue %zu\n\n",
	       prologue_len, epilogue_len);

	/* --- A: Basic arithmetic --- */
	printf("--- A: Basic arithmetic ---\n");

	reset_stack();
	eval("42");
	check("literal 42", 42);

	reset_stack();
	eval("21");
	eval("dup +");
	check("21 dup +", 42);

	reset_stack();
	eval("10");
	eval("3");
	eval("-");
	check("10 3 -", 7);

	reset_stack();
	eval("10");
	eval("1-");
	check("10 1-", 9);

	reset_stack();
	eval("10");
	eval("1+");
	check("10 1+", 11);

	reset_stack();
	eval("255");
	eval("15");
	eval("&");
	check("255 15 &", 15);

	reset_stack();
	eval("12");
	eval("5");
	eval("|");
	check("12 5 |", 13);

	reset_stack();
	eval("255");
	eval("255");
	eval("^");
	check("255 255 ^", 0);

	reset_stack();
	eval("42");
	eval("negate");
	check("42 negate", -42);

	/* --- B: 0= selector --- */
	printf("\n--- B: 0= selector (zero/equal) ---\n");

	eval(": b1-take 0 0- 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("b1-take");
	check("0- 0= IF (zero -> taken)", 42);

	eval(": b1-skip 5 0- 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("b1-skip");
	check("0- 0= IF (nonzero -> skip)", 99);

	eval(": b2-eq 5 - 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("5");
	eval("b2-eq");
	check("5 5 - 0= IF (zero -> taken)", 42);

	eval(": b2-ne 5 - 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("3");
	eval("b2-ne");
	check("3 5 - 0= IF (nonzero -> skip)", 99);

	eval(": b3-hit 1- 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("1");
	eval("b3-hit");
	check("1 1- 0= IF (was 1 -> taken)", 42);

	eval(": b3-miss 1- 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("3");
	eval("b3-miss");
	check("3 1- 0= IF (was 3 -> skip)", 99);

	eval(": b4-eq = drop IF 2drop 42 THEN ;");
	reset_stack();
	eval("5");
	eval("5");
	eval("b4-eq");
	check("5 5 = IF (equal -> taken)", 42);

	eval(": b4-ne = drop IF 2drop 42 THEN ;");
	reset_stack();
	eval("5");
	eval("3");
	eval("b4-ne");
	check("5 3 = IF (not equal -> skip)", 5);

	/* --- C: 0<> selector --- */
	printf("\n--- C: 0<> selector (nonzero/not-equal) ---\n");

	eval(": c1-take 5 0- 0<> drop IF drop 77 THEN ;");
	reset_stack();
	eval("99");
	eval("c1-take");
	check("0- 0<> IF (nonzero -> taken)", 77);

	eval(": c1-skip 0 0- 0<> drop IF drop 77 THEN ;");
	reset_stack();
	eval("99");
	eval("c1-skip");
	check("0- 0<> IF (zero -> skip)", 99);

	eval(": c2-ne <> drop IF 2drop 77 THEN ;");
	reset_stack();
	eval("5");
	eval("3");
	eval("c2-ne");
	check("5 3 <> IF (not-equal -> taken)", 77);

	eval(": c2-eq <> drop IF 2drop 77 THEN ;");
	reset_stack();
	eval("5");
	eval("5");
	eval("c2-eq");
	check("5 5 <> IF (equal -> skip)", 5);

	/* --- D: 0< selector --- */
	printf("\n--- D: 0< selector (negative/sign) ---\n");

	eval(": d1-neg 0- 0< drop IF drop 88 THEN ;");
	reset_stack();
	eval("99");
	eval("-5");
	eval("d1-neg");
	check("0- 0< IF (-5 -> taken)", 88);

	eval(": d1-pos 0- 0< drop IF drop 88 THEN ;");
	reset_stack();
	eval("99");
	eval("5");
	eval("d1-pos");
	check("0- 0< IF (5 -> skip)", 99);

	eval(": d2-less 3 - 0< drop IF drop 88 THEN ;");
	reset_stack();
	eval("99");
	eval("5");
	eval("d2-less");
	check("5 3 - 0< IF (positive -> skip)", 99);

	eval(": d2-less2 5 - 0< drop IF drop 88 THEN ;");
	reset_stack();
	eval("99");
	eval("3");
	eval("d2-less2");
	check("3 5 - 0< IF (negative -> taken)", 88);

	eval(": d3-lt < drop IF 2drop 88 THEN ;");
	reset_stack();
	eval("3");
	eval("5");
	eval("d3-lt");
	check("3 5 < IF (3<5 -> taken)", 88);

	eval(": d3-ge < drop IF 2drop 88 THEN ;");
	reset_stack();
	eval("5");
	eval("3");
	eval("d3-ge");
	check("5 3 < IF (5>=3 -> skip)", 5);

	/* --- E: 0> selector --- */
	printf("\n--- E: 0> selector (positive/greater) ---\n");

	eval(": e1-pos 0- 0> drop IF drop 66 THEN ;");
	reset_stack();
	eval("99");
	eval("5");
	eval("e1-pos");
	check("0- 0> IF (5 -> taken)", 66);

	eval(": e1-neg 0- 0> drop IF drop 66 THEN ;");
	reset_stack();
	eval("99");
	eval("-5");
	eval("e1-neg");
	check("0- 0> IF (-5 -> skip)", 99);

	eval(": e1-zero 0- 0> drop IF drop 66 THEN ;");
	reset_stack();
	eval("99");
	eval("0");
	eval("e1-zero");
	check("0- 0> IF (0 -> skip)", 99);

	eval(": e2-gt > drop IF 2drop 66 THEN ;");
	reset_stack();
	eval("5");
	eval("3");
	eval("e2-gt");
	check("5 3 > IF (5>3 -> taken)", 66);

	eval(": e2-le > drop IF 2drop 66 THEN ;");
	reset_stack();
	eval("3");
	eval("5");
	eval("e2-le");
	check("3 5 > IF (3<=5 -> skip)", 3);

	/* --- F: Loops --- */
	printf("\n--- F: Loops (BEGIN...UNTIL) ---\n");

	eval(": f1 5 BEGIN 1- dup 0- 0= drop UNTIL ;");
	reset_stack();
	eval("f1");
	check("countdown 1- 0= UNTIL", 0);

	eval(": f2 -3 BEGIN 1+ dup 0- 0> drop UNTIL ;");
	reset_stack();
	eval("f2");
	check("countup 1+ 0> UNTIL", 1);

	eval(": f3 0 5 BEGIN swap over + swap 1- dup 0- 0= drop UNTIL drop ;");
	reset_stack();
	eval("f3");
	check("sum 1..5 = 15", 15);

	/* --- G: Flags through composed words --- */
	printf("\n--- G: Flags through composed words ---\n");

	eval(": g1 -3 + 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("3");
	eval("g1");
	check("3 + (-3) 0= IF (sum zero -> taken)", 42);

	eval(": g2 15 & 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("240");
	eval("g2");
	check("240 & 15 0= IF (AND zero -> taken)", 42);

	eval(": g3 15 & 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("255");
	eval("g3");
	check("255 & 15 0= IF (AND nonzero -> skip)", 99);

	/* Results */
	printf("\n%d/%d tests passed\n", pass_count, test_count);
	if (pass_count == test_count) {
		printf("PASSED\n");
		return 0;
	} else {
		printf("FAILED\n");
		return 1;
	}
}
