/*
 * Portable FreeForth2 — Experiment 005: Cross-Architecture
 *
 * Question: Does the same C source produce correct primitives for
 * ARM64 (AArch64)?
 *
 * This is the SAME primitive code as experiments 001-004, but with
 * an architecture-specific register mapping header.  We compile for
 * ARM64 and verify the disassembly shows correct register usage
 * and minimal instruction sequences.
 *
 * ARM64 register mapping:
 *   TOS = x19   (callee-saved)
 *   NOS = x20   (callee-saved)
 *   DSP = x21   (callee-saved)
 *
 * ARM64 callee-saved: x19-x28.  We pick the first three.
 */

#include <stdint.h>

/* --- Architecture-specific register mapping --- */
#if defined(__aarch64__)
register long    tos  asm("x19");
register long    nos  asm("x20");
register long   *dsp  asm("x21");
#elif defined(__x86_64__)
register long    tos  asm("rbx");
register long    nos  asm("r13");
register long   *dsp  asm("r15");
#else
#error "Unsupported architecture"
#endif

/* --- Primitives — IDENTICAL source for both architectures --- */

void prim_add(void) {
    tos += nos;
    nos = *dsp;
    dsp++;
}

void prim_drop(void) {
    tos = nos;
    nos = *dsp;
    dsp++;
}

void prim_dup(void) {
    dsp--;
    *dsp = nos;
    nos = tos;
}

void prim_fetch(void) {
    tos = *(long *)tos;
}

void prim_store(void) {
    *(long *)tos = nos;
    tos = *dsp;
    nos = *(dsp + 1);
    dsp += 2;
}
