# Copilot Instructions for FreeForth2

## About this project

FreeForth2 is derived from FreeForth by Christophe Lavarenne (1956–2011).
The x86-64 port is an ongoing effort on the `exp64-1` branch.

## Approach

DG asked for an incremental, experiment-based approach:

- **Small, conservative goals** — each yielding a runnable binary with a
  Makefile test target, collected in separate directories
  (e.g., `exp/001-dup-test/{Makefile,dup.asm,dup}`).
- **Compile and test at every step** — don't move on until the current
  experiment passes.

## Documentation for a future historian

DG asked that this effort be documented as a journey — "take a future
historian on the journey of an AI perpetuating the life's work of a
deceased human." Specifically:

- **Two documents**: `exp/JOURNAL.md` chronicles each experiment with
  goals, actions, and reasoning. `exp/GUIDE.md` is the historian's
  guide explaining the system.
- **Explain every piece** — for every Forth definition (including those
  already in ff64.boot) and every logical section of assembly code:
  explain how the original i386 piece works, how the ported x86-64
  piece works, and why they differ. Only add the "why" when you don't
  have to guess.
- **Assume a rudimentary grasp of assembly** — be generous in
  descriptions and explanations.

## Preserve FreeForth's character

This is a core design principle from DG and from Lavarenne's original work:

- **Assembly is intentionally minimal** — most things are implemented
  in Forth, not assembly. This is in stark contrast to most
  assembly-based Forths that use assembly for all their primitives.
- **Items in ff.boot should be ported to ff64.boot, not ff64.asm**,
  unless it's unavoidable as a consequence of the new data stack design.
- Lavarenne's choice to implement `dup` as `under` `nipdup` contains a
  deep revelation about this philosophy.

## FLAGS-based conditionals

FreeForth uses CPU FLAGS rather than stack booleans for conditionals.
This is a defining attribute of FreeForth (and FreeForth2):

- Comparison words (`<`, `>`, `=`, etc.) set FLAGS and store a jump
  opcode in `cond_jmp` — they do NOT push a boolean.
- `IF`, `UNTIL`, `WHILE` read `cond_jmp` and emit a conditional jump
  directly. No boolean, no test, no DROP.
- `IF`/`UNTIL`/`WHILE` **require** an explicit preceding condition.
  The README states: "requires explicit conditions before IF — avoids
  source of faulty assumptions."
- Dotted comparisons (`=.`, `<.`, etc.) and `IF.`/`WHILE.`/`UNTIL.`
  are legitimate words but belong in Forth (ff64.boot), not assembly.

## Debugging generated code

FreeForth's compiler generates machine code at runtime. When something
crashes or behaves wrong, **use GDB first** — don't try to reason about
the bug by manually tracing SWAPbit state or flag preservation through
compilation passes. That approach is extremely error-prone and slow.

### What works

- **GDB disassembly of generated code.** Build without `-s` (strip),
  run under GDB, examine the crash site with `x/Ni $rip` and
  `x/Ni addr` to see the actual machine code the compiler emitted.
  The generated code is the ground truth. Example workflow:
  ```
  echo 'test-input' | gdb -batch -ex 'run -f ff64.boot' -ex 'x/30i $rip-40' ./ff64
  ```
- **Tracing back from the crash.** If RIP is a small number (like 9),
  it means execution jumped to a data value — check what constant or
  literal has that value. The return stack (`x/4gx $rsp`) shows where
  the bad call/jump came from.
- **Disassembling a word with the i386 `ff`.** Use `see wordname` on
  the original 32-bit binary to understand how Christophe's compiler
  generates code for a given pattern. This is faster than reading the
  compiler source.

### What doesn't work

