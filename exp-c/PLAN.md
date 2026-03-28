# Portable FreeForth2 — Plan

## Goal

Determine whether FreeForth2's assembly core can be replaced by C
(compiled with Clang) in a way that:

1. Naked C functions produce minimal, copyable machine code for each
   primitive (add, drop, dup, @, !, etc.)
2. The Forth compiler can discover each primitive's code bytes at
   runtime (no object-file surgery)
3. Backtick macros copy those bytes into compiled definitions, exactly
   as today's assembly-based macros do
4. The same C source compiles for multiple architectures (x86-64,
   ARM64) — the C compiler is the portability layer
5. SWAPbit is abandoned — one fixed register assignment per architecture

## Approach

Small experiments, each producing a runnable binary with a Makefile.
Prove or disprove viability early — don't build a cathedral before
testing the foundation.

## Experiments

### 001 — Naked primitives (does Clang emit what we need?)

Write 5 core primitives as `__attribute__((naked))` C functions with
global register variables. Compile with Clang `-O2`. Disassemble.
Verify the output is the minimal instruction sequence we'd hand-write.

**Success criteria:** Each function body is ≤10 bytes, no prologue/
epilogue, no memory spills, correct register usage.

### 002 — Runtime byte extraction (can we read our own code?)

At runtime, read the bytes of each naked function by pointer arithmetic
(function address → next function address). Verify they match the
disassembly from exp 001.

**Success criteria:** A C program prints the hex bytes of each
primitive, matching objdump output exactly.

### 003 — Copy-and-execute (does the copied code work?)

Allocate an executable buffer (mmap RWX), copy primitive bytes into it
as a sequence (simulating what the Forth compiler does), call the
buffer. Verify correct results.

**Success criteria:** Copied code executes correctly, produces the
right stack state.

### 004 — Minimal Forth compiler in C

Build the smallest possible Forth compiler in C that:
- Maintains TOS/NOS/DSP in global register variables
- Has a primitive table (code pointer + size for each primitive)
- Parses words, looks them up, copies their bytes into a code buffer
- Can compile and execute `: double dup + ;`

**Success criteria:** `double` works. We've round-tripped from C
primitives through Forth compilation back to execution.

### 005 — Cross-architecture validation

Cross-compile exp 001 for ARM64 with `clang --target=aarch64-linux-gnu`.
Verify the emitted bytes are valid ARM64 instructions operating on the
correct registers.

**Success criteria:** ARM64 disassembly shows the expected register
usage and instruction selection. Same C source, different target, correct output.

## Non-goals (for now)

- Full FreeForth2 port — we're testing the foundation, not building
  the house
- Boot file compatibility — ff2.boot comes later if viability is proven
- Performance benchmarking — correctness first
- SWAPbit replacement — abandoned, not replaced

## Key risks

- Clang may add unexpected instructions in naked functions (alignment
  nops, stack adjustments) on some targets
- Global register variables may conflict with libc on some platforms
- Flow-control primitives (branches, conditionals) may need
  architecture-specific knowledge that C can't abstract away
- The Forth compiler engine itself (parsing, dictionary) may be hard
  to express efficiently with register-pinned TOS/NOS
