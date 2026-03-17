# FreeForth2 — Backlog

Last verified: 151 PASSED, 1 SKIPPED (`make testall`).

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

- ~~**mmap-wrapper-fail**~~: FIXED — test64 was using `ff64-` wrapper
  unnecessarily. Wrapper is for exp Makefiles (bash-authored Forth),
  not root test targets that pass pre-written .ff files.

- ~~**hang-110-112**~~: FIXED — exp/110's `syscalls.ff` collided with
  `lib/x86-64/syscalls.ff` via `-f` path search. Fixed Makefile to use
  `cd ../.. && ./ff64 -f $(DIR)/syscalls.ff`. exp/112 was never broken.
  Both un-skipped.

- ~~**home-naming-conflict**~~: DONE — renamed boot's `home` to
  `homedir` in ff2lin.boot and openlib.ff. console.ff keeps `home`.

- **compat-jmp-alias**: `compat.ff` line 68 (`jmp` ' alias exit``)
  fails with `jmp` ???` on ff64. The word `jmp`` exists in the
  dictionary (help finds it) but `needed` fails to parse it during
  file load. Causes exp/078 "lib fallback" test to fail when
  converted from pipe to file-based invocation.

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
- ~~**mmap-shared**~~: DONE (exp 145 + 149) — lib/mmap.ff is
  cross-platform, test/mmap.ff passes on both i386 and ff64. Also
  fixed shell.ff system stack bug (wait4 missing rusage arg) and !!
  NUL-termination.
- ~~**fill-bug**~~: FIXED — `fill` works for 100+ bytes.

- **shared-s-dotted**: Make `s01.`/`s08.`/`s09.` (= `,1 s01` etc.)
  shared across both arches. Currently defined separately in `[64]`
  and `[ELSE]` blocks. Blocked by `,1` being an assembly primitive
  on x86-64 but boot-defined (line 91 of `[ELSE]`) on i386 — a
  single shared definition before the first bifurcation can't work.
  Once resolved, shared macros (`w@`, `c@`, `over*`, etc.) can use
  `ext ... s09.` instead of `ext ... ,1 s09`.

- ~~**io-extraction**~~: MOSTLY DONE (tier 3) — I/O words moved from
  fflinio.asm to shared Forth.  fflinio.asm down to ~100 lines:
  accept, syscall, sigrestorer, dlopen.  ff64.asm _accept removed.
  Remaining: syscall/sigrestorer/dlopen are genuinely asm-mandatory.
  ARM64/macOS split would still need an fflin-style glue file for
  the remaining asm, but the Forth-side OS interface (ff2lin.boot)
  is already clean.

- **fflin2-comment-porting**: Port comments from old fflin.boot and
  fflin64.boot into the unified ff2lin.boot. When the two files were
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
- ~~**ffpp-tilde-passthru**~~: DONE — `[~]` enters passthru mode
  (emits verbatim until matching `[THEN]`, tracking nesting).
- ~~**ffpp-ctrlv**~~: DONE — Ctrl-V (0x16) replaces U+2038 for includes.

- ~~**ffpp-brace-macro**~~: DROPPED — `{64}` macro was implemented
  but superseded by `[64] [IF]` conditional compilation.

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

- ~~**beautify-forth**~~: DONE -- boot files restyled (commit
  `2ab6f9c`), lib em-dashes/arrows removed, `style-check` tool
  added. Remaining: `x86-64/fixup.ff` and `x86-64/mkimage.ff`
  tracked in `align-x86-64-with-x86` todo.
- ~~**privatize-cond-dot**~~: DONE — `:. cond.` in both ff.boot and ff64.boot.
- ~~**remove-loop**~~: DONE — removed LOOP from ff64.boot, updated all references.
- ~~**add-stderr-x86**~~: DONE — added stdin/stdout/stderr to ff.boot.
- **exp-tmp-cleanup**: Move experiment temp files from /tmp to local dirs (~20+ Makefiles).
- ~~**segv-missing-word**~~: FIXED — ff64 now shows `<-error: ???` on unknown words, same as i386.
- ~~**needs-segv-loop**~~: NOT A BUG — cascading errors from missing
  dependencies (e.g., hanoi without console.ff/time.ff). Error
  recovery works; SEGV is from executing partially-compiled broken
  code.
- **standardize-tests**: DG asked to standardize on one test pattern
  (`[[ $$actual = $$expected ]]` exact match in Makefiles).
- ~~**else-workarounds**~~: DONE — audit complete. ELSE used freely
  in ff64.boot. No workarounds remain.

## Disassembler / debugger

- **dis-backtick-testing**: `dis`` was integrated into see.ff (exp 155)
  but not tested end-to-end on ff64. DG asked "can we combine [dis
  into see.ff] alike to the i386 see" — integration is done but needs
  verification that GDB-based disassembly output works for a real word.

- ~~**dis-move-to-lib**~~: DONE — dis.ff promoted to lib/, sym
  auto-loading added, lazy loader in ff2lin.boot.
- **dis-see-shared-words**: Factor shared header-walking words
  between dis.ff and see.ff into common utility.
- **fas2gdb-shakedown**: Thorough shakedown of `fas2gdb` (FASM symbol
  → GDB script converter). Test edge cases, then post on the
  flatassembler board for community feedback.

## Side quests
- **native-malloc**: Pure Forth malloc/free based on FreeRTOS heap_4.c
  algorithm. First-fit with address-sorted coalescing, 2-cell block
  headers, MSB-stolen allocated bit. ~50 lines of Forth. Eliminates
  the last fixup.ff/libc dependency. Detailed feasibility study in
  JOURNAL.md (lines ~11766–11999).
- **register-aliases**: Consider exposing register names for x86-64
  assembly-level Forth programming. The original motivation (compat.ff
  `tos>si`/`di>tos`) is gone — compat.ff was rewritten as pure
  portable Forth. The broader idea of x86-64 register aliases remains
  valid but is aspirational.
- **fpu-x86-64**: Explore FPU/floating point for x86-64 (x87 still
  works, but SSE2 is modern default).
- **opendir-readdir**: Tier 3 filesystem: opendir/readdir via
  getdents64 struct parsing, eof. Needs struct helper words first
  (getdents64 has variable-length entries). `getdents64` syscall
  wrapper already exists in `lib/x86-64/syscalls.ff`.
- **dns-services**: gethostbyname, getservbyname — file parsing or stub resolver.

## Resolved (not in TODO.md, captured for record)
- ~~**$-broken**~~: NOT A BUG — `$-` works fine on ff64. The JOURNAL
  report of "corrupted opcodes at `movzx` after `repz cmpsb`" was
  actually `see` failing to decode valid `movzx` instructions (the
  `fix-see64-rex` bug). `$-` expects `( @1 @2 # -- n )` — the
  original SEGV was from passing `"abc"` (which pushes addr+len)
  without dropping the length.
- ~~**ffpp-debug**~~: DONE — `[DEBUG]`/`--debug` implemented.
- ~~**ffpp-tilde-passthru**~~: DONE — `[~]` passthru mode implemented.
- ~~**ffpp-ctrlv**~~: DONE — Ctrl-V replaces U+2038.
- ~~**exp-063-removal**~~: DONE — exp/063-loadfile removed from
  exp/Makefile (tests deleted `loadfile` word).