- **Manual SWAPbit tracing.** Tracking SWAPbit through every macro
  expansion is extremely complex and unreliable. There are too many
  toggles (swap\`, lit\`, dup>r\`) and adjusters (s01, s08, s09) to
  trace reliably in your head. Use GDB to see the actual emitted bytes.
- **Theorizing without evidence.** Don't spend time hypothesizing about
  flag preservation, register clobbering, or stack corruption without
  first looking at the generated machine code. The hypothesis is often
  wrong.
- **Progressive test simplification alone.** Narrowing a crash by
  removing words from a test definition can help, but is slow and can
  lead to wrong conclusions (e.g., creating a "simplified" test that
  crashes for a different reason than the original).

### The ct=1 bug as a cautionary tale

The `words` crash (exp 038) took extensive manual analysis of SWAPbit
state, flag preservation, and stack operations — all of which turned out
to be red herrings. One GDB session showing `jmp 0x9` immediately
revealed that the compile-time stack was corrupted by a constant value.
**Always check the generated code first.**

## OS/Architecture separation

The port follows Lavarenne's cross-platform pattern:

- **`ff64.asm` + `ff64.boot`** — architecture-specific (x86-64):
  compiler, backtick macros, stack ops, flow control, SWAPbit, REPL
- **`fflin64.boot`** — OS-specific (Linux): dlopen/dlsym, file
  loading, command-line processing, SEGV handler, boot sequence

The Makefile concatenates both into `ff64.boot.min` for embedding.
Future ports: ARM64 would replace ff64.asm/ff64.boot but reuse
fflin64.boot; macOS would replace fflin64.boot but reuse ff64.boot.

## Resolved bugs

### The `_parse` stack effect bug (was "ELSE corruption bug")

The long-standing "ELSE corruption bug" — where IF/ELSE/THEN in `:`
definitions could corrupt definitions 250+ lines later — was actually
a bug in `_parse`. The x86-64 `_parse` entry did DROP1 (consuming
TOS + popping memory stack) instead of the i386's DUP1. Every call
to `parse` or `lnparse` consumed one extra stack item, causing
cumulative compile-time stack corruption.

**Fixed in commit `8d17367`.** ELSE works correctly. The IF...;THEN
workarounds throughout ff64.boot are no longer necessary.

### The pick/2over compile-time stack leak (exp 104)

`_pick_detect` had three bugs: (1) comparison residuals leaked onto
the compile-time stack, (2) the 6A-literal path emitted i386-specific
code, (3) BB-path detection didn't mask SWAPbit (BA vs BB). The fix
was two separate handlers (`_pick_bb` and `_pick_6a`) matching the
i386 architecture exactly, found by disassembling i386 `pick` with
`see`.

### The BEGIN/CASE/BREAK/END crash (exp 105)

Two bugs: (1) END emitted a backward E9 jump, but per Lavarenne's
docs END only resolves forward refs — backward jumps come exclusively
from AGAIN/UNTIL/REPEAT. (2) BEGIN didn't set up mrk or cstack for
BREAK/END. Fixed by unifying all flow control around a shared `_begin`
helper with mrk + cstack, and removing END's backward jump.

### Other resolved issues (exp 104)

- **++/--**: Not broken — tests used wrong syntax. Requires `@` suffix
  (e.g., `foo@ ++` not `foo ++`).
- **within**: Not broken — needs `0<> IF` pattern, not bare `IF`.
  `within` returns FLAGS, and `IF` requires a compile-time condition.

## Completion checklist

Every task must end with:

1. Run `make -C exp test` — **all tests must pass**. Do not dismiss
   failures as "pre-existing" without verifying they existed before
   your changes. If you broke it, fix it.
2. Update `exp/JOURNAL.md` — experiment entry with goals, actions,
   reasoning
3. Update `exp/GUIDE.md` — if new concepts or architecture introduced
4. Add novel user-facing words to `ff64.help`
5. `git commit` with descriptive message
6. `git push` (use `source ~/.bash_ssh` for SSH agent)

Do not mark the task complete until all steps are done.

## Build and test

- `make all` builds both `ff` (32-bit) and `ff64` (64-bit)
- `make -C exp test` runs all experiments (currently 48, all PASS).
   The test runner exits nonzero if any experiment fails — never
   commit with failing tests.
- `./ff64 -f ff64.boot` loads the standard library (via ff64.boot.min
  which includes fflin64.boot)
- Assembler is FASM (flat assembler, version 1.73.32)
- Linker warning about RWX segment is expected
