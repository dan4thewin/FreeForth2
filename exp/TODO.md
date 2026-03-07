# FreeForth2 — Backlog

## Test fixes (SKIPPED experiments)
- **fix-079**: Fix 079-fixup — test uses deleted `loadfile`, change to `needs ior.ff`. Trivial.
- **fix-080**: Fix 080-lib64 — fixup.ff generates i386 thunks at runtime, needs x86-64 opcodes. Blocks all lib/ tests.
- **fix-078**: Fix 078-ffpath — may be fixed now that openlib is ported from i386. Retest.
- **fix-073**: Fix 073-turnkey — REPL segfaults in turnkey binaries. Likely BSS/memory layout. Large.

## Compiler bugs (known, tested in exp/135 and test/loops.ff)
- ~~**fix-rdrop-semicolonthen**~~: FIXED — `rdrop ;THEN` compiles and runs correctly.
- ~~**fix-times-while**~~: FIXED — `TIMES ... WHILE ... REPEAT` works.
- ~~**fix-multi-while**~~: FIXED — Multiple `WHILE` in `BEGIN ... REPEAT` works.
- ~~**fix-repeat-break**~~: FIXED — `BEGIN ... IF BREAK ... REPEAT` works.

## Port work
- exp 144+: Continue porting remaining i386 fflin.boot features.
- **mmap-shared**: Move mmap.ff from lib/x86 to lib/ as cross-platform. Replace hardcoded syscall numbers with boot words (mmap/munmap) and constants (_sys.ftruncate). Replace 4-byte struct offsets with cell-relative. Add _sys.ftruncate to syscalls.ff. stat word needed on x86-64.
- ~~**fill-bug**~~: FIXED — `fill` works for 100+ bytes.
- **io-extraction**: Extract I/O from ff64.asm into fflin64io.asm, create fflin64.asm glue file. Prep for future ARM64/macOS ports.

## Turnkey / tree-shaking
- **treeshake**: DG's two-pass source-level tree-shaker (JOURNAL.md, 2026-02-28). Pass 1: replace `compiler` vector (~50 lines, like debug.ff's `dbgc`), record dependency edges. Pass 2: separate Forth program reads graph, computes transitive closure from `main`, filters source, feeds to stock compiler. Dramatically simpler than the discarded machine-code walker.

## Hygiene
- **beautify-forth**: Beautify new Forth files — standardize comment and header style, tab-based alignment.
- **privatize-cond-dot**: Make `cond.` private in both ff.boot and ff64.boot (`:` → `:.`). DG confirmed oversight.
- **remove-loop**: Remove LOOP from ff64.boot — not a FreeForth word. Use TIMES...REPEAT instead.
- **add-stderr-x86**: Add `stderr` constant to ff.boot (x86). Already in ff64.boot.
- **exp-tmp-cleanup**: Move experiment temp files from /tmp to local dirs (~20+ Makefiles).
- ~~**segv-missing-word**~~: FIXED — ff64 now shows `<-error: ???` on unknown words, same as i386.
- **needs-segv-loop**: `needs`/`needed` enters infinite SEGV loop when a dependency file can't be found (e.g., hanoi without console.ff/time.ff preloaded). The needed/openlib chain crashes instead of reporting an error.
- **standardize-tests**: DG asked to standardize on one test pattern (`[[ $$actual = $$expected ]]` exact match in Makefiles).
- **else-workarounds**: Now that `_parse` bug is fixed, audit ff64.boot `IF...;THEN` workarounds — ELSE may work correctly now. Remove workarounds where safe.

## Side quests
- **dis-move-to-lib**: Move dis.ff to lib/ as cross-platform tool (gdb-based, arch-independent).
- **dis-see-shared-words**: Factor shared header-walking words between dis.ff and see.ff into common utility.
- **register-aliases**: Consider exposing register names like compat.ff `tos>si` for x86-64.
- **fpu-x86-64**: Explore FPU/floating point for x86-64 (x87 still works, but SSE2 is modern default).
- **opendir-readdir**: Tier 3 filesystem: opendir/readdir via getdents64 struct parsing, eof.
- **dns-services**: gethostbyname, getservbyname — file parsing or stub resolver.
