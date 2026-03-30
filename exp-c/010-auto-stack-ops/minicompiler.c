/*
 * Portable FreeForth2 — Experiment 010: Auto-Calibrating Stack Operations
 *
 * Builds on exp 009 (sacrificial compare + comparator matrix).
 *
 * Key innovation: RUNTIME FLAG-PRESERVATION CALIBRATION.
 *
 * Every stack operation (drop, dup, swap, etc.) is compiled from C
 * AND from inline asm.  At init time, we compose a test sequence:
 *
 *     alu_sub(sacrifice) + c_stack_op + JZ + marker + RET
 *
 * Execute twice with known values.  If the flags from alu_sub
 * survive through the C stack op, both tests produce correct
 * results → use the C version.  Otherwise → fall back to asm.
 *
 * On ARM64, C stack ops are likely all flag-preserving (ADD without
 * S suffix, LDR/STR post-indexed, MOV — none set flags).
 * On x86-64, dsp++ compiles to ADD which clobbers flags.
 *
 * test_tos uses the same sacrifice pattern as ALU ops:
 *     long c_test_tos_s(void) { return tos == 0; }
 * GCC emits TEST/TST + SETE/CSET.  We extract just the TEST/TST.
 *
 * Result: ARM64 needs zero inline asm.  x86-64 keeps asm where
 * GCC clobbers flags.  Future architectures auto-detect.
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

/* ---- Per-arch Jcc condition codes ------------------------------ */

/*
 * ARM64 B.cond encoding: condition is in bits [3:0]
 *   EQ=0x0, NE=0x1, MI=0x4 (negative), GT=0xC (greater)
 *   LT=0xB (less), GE=0xA (greater-equal)
 */
#define JCC_EQ  0x0   /* ZF=1 : 0=  */
#define JCC_NE  0x1   /* ZF=0 : 0<> */
#define JCC_MI  0x4   /* N=1  : 0<  (negative / sign) */
#define JCC_GT  0xC   /* GT   : 0>  (positive nonzero) */
#define JCC_LT  0xB   /* LT   : signed less */
#define JCC_GE  0xA   /* GE   : signed greater-equal */

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
	/* Backward scan — last 0xC3 is the real RET. */
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

/* ---- Per-arch Jcc condition codes ------------------------------ */

/*
 * x86-64 Jcc near: 0F 8x rel32
 *   JE=0x84 (ZF=1), JNE=0x85 (ZF=0), JS=0x88 (SF=1),
 *   JG=0x8F (ZF=0 && SF==OF), JL=0x8C (SF!=OF), JGE=0x8D (SF==OF)
 */
#define JCC_EQ  0x84   /* JE/JZ  : 0=  */
#define JCC_NE  0x85   /* JNE/JNZ: 0<> */
#define JCC_MI  0x88   /* JS     : 0<  (sign flag) */
#define JCC_GT  0x8F   /* JG     : 0>  (signed greater) */
#define JCC_LT  0x8C   /* JL     : signed less */
#define JCC_GE  0x8D   /* JGE    : signed greater-equal */

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

/* Invert a Jcc condition code (for IF/WHILE inversion) */
static int invert_jcc(int cond)
{
	/* x86-64: bit 0 toggles the sense (JE↔JNE, JL↔JGE, JG↔JLE) */
	return cond ^ 1;
}

#else
#error "Unsupported architecture"
#endif

#if defined(__aarch64__)
/* ARM64: bit 0 of the condition code inverts sense */
static int invert_jcc(int cond)
{
	return cond ^ 1;
}
#endif

/* ================================================================
 * C ALU primitives — TWO versions of each
 *
 * "plain":     just the operation
 * "sacrifice": operation + `return tos == 0` to coerce flag-setting
 *
 * On x86-64, plain already sets flags (SUB/ADD always do).
 * On ARM64, sacrifice coerces SUBS/ADDS (flag-setting variants).
 * ================================================================ */

/* --- Plain versions (no sacrifice) --- */
void __attribute__((noinline)) alu_add_p(void) { tos += nos; }
void __attribute__((noinline)) alu_sub_p(void) { tos = nos - tos; }
void __attribute__((noinline)) alu_dec_p(void) { tos--; }
void __attribute__((noinline)) alu_inc_p(void) { tos++; }
void __attribute__((noinline)) alu_and_p(void) { tos &= nos; }
void __attribute__((noinline)) alu_or_p(void)  { tos |= nos; }
void __attribute__((noinline)) alu_xor_p(void) { tos ^= nos; }
void __attribute__((noinline)) alu_neg_p(void) { tos = -tos; }
void __attribute__((noinline)) alu_end_p(void) { asm volatile("nop"); }

