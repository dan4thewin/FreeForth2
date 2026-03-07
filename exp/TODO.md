# FreeForth2 — Backlog

## Test fixes (SKIPPED experiments)
- ~~**fix-079**~~: DONE — changed `loadfile` → `needs`, fixed strerror expectations.
- ~~**fix-080**~~: DONE — changed `"xxx.ff" needed` → `needs xxx.ff`. All 8 tests pass.
- ~~**fix-078**~~: DONE — updated "not found" expectation to "Can't open file".
- **fix-073**: Fix 073-turnkey — REPL segfaults in turnkey binaries. Likely BSS/memory layout. Large.

## Compiler bugs (known, tested in exp/135 and test/loops.ff)
- ~~**fix-rdrop-semicolonthen**~~: FIXED — `rdrop ;THEN` compiles and runs correctly.
- ~~**fix-times-while**~~: FIXED — `TIMES ... WHILE ... REPEAT` works.
- ~~**fix-multi-while**~~: FIXED — Multiple `WHILE` in `BEGIN ... REPEAT` works.
- ~~**fix-repeat-break**~~: FIXED — `BEGIN ... IF BREAK ... REPEAT` works.

## Port work
- ~~**mmap-shared**~~: DONE (exp 145 + 149) — lib/mmap.ff is cross-platform, test/mmap.ff passes on both i386 and ff64. Also fixed shell.ff system stack bug (wait4 missing rusage arg) and !! NUL-termination.
- ~~**fill-bug**~~: FIXED — `fill` works for 100+ bytes.
- **io-extraction**: Extract I/O from ff64.asm into fflin64io.asm, create fflin64.asm glue file. Prep for future ARM64/macOS ports.

## Turnkey / tree-shaking
- **treeshake**: DG's two-pass source-level tree-shaker (JOURNAL.md, 2026-02-28). Pass 1: replace `compiler` vector (~50 lines, like debug.ff's `dbgc`), record dependency edges. Pass 2: separate Forth program reads graph, computes transitive closure from `main`, filters source, feeds to stock compiler. Dramatically simpler than the discarded machine-code walker.

## Hygiene
- **beautify-forth**: Beautify new Forth files — standardize comment and header style, tab-based alignment.
- ~~**privatize-cond-dot**~~: DONE — `:. cond.` in both ff.boot and ff64.boot.
- ~~**remove-loop**~~: DONE — removed LOOP from ff64.boot, updated all references.
- ~~**add-stderr-x86**~~: DONE — added stdin/stdout/stderr to ff.boot.
- **exp-tmp-cleanup**: Move experiment temp files from /tmp to local dirs (~20+ Makefiles).
- ~~**segv-missing-word**~~: FIXED — ff64 now shows `<-error: ???` on unknown words, same as i386.
- ~~**needs-segv-loop**~~: NOT A BUG — cascading errors from missing dependencies (e.g., hanoi without console.ff/time.ff). Error recovery works; SEGV is from executing partially-compiled broken code.
- **standardize-tests**: DG asked to standardize on one test pattern (`[[ $$actual = $$expected ]]` exact match in Makefiles).
- ~~**else-workarounds**~~: DONE — audit complete. ELSE used freely in ff64.boot. No workarounds remain.

## Side quests
- **dis-move-to-lib**: Move dis.ff to lib/ as cross-platform tool (gdb-based, arch-independent).
- **dis-see-shared-words**: Factor shared header-walking words between dis.ff and see.ff into common utility.
- **register-aliases**: Consider exposing register names like compat.ff `tos>si` for x86-64.
- **fpu-x86-64**: Explore FPU/floating point for x86-64 (x87 still works, but SSE2 is modern default).
- **opendir-readdir**: Tier 3 filesystem: opendir/readdir via getdents64 struct parsing, eof.
- **dns-services**: gethostbyname, getservbyname — file parsing or stub resolver.
