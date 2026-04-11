/*
 * overrides_x86_64.h — asm fallbacks for x86-64
 *
 * These exist ONLY because GCC's x86-64 code generation uses ADD
 * (which clobbers flags) for dsp++ operations.  On architectures
 * where GCC produces flag-preserving code, this file does not exist
 * and is not needed.
 *
 * Each function is extracted at init time.  The calibration loop
 * tests whether the C version preserves flags; if not, it looks
 * here for a replacement.  If neither works, the build fails.
 */

#ifndef OVERRIDES_X86_64_H
#define OVERRIDES_X86_64_H

#define HAS_ASM_OVERRIDES 1

void __attribute__((noinline)) asm_drop_tos(void)
{
	asm volatile(
		"mov %%r13, %%rbx\n\t"
		"mov (%%r15), %%r13\n\t"
		"lea 8(%%r15), %%r15"
		::: "memory"
	);
}

void __attribute__((noinline)) asm_drop_nos(void)
{
	asm volatile(
		"mov (%%r15), %%r13\n\t"
		"lea 8(%%r15), %%r15"
		::: "memory"
	);
}

void __attribute__((noinline)) asm_push_nos(void)
{
	asm volatile(
		"lea -8(%%r15), %%r15\n\t"
		"mov %%r13, (%%r15)"
		::: "memory"
	);
}

void __attribute__((noinline)) asm_dup(void)
{
	asm volatile(
		"lea -8(%%r15), %%r15\n\t"
		"mov %%r13, (%%r15)\n\t"
		"mov %%rbx, %%r13"
		::: "memory"
	);
}

void __attribute__((noinline)) asm_swap(void)
{
	asm volatile(
		"xchg %%rbx, %%r13"
		:::
	);
}

void __attribute__((noinline)) asm_over(void)
{
	asm volatile(
		"lea -8(%%r15), %%r15\n\t"
		"mov %%r13, (%%r15)\n\t"
		"xchg %%rbx, %%r13"
		::: "memory"
	);
}

void __attribute__((noinline)) asm_2drop(void)
{
	asm volatile(
		"mov (%%r15), %%rbx\n\t"
		"mov 8(%%r15), %%r13\n\t"
		"lea 16(%%r15), %%r15"
		::: "memory"
	);
}

void __attribute__((noinline)) asm_end(void) { asm volatile("nop"); }

/*
 * Override table — same order as MAC_* enum.
 * Entries may be NULL (no override for that op).
 * test_tos has no override — C sacrifice works everywhere.
 */

typedef struct {
	const char *name;
	void       (*func)(void);
} override_info;

static override_info override_table[] = {
	{ "drop_tos",  asm_drop_tos  },  /* MAC_DROP_TOS */
	{ "drop_nos",  asm_drop_nos  },  /* MAC_DROP_NOS */
	{ "push_nos",  asm_push_nos  },  /* MAC_PUSH_NOS */
	{ "dup",       asm_dup       },  /* MAC_DUP      */
	{ "swap",      asm_swap      },  /* MAC_SWAP     */
	{ NULL,        asm_over      },  /* MAC_TEST_TOS — no override, func=next boundary */
	{ "over",      asm_over      },  /* MAC_OVER     */
	{ "2drop",     asm_2drop     },  /* MAC_2DROP    */
	{ NULL,        asm_end       },  /* sentinel     */
};

#endif