/* --- Sacrifice versions (coerce flag-setting) --- */
long __attribute__((noinline)) alu_add_s(void) { tos += nos;         return tos == 0; }
long __attribute__((noinline)) alu_sub_s(void) { tos = nos - tos;    return tos == 0; }
long __attribute__((noinline)) alu_dec_s(void) { tos--;              return tos == 0; }
long __attribute__((noinline)) alu_inc_s(void) { tos++;              return tos == 0; }
long __attribute__((noinline)) alu_and_s(void) { tos &= nos;         return tos == 0; }
long __attribute__((noinline)) alu_or_s(void)  { tos |= nos;         return tos == 0; }
long __attribute__((noinline)) alu_xor_s(void) { tos ^= nos;         return tos == 0; }
long __attribute__((noinline)) alu_neg_s(void) { tos = -tos;         return tos == 0; }
void __attribute__((noinline)) alu_end_s(void) { asm volatile("nop"); }

/* --- Non-consuming binary CMP (sacrifice only) --- */
long __attribute__((noinline)) alu_cmp_s(void) { return nos == tos; }
void __attribute__((noinline)) alu_cmp_end(void) { asm volatile("nop"); }

/* ================================================================
 * Inline asm macros — WE pick the instructions
 *
 * Flags-preserving stack plumbing.  LEA on x86-64, post-indexed
 * LDR/STR on ARM64.
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

/* over = ( a b -- a b a ) — push NOS, then swap TOS/NOS */
void __attribute__((noinline)) macro_over(void)
{
	asm volatile(
#if defined(__x86_64__)
		"lea -8(%%r15), %%r15\n\t"
		"mov %%r13, (%%r15)\n\t"
		"xchg %%rbx, %%r13"
#elif defined(__aarch64__)
		"str x20, [x21, #-8]!\n\t"
		"mov x0, x19\n\t"
		"mov x19, x20\n\t"
		"mov x20, x0"
#endif
		::: "memory"
	);
}

/* 2drop = drop TOS then drop new TOS */
void __attribute__((noinline)) macro_2drop(void)
{
	asm volatile(
#if defined(__x86_64__)
		"mov (%%r15), %%rbx\n\t"
		"mov 8(%%r15), %%r13\n\t"
		"lea 16(%%r15), %%r15"
#elif defined(__aarch64__)
		"ldp x19, x20, [x21], #16"
#endif
		::: "memory"
	);
}

void __attribute__((noinline)) macro_end(void) { asm volatile("nop"); }

/* ================================================================
 * C-compiled stack operations — GCC picks instructions
 *
 * These are the CANDIDATES.  If they preserve CPU flags (tested
 * empirically at init time), they replace the inline asm macros.
 *
 * test_tos is ALWAYS asm — C can't express "set flags, change
 * nothing" without side effects that GCC optimizes away.
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

/* test_tos: same sacrifice pattern as ALU ops.  GCC emits
 * TEST/TST to evaluate the condition, SETE/CSET for the return.
 * We extract the TEST/TST and trim the return-value suffix. */
long __attribute__((noinline)) c_test_tos_s(void) { return tos == 0; }
void __attribute__((noinline)) c_test_tos_end(void) { asm volatile("nop"); }

void __attribute__((noinline)) c_end(void) { asm volatile("nop"); }

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

/* Jcc selector — stores the condition code for the next IF/UNTIL */
static int cond_jmp = JCC_EQ;

/* ================================================================
 * Byte extraction and self-calibration
 * ================================================================ */

typedef struct {
	const char *name;
	void       (*func)(void);
} func_info;

typedef struct {
	uint8_t *code;
	size_t   len;
} fragment;

