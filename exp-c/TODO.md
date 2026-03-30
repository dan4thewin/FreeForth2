# Portable FreeForth2 — TODO

## Active

- Next experiment TBD (full flow control: ELSE, WHILE/REPEAT, BREAK, CASE?)
- Investigate non-fusing ops (OR, XOR, NEG) + 0</0> on ARM64:
  for non-fusing ops, the sacrifice adds a separate CMP that tests
  the *original* TOS, not the result.  0= and 0<> work (they only
  need ZF from the CMP-against-zero).  0< and 0> may give wrong
  results because the sign/comparison is against the pre-op value.
  Needs investigation if these combinations are ever used in practice.

## Deferred

- Dictionary structure in C
- Boot file loading (ff2.boot equivalent)
- libc interaction with global register variables
- WASM target investigation
- Return stack operations (>r, r>, r)
- String handling and I/O
- The REPL
- Backtick macros and suffix handling

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
- **exp-009**: Sacrificial compare + full comparator×selector matrix ✓
  - Sacrificial `return tos == 0` coerces SUBS/ADDS on ARM64
  - Self-calibrating extraction (plain vs sacrifice, substring search)
  - All 8 ALU ops with sacrifice pattern (6/8 fuse on ARM64)
  - Non-consuming binary CMP from sacrifice-only extraction
  - 4 Jcc selectors: 0= (ZF), 0<> (!ZF), 0< (SF), 0> (GT)
  - Compound comparisons: =, <>, <, > (CMP + selector)
  - New macros: over, 2drop
  - 38/38 tests on x86-64 and ARM64
- **exp-010**: Auto-calibrating stack operations ✓
  - C-compiled stack ops tested for flag preservation at runtime
  - test_tos from C sacrifice (same pattern as ALU ops)
  - ARM64: all 8 C ops pass — zero inline asm selected
  - x86-64: 5/8 C ops pass (push_nos, dup, swap, test_tos, over)
  - 38/38 tests on x86-64 and ARM64
