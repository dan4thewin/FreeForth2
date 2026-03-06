# Copilot Instructions for FreeForth2

## About this project

FreeForth2 is derived from FreeForth by Christophe Lavarenne (1956–2011).
The x86-64 port is an ongoing effort on the `static-elf64` branch.

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

## Porting principle: semantics, not encodings

When porting backtick macros from i386, **port the compile-time
semantics, not the x86 instruction encoding.**  A backtick macro's job
is to resolve things at compile time and emit whatever runtime code
achieves the effect.  If the i386 version emits a single `mov [abs32],
imm32` and x86-64 has no equivalent, the answer is *not* "make it a
runtime word" — it's "emit different instructions (`lit`/`d!``) that
achieve the same compile-time resolution."  FreeForth's `lit`` and the
backtick store/fetch macros are the portable building blocks.

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
- **Conditional inversion.** `IF`, `WHILE`, and `UNTIL` all XOR the
  condition with 1 (invert the jump sense). `IF`/`WHILE` emit a
  forward jump (skip body when condition is FALSE). `UNTIL` emits a
  backward jump (loop when condition is FALSE). So `0<> WHILE` means
  "continue while nonzero" and `0<> UNTIL` means "loop until nonzero"
  (exits on nonzero, loops on zero) — these are **opposite senses**.
  Getting this wrong is a common source of infinite loops.
- **FLAGS cross word boundaries.** `0=`/`0<>`/`0<`/`0>` emit NO
  runtime code — they only store a Jcc opcode in `cond_jmp`. It is
  `0-` (emitting `or reg,reg`) or binary comparisons (`=`, `<`, etc.)
  that set CPU FLAGS at runtime. Since `CALL`/`RET` don't modify
  RFLAGS, and `drop` is flags-preserving (`mov`+`lea`), a word can
  set FLAGS internally (via subtraction, test, etc.) and the caller
  just writes `0= IF`. What can't cross is `cond_jmp` (compile-time
  state), which the caller's `0=` trivially re-establishes.

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

## File loading: eval, not assembly

File loading is pure Forth — there is no assembly `_loadfile`.
`needed` (in fflin64.boot) opens a file, reads it into the tib
buffer, and calls `eval`. `eval` saves/restores `>in`/`tp` around
a call to `compiler`. This matches the i386 design exactly.

