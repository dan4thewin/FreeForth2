# Portable FreeForth2 — TODO

## Active

- **exp-005**: Cross-architecture — same source compiles for ARM64

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
