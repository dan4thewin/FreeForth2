/*
 * Portable FreeForth2 — Experiment 003: Copy and Execute
 *
 * Question: Can we copy primitive bytes into an executable buffer,
 * compose them into a sequence, and call the result?
 *
 * Test case: compose "dup" + "add" = a function that doubles TOS.
 *   Input stack:  ( 21 0 )    [TOS=21, NOS=0]
 *   After dup:    ( 21 21 0 ) [TOS=21, NOS=21, *DSP=0]
 *   After add:    ( 42 0 )    [TOS=42, NOS=0]
 *
 * We strip the RET from each primitive when copying (inline), then
 * append a single RET at the end.
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

/* --- Register pinning (x86-64) --- */
register long    tos  asm("rbx");
register long    nos  asm("rdx");
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

void __attribute__((noinline)) prim_end_sentinel(void) {
    asm volatile("nop");
}

/* --- Code composition engine --- */

static uint8_t *codebuf;
static size_t   codepos;
#define CODEBUF_SIZE 4096

static int code_init(void) {
    codebuf = mmap(NULL, CODEBUF_SIZE, PROT_READ | PROT_WRITE | PROT_EXEC,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (codebuf == MAP_FAILED) return -1;
    codepos = 0;
    return 0;
}

/* Find the body size (up to but not including RET) */
static size_t prim_body_size(void (*func)(void), void (*next)(void)) {
    uint8_t *start = (uint8_t *)func;
    size_t   gap   = (uint8_t *)next - start;
    for (size_t i = 0; i < gap; i++) {
        if (start[i] == 0xC3) return i;
    }
    return gap;
}

/* Copy primitive body (without RET) into codebuf */
static void code_emit_prim(void (*func)(void), void (*next)(void)) {
    size_t body = prim_body_size(func, next);
    memcpy(codebuf + codepos, (uint8_t *)func, body);
    codepos += body;
}

static void code_emit_ret(void) {
    codebuf[codepos++] = 0xC3;
}

/* --- Test --- */

int main(void) {
    static long stack[64];

    if (code_init() != 0) {
        printf("FAILED — mmap\n");
        return 1;
    }

    /* Compose: dup + add + ret  (should double TOS) */
    code_emit_prim(prim_dup,  prim_fetch);
    code_emit_prim(prim_add,  prim_drop);
    code_emit_ret();

    printf("Composed %zu bytes: ", codepos);
    for (size_t i = 0; i < codepos; i++)
        printf("%02x ", codebuf[i]);
    printf("\n");

    /* Set up register state and call composed code */
    void (*composed)(void) = (void (*)(void))codebuf;

    dsp = &stack[32];
    nos = 0;
    tos = 21;

    composed();

    printf("TOS = %ld (expected 42)\n", tos);
    printf("NOS = %ld (expected 0)\n", nos);

    if (tos == 42 && nos == 0) {
        printf("PASSED\n");
        return 0;
    } else {
        printf("FAILED\n");
        return 1;
    }
}