**`needs` vs `needed`:** `needs` is the user-facing backtick macro:
`` ; wsparse needed ;` ``. The leading `;` flushes anonymous code
before `needed` runs. This prevents the code-overwrite problem
(inner compilation writing at `[anon]` where the caller's anonymous
code lives). All practical file loading goes through `needs`.

**Historical note:** ff64 previously had a ~107-line assembly
`_loadfile` with its own `filebuf` and `hereatexec` variable.
This was removed in experiment 141 after discovering the i386
never had anything like it.

## ELF binary layout

ff64.asm has two ELF sections (in the `ffdl` / dynamic-link build):

- **`.flat`** (PROGBITS, WAX): code, initialized data, dictionary
  headers (`GENWORDS64`), embedded boot source, and `headbuf`
  (64KB, interleaved with initialized data).
- **`.bss`** (NOBITS, WA): uninitialized buffers — `tib` (256KB),
  `eob` (1KB), `helpbuf` (128KB), `dstack` (8KB), `codebuf` (64KB).
  Not stored in the file; the kernel demand-allocates zero pages at
  runtime.

The linker merges both into one RWE LOAD segment with
`MemSiz > FileSiz`. **New `rb` buffers go in `.bss`**, after the
`section '.bss'` directive. Don't put `rb` in `.flat` — it bloats
the binary with zeros on disk.

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

## Bug policy: zero tolerance

Finding a bug in the compiler or runtime is a **stop-everything** event.
Never work around a bug — fix it immediately. A workaround masks the
problem and lets it compound: tests pass but don't test what they claim
to, and everything built on top rests on a false floor.

- **Clear bug** (wrong behavior): drop current task and fix it now.
- **i386/ff64 behavioral difference**: document it and bring it to DG
  for triage — it may be a bug or it may be acceptable divergence
  (like the missing-semicolon-at-EOF behavior). Don't silently route
  around it.
- **The n^ bug as a cautionary tale**: the compile-time n^ bug was
  present since the port began. Every test that used `-f` was actually
  testing nothing — _postboot was silently dead, doargv never fired.
  Dozens of experiments piped stdin as a workaround. One fix to n^
  (one line) unlocked argv, -f, and the make test64 target.

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
- Three test gates — **all must pass before commit**:
  - `make test` — i386: 4 configs (ff, ff+longconds, fftk, fftk+longconds)
    × test/* (excludes test64.ff)
  - `make test64` — ff64: test/* via `-f` (skips core1/core2/mmap which
    need compat.ff)
  - `make -C exp test` — all experiment Makefiles
- `./ff64 -f ff64.boot` loads the standard library (via ff64.boot.min
  which includes fflin64.boot)
- Assembler is FASM (flat assembler, version 1.73.32)
- Linker warning about RWX segment is expected

## Quick Reference

### Register allocation

| Register | Role | Notes |
|----------|------|-------|
| `rbx` | TOS (top of stack) | SWAPbit=0 |
| `rdx` | NOS (next on stack) | SWAPbit=0 |
| `r15` | Data stack pointer | Points to 3rd+ items in memory |
| `rsp` | Return stack | Standard call/ret |
| `rbp` | HERE / compilation pointer | Where next compiled byte goes |
| `rax` | Scratch / syscall number | |
| `rcx` | Scratch / counter | ch used by SWAPbit XOR (SC byte) |
| `rdi`,`rsi` | Scratch / syscall args | |

When SWAPbit=1 (SC bit 1 set): rbx and rdx swap roles.

### Literal compiler suffixes

The COMPILER (not interpreter) handles these on number tokens:

| Suffix | Effect | Example |
|--------|--------|---------|
| `,` | Emit `mov [rbp], imm` meta-instruction (NO rbp advance) | `$DA89,` |
| `@` | Compile fetch from address | `foo@` |
| `!` | Compile store to address | `foo!` |
| `_` | Replace TOS with value | `42_` |
| `+` `-` `*` `/` `%` `&` `\|` `^` | Arithmetic with immediate | `8+` `$FF&` |

litcomma (`,` suffix) ONLY writes bytes at [rbp]. Advance is separate
via `,1`–`,4` or `s01`/`s08`/`s09`/`s1`.

### SWAPbit advance helpers

| Word | rbp advance | XOR mask | Use case |
|------|-------------|----------|----------|
| `,1`–`,4` | +N | none | Fixed bytes |
| `s01` | +2 | bit 0 (dst) | Dest reg field |
| `s08` | +2 | bit 3 (src) | Source reg field |
| `s09` | +2 | bits 0+3 | Both reg fields |
| `s1` | +1 | bit 0 | Single-byte opcodes |

**CRITICAL:** `s01`/`s08`/`s09` advance by 2 AND XOR. Don't use after
`,N` if all bytes are already placed — adds 2 spurious bytes.

### String encoding

In `"..."`, `."..."`, `!"..."`:
`_` = space, `^X` = toggle bit 6 of next char (^J=newline, ^I=tab),
`~` = toggle bit 7 of previous byte, `\X` = literal next char.
Space char: use `$20` (not `' '`).

### Number prefixes

`$` = hex, `%` = binary, `-` = negative. ff64 lacks `&` (octal).
In numbers: `'` `,` `.` `/` are ignored (digit grouping).
`#` changes base to value so far. Character literal: `'X`.

### Header structure

```
+0: 8 bytes — XT       +8: ct byte    +9: name length    +10: name
```
ct: 0=code, 1=data, 2=immediate, 8=anon, 9=pvt, $20=alias, $21=constant.
Constants: `h.ct`=8, `h.sz`=9, `h.nm`=10.

### Vectors

```forth
:^ vec body ;            \ define vector
new ' vec !^             \ redirect (macro: -call)
vec n^                   \ nop vector (macro: -call)
vec ' ^^                 \ reset to default (runtime word)
vec ' x^                 \ call original body (runtime word)
vec ' @^                 \ fetch current target (runtime word)
```

`!^` and `n^` are compile-time macros using `-call`. `^^`, `x^`, `@^`
are runtime words — x86-64 can't encode abs64 in immediates like i386.

### Flow control

```forth
IF ... THEN              \ conditional (requires preceding condition)
IF ... ELSE ... THEN     \ two-way
IF ... ;THEN             \ early return
BEGIN ... cond UNTIL     \ loop until true
BEGIN ... cond WHILE ... REPEAT
START ... ENTER ... REPEAT  \ body skipped first time
TIMES ... REPEAT         \ counted loop (i386 uses REPEAT, not LOOP)
CASE ... ;;              \ multi-way dispatch
```

**Note:** `LOOP` is NOT a Lavarenne word — it was invented during the
ff64 port. The i386 closes `TIMES` with `REPEAT`. ff64 accepts both
`TIMES...REPEAT` and `TIMES...LOOP` but prefer `REPEAT` for fidelity.

### Key non-obvious words

| Word | Stack | Notes |
|------|-------|-------|
| `find` | `( @ # -- xt 0 \| @ # )` | 0 = FOUND |
| `0;` | `( n -- n \| )` | Return if zero |
| `0<>;` | `( n -- n \| )` | Return if nonzero |
| `drop` | flags-preserving | `mov`+`lea`, no flag clobber |
| `bye` | backtick macro | Kills process at compile time inside `:` — use `; t bye` |

### Test pattern

```bash
timeout 5 ./ff64 ': prompt ;' -f test.ff
```
Boot is baked in. Suppress prompt via argv. Top-level code in loaded
files needs trailing `;` to execute.
