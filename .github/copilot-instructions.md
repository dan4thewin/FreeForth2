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

## Build and test

- `make all` builds both `ff` (32-bit) and `ff64` (64-bit)
- `make -C exp test` runs all experiments (currently 20, all PASS)
- `./ff64 -f ff64.boot` loads the standard library
- Assembler is FASM (flat assembler, version 1.73.32)
- Linker warning about RWX segment is expected
