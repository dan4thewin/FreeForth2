/*
 * Portable FreeForth2 — Experiment 012: Full Flow Control
 *
 * Builds on exp 011 (C-default, asm-optional).
 *
 * Adds the complete FreeForth flow control vocabulary:
 *   ELSE, WHILE, REPEAT, AGAIN, BREAK, END, ;THEN
 *
 * Flow stack uses tagged entries to distinguish:
 *   - IF forward refs (patched by THEN/ELSE)
 *   - BEGIN loop marks (jumped to by REPEAT/AGAIN/UNTIL)
 *   - 0 sentinels (pushed by BEGIN, consumed by REPEAT/END)
 *   - BREAK forward refs (chained through code, resolved by REPEAT/END)
 *
 * Same C-default principle: zero inline asm in stack ops.
 * Asm overrides via __has_include for architectures that need them.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

/* ================================================================
 * Architecture-specific: registers, find_ret, emit_call, emit_load_imm,
 * conditional/unconditional branch emission
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

/* Conditional forward branch — returns patch location */
static size_t emit_cond_forward(uint8_t *buf, size_t *here, int cond)
{
	size_t patch = *here;
	uint32_t instr = 0x54000000 | (cond & 0xF);
	memcpy(buf + *here, &instr, 4);
	*here += 4;
	return patch;
}

/* Patch a forward branch to land at 'target' */
static void patch_forward_branch(uint8_t *buf, size_t patch, size_t target)
{
	int32_t offset = (int32_t)(target - patch);
	uint32_t imm19 = (offset >> 2) & 0x7FFFF;
	uint32_t instr;
	memcpy(&instr, buf + patch, 4);
	instr = (instr & 0xFF00001F) | (imm19 << 5);
	memcpy(buf + patch, &instr, 4);
}

/* Conditional backward branch */
static void emit_cond_backward(uint8_t *buf, size_t *here, int cond,
                                size_t target)
{
	int32_t offset = (int32_t)(target - *here);
	uint32_t imm19 = (offset >> 2) & 0x7FFFF;
	uint32_t instr = 0x54000000 | (imm19 << 5) | (cond & 0xF);
	memcpy(buf + *here, &instr, 4);
	*here += 4;
}

/* Unconditional forward branch — returns patch location */
static size_t emit_uncond_forward(uint8_t *buf, size_t *here)
{
	size_t patch = *here;
	uint32_t instr = 0x14000000;  /* B with offset 0 (placeholder) */
	memcpy(buf + *here, &instr, 4);
	*here += 4;
	return patch;
}

/* Patch an unconditional forward branch */
static void patch_uncond_forward(uint8_t *buf, size_t patch, size_t target)
{
	int32_t offset = (int32_t)(target - patch);
	uint32_t imm26 = (offset >> 2) & 0x03FFFFFF;
	uint32_t instr = 0x14000000 | imm26;
	memcpy(buf + patch, &instr, 4);
}

