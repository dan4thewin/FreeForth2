/*
 * Portable FreeForth2 — Experiment 001: Naked Primitives
 *
 * Question: Does GCC emit minimal, copyable machine code for
 * Forth primitives written as C functions with global register
 * variables?
 *
 * Note: Clang does NOT support global register variables.
 * GCC does — and with -O2 -fomit-frame-pointer, it produces
 * prologue-free code for functions that only use pinned registers.
 *
 * Register mapping (x86-64):
 *   TOS = rbx    (top of data stack)
 *   NOS = rdx    (next on data stack)
 *   DSP = r15    (data stack pointer, points to 3rd+ items)
 *
 * Compile:  gcc -O2 -fomit-frame-pointer -c -o prims.o prims.c
 * Inspect:  objdump -d prims.o
 */

#include <stdint.h>

/* --- Register pinning (x86-64) --- */
register long    tos  asm("rbx");
register long    nos  asm("rdx");
register long   *dsp  asm("r15");

/* --- Primitives ---
 *
 * Each is a normal C function.  With global register variables,
 * GCC knows TOS/NOS/DSP are already in registers and won't emit
 * save/restore code for them.  The only overhead should be RET.
 */

/*
 * + (add): ( a b -- a+b )
 * TOS = NOS + TOS; drop NOS from memory stack.
 * Expected body: add rbx, rdx ; mov rdx, [r15] ; lea r15, [r15+8]
 */
void prim_add(void) {
    tos += nos;
    nos = *dsp;
    dsp++;
}

/*
 * drop: ( a b -- a )
 * TOS = NOS; NOS = *DSP++
 * Expected body: mov rbx, rdx ; mov rdx, [r15] ; lea r15, [r15+8]
 */
void prim_drop(void) {
    tos = nos;
    nos = *dsp;
    dsp++;
}

/*
 * dup: ( a -- a a )
 * *--DSP = NOS; NOS = TOS
 * Expected body: lea r15, [r15-8] ; mov [r15], rdx ; mov rdx, rbx
 */
void prim_dup(void) {
    dsp--;
    *dsp = nos;
    nos = tos;
}

/*
 * @ (fetch): ( addr -- value )
 * TOS = *(long *)TOS
 * Expected body: mov rbx, [rbx]
 */
void prim_fetch(void) {
    tos = *(long *)tos;
}

/*
 * ! (store): ( value addr -- )
 * *(long *)TOS = NOS; drop two
 * Expected body: mov [rbx], rdx ; mov rbx, [r15] ; mov rdx, [r15+8] ; lea r15, [r15+16]
 */
void prim_store(void) {
    *(long *)tos = nos;
    tos = *dsp;
    nos = *(dsp + 1);
    dsp += 2;
}