/*
 * extract_one: find function body bytes (up to but not including RET).
 * Uses the next function's address as an upper bound for scanning.
 */
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
 * Self-calibrating extraction for ALU primitives.
 *
 * Extract from both plain and sacrifice versions.
 *
 * Strategy: find the plain bytes as a contiguous subsequence inside
 * the sacrifice bytes (skipping any common prefix like ENDBR64).
 *
 *   - If found: plain instruction is embedded in sacrifice.  The
 *     sacrifice just wrapped it with prefix/suffix (XORL + SETE
 *     on x86-64).  Use plain — it already sets flags.
 *
 *   - If NOT found: sacrifice changed the instruction itself
 *     (SUB → SUBS on ARM64).  Use sacrifice bytes, trimming
 *     (sacrifice_len - plain_len) from the end.
 *
 * This is fully architecture-neutral — no #ifdef.
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
		/* Sacrifice not longer — plain is fine as-is */
		*out = plain;
		return 0;
	}

	/*
	 * Skip any shared prefix (e.g., ENDBR64) to focus on the
	 * ALU instruction proper.
	 */
	size_t common = 0;
	while (common < plain.len && common < sacrifice.len &&
	       plain.code[common] == sacrifice.code[common])
		common++;

	size_t p_tail = plain.len - common;
	size_t s_tail = sacrifice.len - common;

	/*
	 * Search for plain's unique tail within sacrifice's tail.
	 * If found, plain's instruction is intact inside sacrifice,
	 * meaning the architecture already sets flags (x86-64).
	 */
	int found = 0;
	if (p_tail == 0) {
		found = 1;  /* plain is a prefix of sacrifice */
	}
	else {
		for (size_t off = 0; off + p_tail <= s_tail; off++) {
			if (memcmp(sacrifice.code + common + off,
			           plain.code + common, p_tail) == 0) {
				found = 1;
				break;
			}
		}
	}

	if (found) {
		/* Plain bytes found inside sacrifice → use plain */
		*out = plain;
	}
	else {
		/*
		 * Sacrifice truly changed the instruction (ARM64 SUB→SUBS).
		 * Use sacrifice bytes, trimming the suffix.  The trim is
		 * (sacrifice_len - plain_len), giving us the same number
		 * of "useful" bytes.
		 */
		out->code = sacrifice.code;
		out->len  = plain.len;
	}

	return 0;
}

/*
 * CMP is special — it has no "plain" version (GCC optimizes away a
 * comparison with no consumer).  We extract from sacrifice and trim
 * the known suffix.
 */
static int extract_cmp(void *func, void *next, fragment *out,
                       const char *name)
{
	fragment raw;
	if (extract_one(func, next, &raw) != 0) {
		fprintf(stderr, "extract: no RET in %s\n", name);
		return -1;
	}

	/*
	 * The sacrifice function returns nos == tos.  GCC emits:
	 *   ARM64: CMP x20, x19 / CSET x0, eq  → trim 4 bytes
	 *   x86-64: [xorl %eax,%eax /] cmpq %rbx,%r13 / sete %al
	 *           [/ movzbl %al,%eax]
	 *
	 * On x86-64, find the CMP instruction (0x4C 0x39 or 0x49...)
	 * and trim everything after it + its length.
	 *
	 * On ARM64, trim the last 4 bytes (CSET).
	 */
#if defined(__aarch64__)
	if (raw.len >= 4) {
		out->code = raw.code;
		out->len  = raw.len - 4;  /* trim CSET */
	}
	else {
		*out = raw;
	}
#elif defined(__x86_64__)
	/*
	 * x86-64 CMP r/m64, r64 has various encodings.
	 * The sacrifice emits: [xorl] cmpq %rbx, %r13 [sete ...]
	 * The CMP we want compares rbx (TOS) against r13 (NOS).
	 *
	 * Strategy: find the SETE byte sequence (0F 94) and truncate
	 * everything from there onward.  What remains is the CMP
	 * (possibly with a harmless XORL prefix that clears eax —
	 * this is flags-preserving for ZF since XOR sets ZF based on
	 * eax, not on the operands we care about... actually XORL
	 * DOES clobber flags).
	 *
	 * Better: find the CMP.  On x86-64 with r13 and rbx:
	 *   4C 39 EB = cmp %r13, %rbx  (or 49 39 DD = cmp %rbx, %r13)
	 * One of these will be present.  Extract from the CMP to just
	 * before SETE.
	 */
	size_t cmp_start = 0;
	int found_cmp = 0;
	for (size_t i = 0; i + 2 < raw.len; i++) {
		/* Look for REX+CMP opcodes involving r13 and rbx */
		if ((raw.code[i] == 0x4C && raw.code[i+1] == 0x39) ||
		    (raw.code[i] == 0x49 && raw.code[i+1] == 0x39)) {
			cmp_start = i;
			found_cmp = 1;
			break;
		}
	}
	if (found_cmp) {
		/* CMP is 3 bytes (REX + opcode + ModRM) */
		out->code = raw.code + cmp_start;
		out->len  = 3;
	}
	else {
		/* Fallback: use everything, hope for the best */
		*out = raw;
	}
#endif
	return 0;
}