/* Unconditional backward branch */
static void emit_uncond_backward(uint8_t *buf, size_t *here, size_t target)
{
	int32_t offset = (int32_t)(target - *here);
	uint32_t imm26 = (offset >> 2) & 0x03FFFFFF;
	uint32_t instr = 0x14000000 | imm26;
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

static void patch_forward_branch(uint8_t *buf, size_t patch, size_t target)
{
	int32_t rel = (int32_t)(target - (patch + 4));
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

/* Unconditional forward branch (JMP rel32) — returns patch location */
static size_t emit_uncond_forward(uint8_t *buf, size_t *here)
{
	buf[(*here)++] = 0xE9;
	size_t patch = *here;
	int32_t placeholder = 0;
	memcpy(buf + *here, &placeholder, 4);
	*here += 4;
	return patch;
}

/* Patch an unconditional forward branch */
static void patch_uncond_forward(uint8_t *buf, size_t patch, size_t target)
{
	int32_t rel = (int32_t)(target - (patch + 4));
	memcpy(buf + patch, &rel, 4);
}

/* Unconditional backward branch */
static void emit_uncond_backward(uint8_t *buf, size_t *here, size_t target)
{
	buf[(*here)++] = 0xE9;
	int32_t rel = (int32_t)(target - (*here + 4));
	memcpy(buf + *here, &rel, 4);
	*here += 4;
}

/* Emit RET instruction */
static int invert_jcc(int cond) { return cond ^ 1; }

#else
#error "Unsupported architecture"
#endif

/* ================================================================
 * C ALU primitives — plain + sacrifice versions
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

long __attribute__((noinline)) alu_cmp_s(void) { return nos == tos; }
void __attribute__((noinline)) alu_cmp_end(void) { asm volatile("nop"); }

/* ================================================================
 * C-compiled stack operations — the DEFAULT
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

long __attribute__((noinline)) c_test_tos_s(void) { return tos == 0; }
void __attribute__((noinline)) c_test_tos_end(void) { asm volatile("nop"); }

void __attribute__((noinline)) c_end(void) { asm volatile("nop"); }

/* ================================================================
 * Asm overrides — conditionally included per architecture
 * ================================================================ */

#if defined(__x86_64__) && __has_include("overrides_x86_64.h")
#include "overrides_x86_64.h"
#elif defined(__aarch64__) && __has_include("overrides_aarch64.h")
#include "overrides_aarch64.h"
#endif

#ifndef HAS_ASM_OVERRIDES
#define HAS_ASM_OVERRIDES 0
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
 * Nonleaf template
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
	if (first_bl == span) return -1;
	size_t ret_off = span;
	for (size_t i = first_bl + 4; i + 3 < span; i += 4) {
		uint32_t w;
		memcpy(&w, start + i, 4);
		if (w == 0xD65F03C0) { ret_off = i; break; }
	}
	if (ret_off == span) return -1;
	prologue_len = first_bl;
	memcpy(prologue_buf, start, prologue_len);
	size_t epi_start = first_bl + 4;
	epilogue_len = (ret_off + 4) - epi_start;
	memcpy(epilogue_buf, start + epi_start, epilogue_len);

#elif defined(__x86_64__)
	size_t first_call = span;
	for (size_t i = 0; i < span; i++) {
		if (start[i] == 0xE8) { first_call = i; break; }
	}
	if (first_call == span) return -1;
	size_t ret_off = span;
	for (size_t i = first_call + 5; i < span; i++) {
		if (start[i] == 0xC3) { ret_off = i; break; }
	}
	if (ret_off == span) return -1;
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
	int         is_prim;
} dict_entry;

static dict_entry dictionary[DICT_MAX];
static int dict_count = 0;
static int compiling = 0;
static size_t def_start = 0;

/* ================================================================
 * Flow control stack
 *
 * Tagged entries to distinguish different forward reference types.
 * Each entry is a (tag, value) pair.
 *
 * Tags:
 *   FLOW_IF      — forward ref from IF (patch location)
 *   FLOW_BEGIN   — loop origin (code offset to jump back to)
 *   FLOW_SENTINEL — 0 sentinel pushed by BEGIN (marks start of
 *                   WHILE chain on the flow stack)
 *   FLOW_WHILE   — forward ref from WHILE (patch location)
 *   FLOW_BREAK   — forward ref from BREAK (patch location,
 *                   chained through flow stack, not code buffer)
 * ================================================================ */

enum {
	FLOW_IF,
	FLOW_UNCOND,    /* unconditional forward ref (ELSE jump) */
	FLOW_BEGIN,
	FLOW_SENTINEL,
	FLOW_WHILE,
	FLOW_BREAK,
};

typedef struct {
	int    tag;
	size_t value;
} flow_entry;

#define FLOW_STACK_SZ 64
static flow_entry flow_stack[FLOW_STACK_SZ];
static int flow_sp = 0;

static void flow_push(int tag, size_t value)
{
	flow_stack[flow_sp].tag   = tag;
	flow_stack[flow_sp].value = value;
	flow_sp++;
}

static flow_entry flow_pop(void)
{
	return flow_stack[--flow_sp];
}

static flow_entry flow_peek(void)
{
	return flow_stack[flow_sp - 1];
}

/* Jcc selector */
static int cond_jmp = JCC_EQ;

/* ================================================================
 * Byte extraction — same as exp 011
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
static fragment mac[MAC_COUNT];
static fragment c_mac[MAC_COUNT];
static fragment ov_mac[MAC_COUNT];
static const char *mac_source[MAC_COUNT];

static int extract_one(void *func, void *next, fragment *out)
{
	uint8_t *start = (uint8_t *)func;
	size_t gap = (size_t)((uint8_t *)next - start);
	size_t body = find_ret(start, gap);
	if (body == 0) return -1;
	out->code = start;
	out->len  = body;
	return 0;
}

static int extract_alu_calibrated(void *func_plain, void *next_plain,
                                  void *func_sacrifice, void *next_sacrifice,
                                  fragment *out, const char *name)
{
	fragment plain, sacrifice;
	if (extract_one(func_plain, next_plain, &plain) != 0) return -1;
	if (extract_one(func_sacrifice, next_sacrifice, &sacrifice) != 0) return -1;

	if (sacrifice.len <= plain.len) { *out = plain; return 0; }

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

	if (found) { *out = plain; }
	else { out->code = sacrifice.code; out->len = plain.len; }
	return 0;
}

static int extract_cmp(void *func, void *next, fragment *out,
                       const char *name)
{
	fragment raw;
	if (extract_one(func, next, &raw) != 0) return -1;

#if defined(__aarch64__)
	if (raw.len >= 4) { out->code = raw.code; out->len = raw.len - 4; }
	else { *out = raw; }
#elif defined(__x86_64__)
	int found_cmp = 0;
	for (size_t i = 0; i + 2 < raw.len; i++) {
		if ((raw.code[i] == 0x4C && raw.code[i+1] == 0x39) ||
		    (raw.code[i] == 0x49 && raw.code[i+1] == 0x39)) {
			out->code = raw.code + i;
			out->len  = 3;
			found_cmp = 1;
			break;
		}
	}
	if (!found_cmp) *out = raw;
#endif
	(void)name;
	return 0;
}

static int extract_test_tos(fragment *out)
{
	fragment raw;
	if (extract_one((void *)c_test_tos_s, (void *)c_test_tos_end, &raw) != 0)
		return -1;

#if defined(__aarch64__)
	if (raw.len >= 4) { out->code = raw.code; out->len = raw.len - 4; }
	else { *out = raw; }
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
	if (!found) *out = raw;
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
 * Flag-preservation calibration — same as exp 011
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

	dsp = &data_stack[DATA_STACK_SZ / 2];
	data_stack[DATA_STACK_SZ / 2]     = 777;
	data_stack[DATA_STACK_SZ / 2 + 1] = 888;
	tos = 5; nos = 5;
	((void (*)(void))(codebuf_x + save_here))();
	long result_a = tos;

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

static const long calib_expect_a[] = {
	[MAC_DROP_TOS] = 5,
	[MAC_DROP_NOS] = 0,
	[MAC_PUSH_NOS] = 0,
	[MAC_DUP]      = 0,
	[MAC_SWAP]     = 5,
	[MAC_TEST_TOS] = 0,
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
	{ NULL,        c_end       },
};

static int init(void)
{
#ifdef __APPLE__
	codebuf_w = mmap(NULL, CODEBUF_SIZE,
	                 PROT_READ | PROT_WRITE | PROT_EXEC,
	                 MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT, -1, 0);
	if (codebuf_w == MAP_FAILED) { perror("mmap"); return -1; }
	codebuf_x = codebuf_w;
	jit_write_mode();
#else
	int fd = memfd_create_("ffcode", 0);
	if (fd == -1) { perror("memfd_create"); return -1; }
	if (ftruncate(fd, CODEBUF_SIZE) == -1) {
		perror("ftruncate"); close(fd); return -1;
	}
	codebuf_w = mmap(NULL, CODEBUF_SIZE, PROT_READ | PROT_WRITE,
	                 MAP_SHARED, fd, 0);
	codebuf_x = mmap(NULL, CODEBUF_SIZE, PROT_READ | PROT_EXEC,
	                 MAP_SHARED, fd, 0);
	close(fd);
	if (codebuf_w == MAP_FAILED || codebuf_x == MAP_FAILED) {
		perror("mmap"); return -1;
	}
#endif
	here = 0;

	/* ---- ALU extraction ---- */
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
		if (extract_alu_calibrated(
				plain_funcs[i], plain_nexts[i],
				sacrifice_funcs[i], sacrifice_nexts[i],
				&alu[i], alu_names[i]) != 0)
			return -1;
		printf("  %-4s %zu bytes\n", alu_names[i], alu[i].len);
	}
	if (extract_cmp((void *)alu_cmp_s, (void *)alu_cmp_end,
	                &alu[ALU_CMP], "cmp") != 0)
		return -1;
	printf("  cmp  %zu bytes\n", alu[ALU_CMP].len);

	/* ---- C stack ops ---- */
	for (int i = 0; i < MAC_COUNT; i++) {
		if (i == MAC_TEST_TOS) {
			if (extract_test_tos(&c_mac[i]) != 0) return -1;
			continue;
		}
		if (extract_one((void *)c_func_table[i].func,
		                (void *)c_func_table[i + 1].func,
		                &c_mac[i]) != 0)
			return -1;
	}

	/* ---- Asm overrides ---- */
	if (HAS_ASM_OVERRIDES) {
		for (int i = 0; i < MAC_COUNT; i++) {
			if (override_table[i].name == NULL) continue;
			if (extract_one((void *)override_table[i].func,
			                (void *)override_table[i + 1].func,
			                &ov_mac[i]) != 0)
				return -1;
		}
	}

	/* ---- Nonleaf frame ---- */
	if (extract_nonleaf_frame() != 0) return -1;

	/* ---- Calibration ---- */
	printf("\nCalibration:\n");
	int fatal = 0;

	for (int i = 0; i < MAC_COUNT; i++) {
		if (i == MAC_TEST_TOS) {
			/* test_tos: verify flag-setting via C sacrifice */
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

			if (ra == 0 && rb == 42) {
				mac[i] = c_mac[i];
				mac_source[i] = "C";
			} else {
				fprintf(stderr, "FATAL: C test_tos broken\n");
				fatal = 1;
			}
			printf("  %-10s [%s] %zu bytes\n",
			       mac_names[i], mac_source[i], mac[i].len);
			continue;
		}

		int c_ok = calibrate_one(&c_mac[i], calib_expect_a[i]);
		if (c_ok) {
			mac[i] = c_mac[i];
			mac_source[i] = "C";
		} else if (HAS_ASM_OVERRIDES && ov_mac[i].code != NULL) {
			int asm_ok = calibrate_one(&ov_mac[i], calib_expect_a[i]);
			if (asm_ok) {
				mac[i] = ov_mac[i];
				mac_source[i] = "asm";
			} else {
				fprintf(stderr, "FATAL: %s — both C and asm fail\n",
				        mac_names[i]);
				fatal = 1;
			}
		} else {
			fprintf(stderr,
				"FATAL: C '%s' clobbers flags, no asm override.\n"
				"  Create overrides_"
#if defined(__aarch64__)
				"aarch64"
#elif defined(__x86_64__)
				"x86_64"
#else
				"ARCH"
#endif
				".h with '%s'.\n", mac_names[i], mac_names[i]);
			fatal = 1;
		}
		printf("  %-10s [%s] %zu bytes\n",
		       mac_names[i], mac_source[i], mac[i].len);
	}

	if (fatal) return -1;

	/* ---- Compose dictionary ---- */
	size_t start;

	start = here;
	emit_bytes(alu[ALU_ADD].code, alu[ALU_ADD].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("+", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(alu[ALU_SUB].code, alu[ALU_SUB].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("-", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(alu[ALU_DEC].code, alu[ALU_DEC].len);
	dict_add("1-", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(alu[ALU_INC].code, alu[ALU_INC].len);
	dict_add("1+", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(alu[ALU_AND].code, alu[ALU_AND].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("&", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(alu[ALU_OR].code, alu[ALU_OR].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("|", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(alu[ALU_XOR].code, alu[ALU_XOR].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("^", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(alu[ALU_NEG].code, alu[ALU_NEG].len);
	dict_add("negate", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(alu[ALU_CMP].code, alu[ALU_CMP].len);
	dict_add("cmp", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(mac[MAC_DROP_TOS].code, mac[MAC_DROP_TOS].len);
	dict_add("drop", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(mac[MAC_DUP].code, mac[MAC_DUP].len);
	dict_add("dup", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(mac[MAC_SWAP].code, mac[MAC_SWAP].len);
	dict_add("swap", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(mac[MAC_OVER].code, mac[MAC_OVER].len);
	dict_add("over", codebuf_x + start, here - start, 1);

	start = here;
	emit_bytes(mac[MAC_2DROP].code, mac[MAC_2DROP].len);
	dict_add("2drop", codebuf_x + start, here - start, 1);

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
 * Dictionary and interpreter — with full flow control
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

/*
 * Resolve WHILE forward refs from the flow stack.
 * Pop and patch all FLOW_WHILE entries until we hit FLOW_SENTINEL.
 * Also pop the sentinel itself.
 */
/*
 * Resolve all forward refs (WHILE and BREAK) above the SENTINEL.
 * WHILE refs use conditional branch patching.
 * BREAK refs use unconditional branch patching.
 * Both land at current `here`.
 * Pops the SENTINEL too.
 */
static void resolve_loop_forwards(void)
{
	while (flow_sp > 0) {
		flow_entry top = flow_peek();
		if (top.tag == FLOW_WHILE) {
			flow_pop();
			patch_forward_branch(codebuf_w, top.value, here);
		} else if (top.tag == FLOW_BREAK) {
			flow_pop();
			patch_uncond_forward(codebuf_w, top.value, here);
		} else {
			break;
		}
	}
	/* Pop the sentinel */
	if (flow_sp > 0 && flow_peek().tag == FLOW_SENTINEL)
		flow_pop();
}

static void process_word(const char *word)
{
	long num;

	/* ---- Definition delimiters ---- */

	if (strcmp(word, ":") == 0) {
		compiling = 1;
		def_start = here;
		return;
	}

	if (strcmp(word, ";") == 0) {
		if (!compiling) return;
		emit_bytes(epilogue_buf, epilogue_len);
		compiling = 0;
		return;
	}

	/* ---- Immediate I/O (interpret mode only) ---- */

	if (strcmp(word, ".") == 0) {
		if (!compiling) {
			printf("%ld ", tos);
			tos = nos; nos = *dsp; dsp++;
		}
		return;
	}

	if (strcmp(word, "cr") == 0) {
		if (!compiling) printf("\n");
		return;
	}

	/* ---- Jcc selectors (compile-time only) ---- */

	if (strcmp(word, "0=") == 0)  { if (compiling) cond_jmp = JCC_EQ; return; }
	if (strcmp(word, "0<>") == 0) { if (compiling) cond_jmp = JCC_NE; return; }
	if (strcmp(word, "0<") == 0)  { if (compiling) cond_jmp = JCC_MI; return; }
	if (strcmp(word, "0>") == 0)  { if (compiling) cond_jmp = JCC_GT; return; }

	/* ---- Compound comparisons ---- */

	if (strcmp(word, "=") == 0) {
		if (compiling) { emit_inline(dict_find("cmp")); cond_jmp = JCC_EQ; }
		return;
	}
	if (strcmp(word, "<>") == 0) {
		if (compiling) { emit_inline(dict_find("cmp")); cond_jmp = JCC_NE; }
		return;
	}
	if (strcmp(word, "<") == 0) {
		if (compiling) { emit_inline(dict_find("cmp")); cond_jmp = JCC_LT; }
		return;
	}
	if (strcmp(word, ">") == 0) {
		if (compiling) { emit_inline(dict_find("cmp")); cond_jmp = JCC_GT; }
		return;
	}

	/* ================================================================
	 * Flow control
	 *
	 * Flow stack layout for each construct:
	 *
	 *   IF:     pushes (FLOW_IF, patch_addr)
	 *   THEN:   pops FLOW_IF, patches forward ref to here
	 *   ELSE:   emits uncond fwd jump, patches IF, pushes new FLOW_IF
	 *   ;THEN:  emits RET, pops FLOW_IF, patches forward ref to here
	 *
	 *   BEGIN:  pushes (FLOW_BEGIN, here) then (FLOW_SENTINEL, 0)
	 *   WHILE:  emits cond fwd jump, pushes (FLOW_WHILE, patch_addr)
	 *   UNTIL:  emits cond backward jump to BEGIN addr,
	 *           resolves WHILEs and sentinel
	 *   REPEAT: emits uncond backward jump to BEGIN addr,
	 *           resolves WHILEs, BREAKs, and sentinel
	 *   AGAIN:  emits uncond backward jump to BEGIN addr
	 *           (does NOT close the loop — no resolve)
	 *   BREAK:  emits uncond fwd jump, pushes (FLOW_BREAK, patch_addr)
	 *   END:    resolves BREAKs and WHILEs (no backward jump)
	 * ================================================================ */

	if (strcmp(word, "IF") == 0) {
		if (!compiling) return;
		int inverted = invert_jcc(cond_jmp);
		size_t patch = emit_cond_forward(codebuf_w, &here, inverted);
		flow_push(FLOW_IF, patch);
		return;
	}

	if (strcmp(word, "THEN") == 0) {
		if (!compiling || flow_sp == 0) return;
		flow_entry e = flow_pop();
		if (e.tag == FLOW_UNCOND)
			patch_uncond_forward(codebuf_w, e.value, here);
		else
			patch_forward_branch(codebuf_w, e.value, here);
		return;
	}

	if (strcmp(word, "ELSE") == 0) {
		if (!compiling || flow_sp == 0) return;
		/* Emit unconditional forward jump (skip ELSE body) */
		size_t else_patch = emit_uncond_forward(codebuf_w, &here);
		/* Patch the IF to land here (start of ELSE body) */
		flow_entry if_entry = flow_pop();
		patch_forward_branch(codebuf_w, if_entry.value, here);
		/* Push ELSE's forward ref — unconditional, resolved by THEN */
		flow_push(FLOW_UNCOND, else_patch);
		return;
	}

	if (strcmp(word, ";THEN") == 0) {
		if (!compiling || flow_sp == 0) return;
		/* Emit RET (early return) */
		emit_bytes(epilogue_buf, epilogue_len);
		/* Patch the IF to land here */
		flow_entry e = flow_pop();
		patch_forward_branch(codebuf_w, e.value, here);
		return;
	}

	if (strcmp(word, "BEGIN") == 0) {
		if (!compiling) return;
		flow_push(FLOW_BEGIN, here);
		flow_push(FLOW_SENTINEL, 0);
		return;
	}

	if (strcmp(word, "WHILE") == 0) {
		if (!compiling) return;
		/* Emit conditional forward branch (inverted — skip body if false) */
		int inverted = invert_jcc(cond_jmp);
		size_t patch = emit_cond_forward(codebuf_w, &here, inverted);
		flow_push(FLOW_WHILE, patch);
		return;
	}

	if (strcmp(word, "UNTIL") == 0) {
		if (!compiling) return;
		/* Emit conditional backward jump FIRST */
		if (flow_sp == 0) return;
		/* Find BEGIN under WHILEs and sentinel */
		int bi = flow_sp - 1;
		while (bi >= 0 && flow_stack[bi].tag != FLOW_BEGIN) bi--;
		if (bi < 0) return;
		size_t begin_addr = flow_stack[bi].value;
		int inverted = invert_jcc(cond_jmp);
		emit_cond_backward(codebuf_w, &here, inverted, begin_addr);
		/* NOW resolve forwards to land here (after the backward jump) */
		resolve_loop_forwards();
		if (flow_sp == 0) return;
		flow_pop(); /* BEGIN */
		return;
	}

	if (strcmp(word, "REPEAT") == 0) {
		if (!compiling) return;
		/* Find BEGIN under WHILEs and sentinel */
		int bi = flow_sp - 1;
		while (bi >= 0 && flow_stack[bi].tag != FLOW_BEGIN) bi--;
		if (bi < 0) return;
		size_t begin_addr = flow_stack[bi].value;
		/* Emit unconditional backward jump FIRST */
		emit_uncond_backward(codebuf_w, &here, begin_addr);
		/* NOW resolve forwards to land here (after the backward jump) */
		resolve_loop_forwards();
		if (flow_sp == 0) return;
		flow_pop(); /* BEGIN */
		return;
	}

	if (strcmp(word, "AGAIN") == 0) {
		if (!compiling) return;
		/*
		 * AGAIN = unconditional jump back to BEGIN.
		 * Unlike REPEAT, it does NOT close the loop.
		 * It's used as "continue" after IF:  IF AGAIN
		 *
		 * Find the BEGIN address by scanning down past
		 * WHILEs and the sentinel.
		 */
		/* Find the BEGIN entry without popping WHILE/SENTINEL */
		int found = 0;
		size_t begin_addr = 0;
		for (int i = flow_sp - 1; i >= 0; i--) {
			if (flow_stack[i].tag == FLOW_BEGIN) {
				begin_addr = flow_stack[i].value;
				found = 1;
				break;
			}
		}
		if (!found) return;
		emit_uncond_backward(codebuf_w, &here, begin_addr);
		/* If preceded by IF, resolve the IF's forward ref to here */
		/* (the IF AGAIN pattern: IF jumps past the AGAIN) */
		/* Check if the top is an IF that should be resolved */
		if (flow_sp > 0 && flow_peek().tag == FLOW_IF) {
			flow_entry e = flow_pop();
			patch_forward_branch(codebuf_w, e.value, here);
		}
		return;
	}

	if (strcmp(word, "BREAK") == 0) {
		if (!compiling) return;
		/* Emit unconditional forward jump (resolved by REPEAT/END) */
		size_t patch = emit_uncond_forward(codebuf_w, &here);
		flow_push(FLOW_BREAK, patch);
		/* If preceded by IF, resolve the IF's forward ref to here */
		/* Actually: BREAK itself follows IF. The IF jumps past the BREAK.
		 * So we need to resolve the IF that's BELOW the BREAK we just pushed. */
		/* Check: pattern is IF BREAK → flow has [..., IF, BREAK]
		 * We want to resolve the IF so non-taken path skips BREAK. */
		if (flow_sp >= 2 && flow_stack[flow_sp - 2].tag == FLOW_IF) {
			/* Swap BREAK and IF, then pop and resolve IF */
			flow_entry brk = flow_stack[flow_sp - 1];
			flow_entry ife = flow_stack[flow_sp - 2];
			flow_stack[flow_sp - 2] = brk;
			flow_sp--;
			patch_forward_branch(codebuf_w, ife.value, here);
		}
		return;
	}

	if (strcmp(word, "END") == 0) {
		if (!compiling) return;
		/* Resolve WHILEs and BREAKs, pop sentinel and BEGIN (no backward jump) */
		resolve_loop_forwards();
		if (flow_sp > 0) flow_pop(); /* BEGIN */
		return;
	}

	/* ---- Dictionary lookup ---- */

	dict_entry *e = dict_find(word);
	if (e) {
		if (compiling) {
			if (e->is_prim)
				emit_inline(e);
			else
				emit_call(codebuf_w, codebuf_x, &here, e->code);
		} else {
			size_t save = here;
			emit_bytes(prologue_buf, prologue_len);
			if (e->is_prim) emit_inline(e);
			else emit_call(codebuf_w, codebuf_x, &here, e->code);
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
			dsp--; *dsp = nos; nos = tos; tos = num;
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
		while (*p == ' ' || *p == '\t' || *p == '\n') p++;
		if (!*p) break;

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
			dict_entry *de = &dictionary[dict_count - 1];
			de->code_len = here - (de->code - codebuf_x);
			continue;
		}

		process_word(buf);
	}
}

/* ================================================================
 * Tests
 *
 * Ported from exp/166-no-cstack-shared/test.ff plus exp 010's
 * arithmetic and selector tests.
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
	tos = 0; nos = 0;

	if (init() != 0) {
		fprintf(stderr, "FAILED — init\n");
		return 1;
	}
	setvbuf(stdout, NULL, _IOLBF, 0);

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
	printf("\n");

	/* ==============================================================
	 * Section A: Basic arithmetic (sanity)
	 * ============================================================== */

	printf("--- A: Arithmetic ---\n");

	reset_stack(); eval("42");
	check("literal 42", 42);

	reset_stack(); eval("21"); eval("dup +");
	check("21 dup +", 42);

	reset_stack(); eval("10"); eval("3"); eval("-");
	check("10 3 -", 7);

	reset_stack(); eval("10"); eval("1-");
	check("10 1-", 9);

	reset_stack(); eval("10"); eval("1+");
	check("10 1+", 11);

	reset_stack(); eval("255"); eval("15"); eval("&");
	check("255 15 &", 15);

	reset_stack(); eval("12"); eval("5"); eval("|");
	check("12 5 |", 13);

	reset_stack(); eval("255"); eval("255"); eval("^");
	check("255 255 ^", 0);

	reset_stack(); eval("42"); eval("negate");
	check("42 negate", -42);

	/* ==============================================================
	 * Section B: IF/THEN (from exp 010)
	 * ============================================================== */

	printf("\n--- B: IF/THEN ---\n");

	eval(": b1-take 0 0- 0= drop IF drop 42 THEN ;");
	reset_stack(); eval("99"); eval("b1-take");
	check("0= IF (zero -> taken)", 42);

	eval(": b1-skip 5 0- 0= drop IF drop 42 THEN ;");
	reset_stack(); eval("99"); eval("b1-skip");
	check("0= IF (nonzero -> skip)", 99);

	eval(": b4-eq = drop IF 2drop 42 THEN ;");
	reset_stack(); eval("5"); eval("5"); eval("b4-eq");
	check("= IF (equal -> taken)", 42);

	eval(": b4-ne = drop IF 2drop 42 THEN ;");
	reset_stack(); eval("5"); eval("3"); eval("b4-ne");
	check("= IF (not equal -> skip)", 5);

	/* ==============================================================
	 * Section C: ELSE
	 * ============================================================== */

	printf("\n--- C: IF/ELSE/THEN ---\n");

	eval(": c1 0- 0= drop IF 42 ELSE 99 THEN ;");
	reset_stack(); eval("0"); eval("c1");
	check("0 IF 42 ELSE 99 (zero -> 42)", 42);

	reset_stack(); eval("5"); eval("c1");
	check("5 IF 42 ELSE 99 (nonzero -> 99)", 99);

	eval(": c2 0- 0<> drop IF 77 ELSE 33 THEN ;");
	reset_stack(); eval("5"); eval("c2");
	check("5 0<> IF 77 ELSE 33 (nonzero -> 77)", 77);

	reset_stack(); eval("0"); eval("c2");
	check("0 0<> IF 77 ELSE 33 (zero -> 33)", 33);

	/* ==============================================================
	 * Section D: ;THEN (early return)
	 * ============================================================== */

	printf("\n--- D: ;THEN ---\n");

	eval(": d1 0- 0= drop IF 42 ;THEN 99 ;");
	reset_stack(); eval("0"); eval("d1");
	check("0 IF 42 ;THEN 99 (zero -> early return 42)", 42);

	reset_stack(); eval("5"); eval("d1");
	check("5 IF 42 ;THEN 99 (nonzero -> fall through 99)", 99);

	/* Multiple ;THEN */
	eval(": d2 dup 1- drop 0= IF drop 10 ;THEN dup 2 - drop 0= IF drop 20 ;THEN drop 30 ;");
	reset_stack(); eval("1"); eval("d2");
	check("1 -> 10 (first ;THEN)", 10);

	reset_stack(); eval("2"); eval("d2");
	check("2 -> 20 (second ;THEN)", 20);

	reset_stack(); eval("3"); eval("d2");
	check("3 -> 30 (fall through)", 30);

	/* ==============================================================
	 * Section E: BEGIN/UNTIL (from exp 010)
	 * ============================================================== */

	printf("\n--- E: BEGIN/UNTIL ---\n");

	eval(": e1 5 BEGIN 1- dup 0- 0= drop UNTIL ;");
	reset_stack(); eval("e1");
	check("countdown 1- 0= UNTIL", 0);

	eval(": e2 -3 BEGIN 1+ dup 0- 0> drop UNTIL ;");
	reset_stack(); eval("e2");
	check("countup 1+ 0> UNTIL", 1);

	eval(": e3 0 5 BEGIN swap over + swap 1- dup 0- 0= drop UNTIL drop ;");
	reset_stack(); eval("e3");
	check("sum 1..5 = 15", 15);

	/* ==============================================================
	 * Section F: BEGIN/WHILE/REPEAT
	 * ============================================================== */

	printf("\n--- F: BEGIN/WHILE/REPEAT ---\n");

	/* sum 5..1 with WHILE loop */
	eval(": f1 0 5 BEGIN dup 0- 0<> drop WHILE swap over + swap 1- REPEAT drop ;");
	reset_stack(); eval("f1");
	check("sum 5..1 WHILE/REPEAT", 15);

	/* zero-trip: WHILE fails immediately */
	eval(": f2 42 0 BEGIN dup 0- 0<> drop WHILE 1- REPEAT drop ;");
	reset_stack(); eval("f2");
	check("zero-trip WHILE (0 -> skip body)", 42);

	/* count down from 10, exit when 5 */
	eval(": f3 10 BEGIN dup 5 - drop 0<> WHILE 1- REPEAT ;");
	reset_stack(); eval("f3");
	check("10 countdown to 5 via WHILE", 5);

	/* ==============================================================
	 * Section G: AGAIN (continue)
	 * ============================================================== */

	printf("\n--- G: AGAIN (continue) ---\n");

	/* Sum 5..1 using AGAIN with ;THEN exit at 0 */
	eval(": g1 0 5 BEGIN dup 0- 0= drop IF drop ;THEN swap over + swap 1- AGAIN ;");
	reset_stack(); eval("g1");
	check("sum 5..1 via AGAIN/;THEN", 15);

	/* Sum even numbers 8+6+4+2=20, skip odd via AGAIN */
	eval(": g2 0 10 BEGIN 1- dup 0- 0<> drop WHILE dup 1 & 0- 0<> drop IF AGAIN swap over + swap REPEAT drop ;");
	reset_stack(); eval("g2");
	check("sum evens via AGAIN (8+6+4+2=20)", 20);

	/* ==============================================================
	 * Section H: BREAK
	 * ============================================================== */

	printf("\n--- H: BREAK ---\n");

	/* Sum 5..3, break at 2 */
	eval(": h1 0 5 BEGIN dup 2 - drop 0= IF drop BREAK swap over + swap 1- REPEAT ;");
	reset_stack(); eval("h1");
	check("sum 5..3, BREAK at 2", 12);

	/* Find first: 7 or 3, starting from 10 */
	eval(": h2 10 BEGIN dup 7 - drop 0= IF BREAK dup 3 - drop 0= IF BREAK 1- REPEAT ;");
	reset_stack(); eval("h2");
	check("find first 7 from 10", 7);

	/* BREAK from UNTIL loop */
	eval(": h3 0 10 BEGIN dup 5 - drop 0= IF BREAK swap over + swap 1- dup 0- 0= drop UNTIL drop ;");
	reset_stack(); eval("h3");
	check("BREAK at 5, else UNTIL at 0 (sum 10..6=40)", 40);

	/* ==============================================================
	 * Section I: END (resolve breaks, no backward jump)
	 * ============================================================== */

	printf("\n--- I: END ---\n");

	/* Loop with only BREAK exits, closed by END */
	eval(": i1 10 BEGIN dup 5 - drop 0= IF BREAK 1- dup 0- 0= drop IF BREAK REPEAT ;");
	reset_stack(); eval("i1");
	check("BREAK at 5", 5);

	/* ==============================================================
	 * Section J: Multiple WHILE
	 * ============================================================== */

	printf("\n--- J: Multiple WHILE ---\n");

	/* Sum 10..6, second WHILE exits at 5 */
	eval(": j1 0 10 BEGIN dup 0- 0<> drop WHILE dup 5 - drop 0<> WHILE swap over + swap 1- REPEAT drop ;");
	reset_stack(); eval("j1");
	check("double WHILE (sum 10..6=40)", 40);

	/* ==============================================================
	 * Section K: Nested loops
	 * ============================================================== */

	printf("\n--- K: Nested loops ---\n");

	/* Simple nested UNTIL: inner counts 3->0, outer counts 2->0, total increments = 6 */
	eval(": k1 0 2 BEGIN swap 3 BEGIN swap 1+ swap 1- dup 0- 0= drop UNTIL drop swap 1- dup 0- 0= drop UNTIL drop ;");
	reset_stack(); eval("k1");
	check("nested 2x3 UNTIL (count=6)", 6);

	/* ==============================================================
	 * Section L: Flags through composed words
	 * ============================================================== */

	printf("\n--- L: Flags through composed words ---\n");

	eval(": l1 -3 + 0= drop IF drop 42 THEN ;");
	reset_stack(); eval("99"); eval("3"); eval("l1");
	check("3+(-3) 0= IF (zero -> taken)", 42);

	eval(": l2 15 & 0= drop IF drop 42 THEN ;");
	reset_stack(); eval("99"); eval("240"); eval("l2");
	check("240 & 15 0= IF (zero -> taken)", 42);

	reset_stack(); eval("99"); eval("255"); eval("l2");
	check("255 & 15 0= IF (nonzero -> skip)", 99);

	/* ==============================================================
	 * Results
	 * ============================================================== */

	printf("\n%d/%d tests passed\n", pass_count, test_count);
	if (pass_count == test_count) {
		printf("PASSED\n");
		return 0;
	} else {
		printf("FAILED\n");
		return 1;
	}
}
