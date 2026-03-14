# FreeForth2 — Backlog

Last verified: 131 PASSED, 3 SKIPPED (`make testall`).

## Bugs

- **fix-see64-rex**: REX.R decoding bug in `lib/x86-64/see.ff`.
  `4C 89 FA` decodes as `mov r10,r15` but should be `mov rdx,r15` —
  REX.R extends the reg field (source in `89 /r`), not the r/m field.
  `r64r` uses `rexR?` correctly, but something in the mod/rm dispatch
  applies the REX.R bit to the wrong operand. Identified in DG's `out`
  file; mentioned in 4+ checkpoints but never fixed.

- **fix-d@-help**: `d@` help text is wrong across three files.
  ff64.help says "d@ is equivalent to @" but `d@`` compiles `movsxd`
  (`48 63 1B` = sign-extend 32-bit to 64-bit), NOT a 64-bit load.
  Fix ff64.help, QUICKREF, and TINYREF to say "sign-extended 32-bit
  fetch" instead.

- **help-noarg**: Bare `help` (no argument) shows wrong output on ff64.
  The display loop's empty-line detection uses `>in@ over- 2* + 1-`
  pointer math — the `2*` was correct for 32-bit pointers but needs
  adjustment for 64-bit. Test in `exp/067-help/Makefile` is skipped
  (`test-help-noarg`, 4/5 pass). The ff.help preamble search/display
  code (lines 7–16 of ff.help) runs in the tib after `needed` loads
  the file.

- **fix-073**: Turnkey REPL SEGV — REPL segfaults in turnkey binaries.
  Turnkey binaries with explicit `main` work fine (hello, 42, dup).
  REPL input to a turnkey (no `-f` arg) SEGVs. The `_top` REPL path
  requires working `accept`, `_eval`, `_exec`, and SEGV handler.
  BSS section changes (exp 142) likely invalidated the turnkey memory
  layout. `fftk64.asm` is complex. Debug with GDB: compare working
  (main-based) vs crashing (REPL) paths. Currently SKIPPED in
  `exp/Makefile`. **Blocks treeshake.**

- **hang-110-112**: Experiments 110-perl-parity and 112-file-tests
  hang on `ff64s` (static build). Confirmed pre-existing — not caused
  by openlib changes. Root cause unknown; likely related to static
  linking missing something the dynamic build provides. Currently
  SKIPPED in `exp/Makefile`.

- **home-naming-conflict**: Boot `home ( -- @ # )` returns `$HOME`
  directory path. `lib/console.ff` defines `home ( -- )` as VT100
  cursor-home (`0 0 atxy`). Loading console.ff silently overwrites
  boot's `home`. Needs DG decision — options: rename boot's to
  `homedir`/`$HOME`, or rename console.ff's to `cursor-home`/`ch`.

## Test fixes (SKIPPED experiments)
- ~~**fix-079**~~: DONE — changed `loadfile` → `needs`, fixed strerror expectations.
- ~~**fix-080**~~: DONE — changed `"xxx.ff" needed` → `needs xxx.ff`. All 8 tests pass.
- ~~**fix-078**~~: DONE — updated "not found" expectation to "Can't open file".

## Compiler bugs (known, tested in exp/135 and test/loops.ff)
- ~~**fix-rdrop-semicolonthen**~~: FIXED — `rdrop ;THEN` compiles and runs correctly.
- ~~**fix-times-while**~~: FIXED — `TIMES ... WHILE ... REPEAT` works.
- ~~**fix-multi-while**~~: FIXED — Multiple `WHILE` in `BEGIN ... REPEAT` works.
- ~~**fix-repeat-break**~~: FIXED — `BEGIN ... IF BREAK ... REPEAT` works.

## Port work
- ~~**mmap-shared**~~: DONE (exp 145 + 149) — lib/mmap.ff is cross-platform, test/mmap.ff passes on both i386 and ff64. Also fixed shell.ff system stack bug (wait4 missing rusage arg) and !! NUL-termination.
- ~~**fill-bug**~~: FIXED — `fill` works for 100+ bytes.

- **io-extraction**: Extract I/O from ff64.asm into fflin64io.asm,
  create fflin64.asm glue file. Prep for future ARM64/macOS ports.
  The remaining assembly I/O (`_accept`, `_type`, `_emit`, syscall
  wrappers) needs splitting out of ff64.asm. ARM64 would replace
  ff64.asm but keep fflin2.boot; macOS would replace fflin2.boot but
  keep ff64.asm.

- **fflin2-comment-porting**: Port comments from old fflin.boot and
  fflin64.boot into the unified fflin2.boot. When the two files were
  merged (exp 151), their valuable comments were not carried over.
  DG specifically requested this; noted as undone in the exp 151
  checkpoint.

- **needs-extension-change**: Transition `needs foo.ff` → `needs foo`
  across ~50 call sites. The openlib template system (`?.ff` in
  default FFPATH) supports extensionless lookup — `needs pno` tries
  `pno`, then `pno.ff` via the `?.ff` template. Requires updating
  `lib/*.ff`, `test/*.ff`, and boot files. Guard tokens change too
  (`pno` vs `pno.ff`).

## Turnkey / tree-shaking

- **treeshake**: DG's two-pass source-level tree-shaker (JOURNAL.md,
  2026-02-28). Pass 1: replace `compiler` vector (~50 lines, like
  debug.ff's `dbgc`), record dependency edges. Pass 2: separate Forth
  program reads graph, computes transitive closure from `main`,
  filters source, feeds to stock compiler. Dramatically simpler than
  the discarded machine-code walker. 95% coverage acceptable. Lives
  on `exp64-treeshake` branch. **Depends on fix-073** (working
  turnkey).

## Preprocessor (ffpp)

- ~~**ffpp-debug**~~: DONE — `--debug` flag and `[DEBUG]` conditional implemented in ffpp.asm.
- ~~**ffpp-tilde-passthru**~~: DONE — `[~]` enters passthru mode (emits verbatim until matching `[THEN]`, tracking nesting).
- ~~**ffpp-ctrlv**~~: DONE — Ctrl-V (0x16) replaces U+2038 for includes.

- **ffpp-brace-macro**: Add `{64}` macro support with `--64` flag.
  When `--64` is passed, `{64}` in input expands to `64`; otherwise
  it expands to nothing. Use case: `lib/x86-{64}/see.ff` →
  `lib/x86-64/see.ff` (with `--64`) or `lib/x86-/see.ff` (without).
  Manual tests were done during development but no formal test cases
  exist. The `flag_64` variable already exists in ffpp.asm; needs a
  `{` handler. **Possibly superseded** by `[64] [IF]` which achieves
  similar conditional compilation differently.

## Documentation

- **ff-help-turnkey**: ff.help line 1769: `turnkey *TODO* (update boot
  entry too)` — the turnkey help entry exists but is incomplete. Needs
  the actual description written and the boot entry updated.

- **ff-help-libc-underscore**: ff.help line 1867: `libc_ *TODO*
  contrast with libc.` — needs content explaining how `libc_` differs
  from `libc` (the fixup/thunk mechanism for libc function calls).

- **fflinio-inline-dl**: fflinio.asm line 127 (Lavarenne's original
  TODO): `try to inline dl* functions to compile with fasm only`.
  Inline dlopen/dlsym so the binary can build without dynamic linking.
  Low priority — the ffdl build works fine as-is. i386 only.

## Hygiene

- **beautify-forth**: Beautify library files — standardize comment and
  header style per the STYLE file. Boot file beautification (ff2.boot
  + fflin2.boot) was done in commit `2ab6f9c`. What remains:
  `lib/*.ff`, `lib/x86/*.ff`, `lib/x86-64/*.ff`.
- ~~**privatize-cond-dot**~~: DONE — `:. cond.` in both ff.boot and ff64.boot.
- ~~**remove-loop**~~: DONE — removed LOOP from ff64.boot, updated all references.
- ~~**add-stderr-x86**~~: DONE — added stdin/stdout/stderr to ff.boot.
- **exp-tmp-cleanup**: Move experiment temp files from /tmp to local dirs (~20+ Makefiles).
- ~~**segv-missing-word**~~: FIXED — ff64 now shows `<-error: ???` on unknown words, same as i386.
- ~~**needs-segv-loop**~~: NOT A BUG — cascading errors from missing dependencies (e.g., hanoi without console.ff/time.ff). Error recovery works; SEGV is from executing partially-compiled broken code.
- **standardize-tests**: DG asked to standardize on one test pattern (`[[ $$actual = $$expected ]]` exact match in Makefiles).
- ~~**else-workarounds**~~: DONE — audit complete. ELSE used freely in ff64.boot. No workarounds remain.

## Disassembler / debugger

- **dis-backtick-testing**: `dis`` was integrated into see.ff (exp 155)
  but not tested end-to-end on ff64. DG asked "can we combine [dis
  into see.ff] alike to the i386 see" — integration is done but needs
  verification that GDB-based disassembly output works for a real word.

- **dis-move-to-lib**: Move dis.ff to lib/ as cross-platform tool (gdb-based, arch-independent).
- **dis-see-shared-words**: Factor shared header-walking words between dis.ff and see.ff into common utility.

## Side quests
- **register-aliases**: Consider exposing register names for x86-64
  assembly-level Forth programming. The original motivation (compat.ff
  `tos>si`/`di>tos`) is gone — compat.ff was rewritten as pure
  portable Forth. The broader idea of x86-64 register aliases remains
  valid but is aspirational.
- **fpu-x86-64**: Explore FPU/floating point for x86-64 (x87 still works, but SSE2 is modern default).
- **opendir-readdir**: Tier 3 filesystem: opendir/readdir via getdents64 struct parsing, eof. Needs struct helper words first (getdents64 has variable-length entries). `getdents64` syscall wrapper already exists in `lib/x86-64/syscalls.ff`.
- **dns-services**: gethostbyname, getservbyname — file parsing or stub resolver.

## Resolved (not in TODO.md, captured for record)
- ~~**$-broken**~~: NOT A BUG — `$-` works fine on ff64. The JOURNAL report of "corrupted opcodes at `movzx` after `repz cmpsb`" was actually `see` failing to decode valid `movzx` instructions (the `fix-see64-rex` bug). `$-` expects `( @1 @2 # -- n )` — the original SEGV was from passing `"abc"` (which pushes addr+len) without dropping the length.
- ~~**ffpp-debug**~~: DONE — `[DEBUG]`/`--debug` implemented.
- ~~**ffpp-tilde-passthru**~~: DONE — `[~]` passthru mode implemented.
- ~~**ffpp-ctrlv**~~: DONE — Ctrl-V replaces U+2038.
- ~~**exp-063-removal**~~: DONE — exp/063-loadfile removed from exp/Makefile (tests deleted `loadfile` word).
