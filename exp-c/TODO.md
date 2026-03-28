# Portable FreeForth2 — TODO

## Active

- **exp-001**: Naked primitives — verify Clang emits clean code
- **exp-002**: Runtime byte extraction — read primitive bytes at runtime
- **exp-003**: Copy-and-execute — copied primitives run correctly
- **exp-004**: Minimal Forth compiler — compile and run `: double dup + ;`
- **exp-005**: Cross-architecture — same source compiles for ARM64

## Deferred

- Flow control emission (IF/THEN/BEGIN) — architecture-specific jump encoding
- Dictionary structure in C
- Boot file loading (ff2.boot equivalent)
- libc interaction with global register variables
- WASM target investigation

## Done

(none yet)
