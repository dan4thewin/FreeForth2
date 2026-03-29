# Portable FreeForth2 — TODO

## Active

- Next experiment TBD (flow control? deeper nesting? boot loading?)

## Deferred

- Flow control emission (IF/THEN/BEGIN) — architecture-specific jump encoding
- Dictionary structure in C
- Boot file loading (ff2.boot equivalent)
- libc interaction with global register variables
- WASM target investigation

## Done

- **exp-001**: GCC produces clean, prologue-free primitives ✓
- **exp-002**: Runtime byte extraction via pointer arithmetic ✓
- **exp-003**: Copy-and-execute: dup+add → 42 ✓
- **exp-004**: Minimal Forth compiler: colon definitions work ✓
- **exp-005**: ARM64 cross-compile: same source, correct output ✓
- **exp-006**: Portable mini-compiler: x86-64 Linux + ARM64 macOS ✓
  - W^X: dual-mapping (Linux) vs MAP_JIT (macOS)
  - Nonleaf frame extraction: C determines prologue/epilogue
  - Nested calls work on both platforms (5/5 tests)
- **exp-007**: Minimal flow control: IF/THEN, BEGIN/UNTIL ✓
  - Stack booleans (not FLAGS) for portable conditionals
  - Save-to-scratch pattern works around x86 ADD clobbering flags
  - ~20 lines per-arch for branch emission + C reference functions
  - 12/12 tests on x86-64 and ARM64
- **exp-008**: FLAGS-based flow control ✓
  - Decomposed: C ALU ops + inline asm stack macros (LEA on x86-64)
  - FLAGS survive through drop — FreeForth's model restored
  - 0= / 0<> are compile-time Jcc selectors (no runtime code)
  - False-RET bug: backward scan for x86-64 0xC3
  - 12/12 tests on x86-64, x86-64+CET, and ARM64