/*
 * test_tos from C sacrifice: `return tos == 0`.
 * Same idea as CMP extraction — trim the return-value suffix.
 *
 * GCC emits:
 *   ARM64: TST x19, x19 / CSET x0, eq  → trim CSET (4 bytes)
 *   x86-64: [xorl %eax,%eax /] test %rbx,%rbx / sete %al
 *           → find TEST opcode (48 85 DB), extract 3 bytes
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
		out->len  = raw.len - 4;  /* trim CSET */
	}
	else {
		*out = raw;
	}
#elif defined(__x86_64__)
	/*
	 * test %rbx, %rbx = 48 85 DB (REX.W + TEST + ModRM)
	 * Find this sequence and extract 3 bytes.
	 */
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
	if (!found) {
		/* Fallback: use raw */
		*out = raw;
	}
#endif
	return 0;
}

/* Macro extraction — straightforward, no sacrifice needed */
static int discover_macros(func_info *table, fragment *out, int count)
{
	for (int i = 0; i < count; i++) {
		if (extract_one((void *)table[i].func,
		                (void *)table[i + 1].func,
		                &out[i]) != 0) {
			fprintf(stderr, "discover: no RET in %s\n",
			        table[i].name);
			return -1;
		}
	}
	return 0;
}

/* ================================================================
 * Tables for extraction
 * ================================================================ */

static func_info macro_table[] = {
	{ "drop_tos",  macro_drop_tos  },
	{ "drop_nos",  macro_drop_nos  },
	{ "push_nos",  macro_push_nos  },
	{ "dup",       macro_dup       },
	{ "swap",      macro_swap      },
	{ "test_tos",  macro_test_tos  },
	{ "over",      macro_over      },
	{ "2drop",     macro_2drop     },
	{ NULL,        macro_end       }
};

/* C-compiled equivalents (no test_tos — always asm)
 *
 * The table must be ordered by function address for extraction.
 * test_tos has no C equivalent, so we put a real sentinel between
 * swap and over to provide an extraction boundary.
 */
static func_info c_macro_table[] = {
	{ "drop_tos",  c_drop_tos  },  /* 0: MAC_DROP_TOS */
	{ "drop_nos",  c_drop_nos  },  /* 1: MAC_DROP_NOS */
	{ "push_nos",  c_push_nos  },  /* 2: MAC_PUSH_NOS */
	{ "dup",       c_dup       },  /* 3: MAC_DUP      */
	{ "swap",      c_swap      },  /* 4: MAC_SWAP     */
	{ NULL,        c_over      },  /* 5: MAC_TEST_TOS — skipped, func=over as boundary */
	{ "over",      c_over      },  /* 6: MAC_OVER     */
	{ "2drop",     c_2drop     },  /* 7: MAC_2DROP    */
	{ NULL,        c_end       }   /* sentinel */
};

enum {
	MAC_DROP_TOS, MAC_DROP_NOS, MAC_PUSH_NOS,
	MAC_DUP, MAC_SWAP, MAC_TEST_TOS, MAC_OVER,
	MAC_2DROP, MAC_COUNT
};

/* ALU fragments — filled by calibrated extraction */
enum {
	ALU_ADD, ALU_SUB, ALU_DEC, ALU_INC,
	ALU_AND, ALU_OR, ALU_XOR, ALU_NEG,
	ALU_CMP, ALU_COUNT
};

static fragment alu[ALU_COUNT];
static fragment mac[MAC_COUNT];          /* selected (C or asm) */
static fragment asm_mac[MAC_COUNT];      /* always-available asm versions */
static fragment c_mac[MAC_COUNT];        /* C-compiled versions */
static const char *mac_source[MAC_COUNT]; /* "C" or "asm" for diagnostics */

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
 * Tests whether a C-compiled stack op preserves CPU flags set by
 * a preceding ALU operation.  Composes a test sequence into the
 * code buffer:
 *
 *   [prologue] [alu_sub] [c_stack_op] [JZ forward] [load 42] [epilogue]
 *
 * Executes twice:
 *   Test A: TOS=5, NOS=5 → sub=0, ZF=1 → JZ taken → TOS per stackop
 *   Test B: TOS=3, NOS=5 → sub=2, ZF=0 → JZ not taken → TOS=42
 *
 * If both match expectations, flags survived → use C version.
 * ================================================================ */

static void emit_bytes(const uint8_t *src, size_t len)
{
	memcpy(codebuf_w + here, src, len);
	here += len;
}

static int calibrate_one(fragment *c_frag, long expect_a)
{
	size_t save_here = here;

	/* Compose: prologue + sub + c_stack_op + JZ + load_42 + epilogue */
	emit_bytes(prologue_buf, prologue_len);
	emit_bytes(alu[ALU_SUB].code, alu[ALU_SUB].len);
	emit_bytes(c_frag->code, c_frag->len);
	size_t patch = emit_cond_forward(codebuf_w, &here, JCC_EQ);
	emit_load_imm(codebuf_w, &here, 42);
	patch_forward_branch(codebuf_w, patch, here);
	emit_bytes(epilogue_buf, epilogue_len);

	jit_exec_mode();

	/* Test A: TOS=5, NOS=5 → sub=0, ZF=1 → JZ taken → skip marker */
	dsp = &data_stack[DATA_STACK_SZ / 2];
	data_stack[DATA_STACK_SZ / 2]     = 777;
	data_stack[DATA_STACK_SZ / 2 + 1] = 888;
	tos = 5; nos = 5;
	((void (*)(void))(codebuf_x + save_here))();
	long result_a = tos;

	/* Test B: TOS=3, NOS=5 → sub=2, ZF=0 → JZ not taken → load 42 */
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
 * Expected TOS for test A (ZF=1, JZ taken — marker skipped):
 *
 * After alu_sub(5,5): TOS=0, NOS=5, dsp=[777, 888, ...]
 * Then each stack op:
 *   drop_tos: TOS=NOS=5, NOS=*dsp=777           → expect 5
 *   drop_nos: TOS=0 (unchanged), NOS=*dsp=777    → expect 0
 *   push_nos: TOS=0 (unchanged)                   → expect 0
 *   dup:      TOS=0 (unchanged), NOS=TOS=0        → expect 0
 *   swap:     TOS=NOS=5, NOS=TOS=0                → expect 5
 *   over:     TOS=NOS=5 (push_nos+swap)            → expect 5
 *   2drop:    TOS=*dsp=777, NOS=dsp[1]=888         → expect 777
 */
static const long calib_expect_a[] = {
	[MAC_DROP_TOS] = 5,
	[MAC_DROP_NOS] = 0,
	[MAC_PUSH_NOS] = 0,
	[MAC_DUP]      = 0,
	[MAC_SWAP]     = 5,
	[MAC_TEST_TOS] = 0,  /* unused — test_tos always asm */
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

	/* ---- Extract ALU prims with self-calibrating sacrifice ---- */

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

	printf("Self-calibrating ALU extraction:\n");
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

		printf("  → using %zu bytes (%s)\n", alu[i].len,
		       alu[i].code == fs.code ? "sacrifice" : "plain");
	}

	/* Extract CMP (sacrifice only) */
	if (extract_cmp((void *)alu_cmp_s, (void *)alu_cmp_end,
	                &alu[ALU_CMP], "cmp") != 0)
		return -1;
	printf("  cmp   sacrifice=%2zu → using %zu bytes\n",
	       alu[ALU_CMP].len + 4, alu[ALU_CMP].len);

	/* ---- Extract asm macros ---- */
	if (discover_macros(macro_table, asm_mac, MAC_COUNT) != 0)
		return -1;

	/* ---- Extract C-compiled stack ops ---- */
	for (int i = 0; i < MAC_COUNT; i++) {
		if (i == MAC_TEST_TOS) {
			/* test_tos uses sacrifice extraction (like CMP) */
			if (extract_test_tos(&c_mac[i]) != 0)
				c_mac[i] = asm_mac[i];
			continue;
		}
		if (extract_one((void *)c_macro_table[i].func,
		                (void *)c_macro_table[i + 1].func,
		                &c_mac[i]) != 0) {
			fprintf(stderr, "extract: no RET in c_%s\n",
			        c_macro_table[i].name);
			c_mac[i] = asm_mac[i]; /* fallback */
		}
	}

	/* ---- Nonleaf frame ---- */
	if (extract_nonleaf_frame() != 0) {
		fprintf(stderr, "init: nonleaf frame extraction failed\n");
		return -1;
	}

	/* ---- Flag-preservation calibration ---- */
	printf("\nStack op calibration:\n");
	for (int i = 0; i < MAC_COUNT; i++) {
		if (i == MAC_TEST_TOS) {
			/*
			 * test_tos SETS flags — different calibration.
			 * Compose: c_test_tos + JZ + load_42 + epilogue
			 * Test A: TOS=0 → ZF=1 → JZ taken → TOS stays 0
			 * Test B: TOS=5 → ZF=0 → JZ not taken → TOS=42
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

			/* Test A: TOS=0 → should stay 0 */
			dsp = &data_stack[DATA_STACK_SZ / 2];
			tos = 0; nos = 777;
			((void (*)(void))(codebuf_x + save))();
			long ra = tos;

			/* Test B: TOS=5 → should become 42 */
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
			} else {
				mac[i] = asm_mac[i];
				mac_source[i] = "asm";
			}
			printf("  %-10s C=%2zu bytes  asm=%2zu bytes → %s%s\n",
			       macro_table[i].name,
			       c_mac[i].len, asm_mac[i].len,
			       mac_source[i],
			       ok ? " (sets flags correctly)"
			          : " (flags incorrect)");
			continue;
		}

		/* Test C version for flag preservation */
		int preserved = calibrate_one(&c_mac[i], calib_expect_a[i]);
		if (preserved) {
			mac[i] = c_mac[i];
			mac_source[i] = "C";
		} else {
			mac[i] = asm_mac[i];
			mac_source[i] = "asm";
		}
		printf("  %-10s C=%2zu bytes  asm=%2zu bytes → %s%s\n",
		       macro_table[i].name,
		       c_mac[i].len, asm_mac[i].len,
		       mac_source[i],
		       preserved ? " (flags preserved)" : " (flags clobbered)");
	}

	/* ---- Compose dictionary words ---- */
	size_t start;

	/* + = alu_add + drop_nos (consuming: TOS=TOS+NOS, pop NOS) */
	start = here;
	emit_bytes(alu[ALU_ADD].code, alu[ALU_ADD].len);
	emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
	dict_add("+", codebuf_x + start, here - start, 1);

	/* - = alu_sub + drop_nos (consuming: TOS=NOS-TOS, pop NOS) */
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

	/* negate = alu_neg (unary, no stack pop) */
	start = here;
	emit_bytes(alu[ALU_NEG].code, alu[ALU_NEG].len);
	dict_add("negate", codebuf_x + start, here - start, 1);

	/* cmp = alu_cmp (non-consuming binary compare) */
	start = here;
	emit_bytes(alu[ALU_CMP].code, alu[ALU_CMP].len);
	dict_add("cmp", codebuf_x + start, here - start, 1);

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

	/* over = macro_over */
	start = here;
	emit_bytes(mac[MAC_OVER].code, mac[MAC_OVER].len);
	dict_add("over", codebuf_x + start, here - start, 1);

	/* 2drop = macro_2drop */
	start = here;
	emit_bytes(mac[MAC_2DROP].code, mac[MAC_2DROP].len);
	dict_add("2drop", codebuf_x + start, here - start, 1);

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
			cond_jmp = JCC_EQ;
		return;
	}

	if (strcmp(word, "0<>") == 0) {
		if (compiling)
			cond_jmp = JCC_NE;
		return;
	}

	if (strcmp(word, "0<") == 0) {
		if (compiling)
			cond_jmp = JCC_MI;
		return;
	}

	if (strcmp(word, "0>") == 0) {
		if (compiling)
			cond_jmp = JCC_GT;
		return;
	}

	/* ---- Compound comparisons (compare + select) ---- */

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

	/* ---- Flow control ---- */

	if (strcmp(word, "IF") == 0) {
		if (!compiling)
			return;
		/*
		 * Emit INVERTED conditional forward branch.
		 * FLAGS were set by a comparator; drop consumed
		 * the tested value (flags-preserving).
		 */
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
		printf("  PASS  %s (TOS=%ld)\n", desc, tos);
		pass_count++;
	}
	else {
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

	printf("Stack macros (selected):\n");
	for (int i = 0; i < MAC_COUNT; i++)
		printf("  %-10s %2zu bytes [%s]\n",
		       macro_table[i].name, mac[i].len, mac_source[i]);
	printf("Composed words:\n");
	for (int i = 0; i < dict_count; i++)
		printf("  %-8s %zu bytes%s\n",
		       dictionary[i].name, dictionary[i].code_len,
		       dictionary[i].is_prim ? " (inline)" : " (call)");
	printf("Nonleaf frame: prologue %zu, epilogue %zu\n\n",
	       prologue_len, epilogue_len);

	/* ==============================================================
	 * Section A: Basic arithmetic (sanity check from exp 008)
	 * ============================================================== */

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

	/* New ALU ops */
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

	/* ==============================================================
	 * Section B: 0= selector (zero / equal)
	 * ============================================================== */

	printf("\n--- B: 0= selector (zero/equal) ---\n");

	/* 0- 0= IF: test TOS, branch if zero */
	eval(": b1-take 0 0- 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("b1-take");
	check("0- 0= IF (zero → taken)", 42);

	eval(": b1-skip 5 0- 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("b1-skip");
	check("0- 0= IF (nonzero → skip)", 99);

	/* - 0= IF: subtract, branch if result zero */
	eval(": b2-eq 5 - 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("5");
	eval("b2-eq");
	check("5 5 - 0= IF (zero → taken)", 42);

	eval(": b2-ne 5 - 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("3");
	eval("b2-ne");
	check("3 5 - 0= IF (nonzero → skip)", 99);

	/* 1- 0= IF: decrement, branch if result zero */
	eval(": b3-hit 1- 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("1");
	eval("b3-hit");
	check("1 1- 0= IF (was 1 → taken)", 42);

	eval(": b3-miss 1- 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("3");
	eval("b3-miss");
	check("3 1- 0= IF (was 3 → skip)", 99);

	/* cmp = IF: non-consuming equal */
	eval(": b4-eq = drop IF 2drop 42 THEN ;");
	reset_stack();
	eval("5");
	eval("5");
	eval("b4-eq");
	check("5 5 = IF (equal → taken)", 42);

	eval(": b4-ne = drop IF 2drop 42 THEN ;");
	reset_stack();
	eval("5");
	eval("3");
	eval("b4-ne");
	/* Not equal: IF skipped, stack still has 5 3 with drop → TOS=5 NOS=... */
	check("5 3 = IF (not equal → skip)", 5);

	/* ==============================================================
	 * Section C: 0<> selector (nonzero / not-equal)
	 * ============================================================== */

	printf("\n--- C: 0<> selector (nonzero/not-equal) ---\n");

	eval(": c1-take 5 0- 0<> drop IF drop 77 THEN ;");
	reset_stack();
	eval("99");
	eval("c1-take");
	check("0- 0<> IF (nonzero → taken)", 77);

	eval(": c1-skip 0 0- 0<> drop IF drop 77 THEN ;");
	reset_stack();
	eval("99");
	eval("c1-skip");
	check("0- 0<> IF (zero → skip)", 99);

	eval(": c2-ne <> drop IF 2drop 77 THEN ;");
	reset_stack();
	eval("5");
	eval("3");
	eval("c2-ne");
	check("5 3 <> IF (not-equal → taken)", 77);

	eval(": c2-eq <> drop IF 2drop 77 THEN ;");
	reset_stack();
	eval("5");
	eval("5");
	eval("c2-eq");
	check("5 5 <> IF (equal → skip)", 5);

	/* ==============================================================
	 * Section D: 0< selector (negative / sign)
	 * ============================================================== */

	printf("\n--- D: 0< selector (negative/sign) ---\n");

	/* 0- 0< IF: test TOS, branch if negative */
	eval(": d1-neg 0- 0< drop IF drop 88 THEN ;");
	reset_stack();
	eval("99");
	eval("-5");
	eval("d1-neg");
	check("0- 0< IF (-5 → taken)", 88);

	eval(": d1-pos 0- 0< drop IF drop 88 THEN ;");
	reset_stack();
	eval("99");
	eval("5");
	eval("d1-pos");
	check("0- 0< IF (5 → skip)", 99);

	/* - 0< IF: subtract, branch if result negative */
	eval(": d2-less 3 - 0< drop IF drop 88 THEN ;");
	reset_stack();
	eval("99");
	eval("5");
	eval("d2-less");
	check("5 3 - 0< IF (5-3=2, positive → skip)", 99);

	eval(": d2-less2 5 - 0< drop IF drop 88 THEN ;");
	reset_stack();
	eval("99");
	eval("3");
	eval("d2-less2");
	check("3 5 - 0< IF (3-5=-2, negative → taken)", 88);

	/* < IF: non-consuming signed less-than */
	eval(": d3-lt < drop IF 2drop 88 THEN ;");
	reset_stack();
	eval("3");
	eval("5");
	eval("d3-lt");
	check("3 5 < IF (3<5 → taken)", 88);

	eval(": d3-ge < drop IF 2drop 88 THEN ;");
	reset_stack();
	eval("5");
	eval("3");
	eval("d3-ge");
	check("5 3 < IF (5≥3 → skip)", 5);

	/* ==============================================================
	 * Section E: 0> selector (positive / greater)
	 * ============================================================== */

	printf("\n--- E: 0> selector (positive/greater) ---\n");

	eval(": e1-pos 0- 0> drop IF drop 66 THEN ;");
	reset_stack();
	eval("99");
	eval("5");
	eval("e1-pos");
	check("0- 0> IF (5 → taken)", 66);

	eval(": e1-neg 0- 0> drop IF drop 66 THEN ;");
	reset_stack();
	eval("99");
	eval("-5");
	eval("e1-neg");
	check("0- 0> IF (-5 → skip)", 99);

	eval(": e1-zero 0- 0> drop IF drop 66 THEN ;");
	reset_stack();
	eval("99");
	eval("0");
	eval("e1-zero");
	check("0- 0> IF (0 → skip)", 99);

	/* > IF: non-consuming signed greater-than */
	eval(": e2-gt > drop IF 2drop 66 THEN ;");
	reset_stack();
	eval("5");
	eval("3");
	eval("e2-gt");
	check("5 3 > IF (5>3 → taken)", 66);

	eval(": e2-le > drop IF 2drop 66 THEN ;");
	reset_stack();
	eval("3");
	eval("5");
	eval("e2-le");
	check("3 5 > IF (3≤5 → skip)", 3);

	/* ==============================================================
	 * Section F: ALU ops × selectors in loops
	 * ============================================================== */

	printf("\n--- F: Loops (BEGIN...UNTIL) ---\n");

	/* Countdown: 5 to 0 using 1- 0= UNTIL */
	eval(": f1 5 BEGIN 1- dup 0- 0= drop UNTIL ;");
	reset_stack();
	eval("f1");
	check("countdown 1- 0= UNTIL", 0);

	/* Count up: start at -3, increment, loop until positive */
	eval(": f2 -3 BEGIN 1+ dup 0- 0> drop UNTIL ;");
	reset_stack();
	eval("f2");
	check("countup 1+ 0> UNTIL", 1);

	/* Sum 1..5 = 15 */
	eval(": f3 0 5 BEGIN swap over + swap 1- dup 0- 0= drop UNTIL drop ;");
	reset_stack();
	eval("f3");
	check("sum 1..5 = 15", 15);

	/* ==============================================================
	 * Section G: ALU flag-setting through composed words
	 * ============================================================== */

	printf("\n--- G: Flags through composed words ---\n");

	/* + sets flags: 3 + (-3) = 0 */
	eval(": g1 -3 + 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("3");
	eval("g1");
	check("3 + (-3) 0= IF (sum zero → taken)", 42);

	/* & sets flags: 0xF0 & 0x0F = 0 */
	eval(": g2 15 & 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("240");
	eval("g2");
	check("240 & 15 0= IF (AND zero → taken)", 42);

	/* & sets flags: 0xFF & 0x0F = 0x0F ≠ 0 */
	eval(": g3 15 & 0= drop IF drop 42 THEN ;");
	reset_stack();
	eval("99");
	eval("255");
	eval("g3");
	check("255 & 15 0= IF (AND nonzero → skip)", 99);

	/* ==============================================================
	 * Results
	 * ============================================================== */

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
