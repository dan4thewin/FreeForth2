# FreeForth2 — Backlog

## Test fixes (SKIPPED experiments)
- **fix-079**: Fix 079-fixup — test uses deleted `loadfile`, change to `needs ior.ff`. Trivial.
- **fix-080**: Fix 080-lib64 — fixup.ff generates i386 thunks at runtime, needs x86-64 opcodes. Blocks all lib/ tests.
- **fix-078**: Fix 078-ffpath — may be fixed now that openlib is ported from i386. Retest.
- **fix-073**: Fix 073-turnkey — REPL segfaults in turnkey binaries. Likely BSS/memory layout. Large.

## Port work
- exp 144+: Continue porting remaining i386 fflin.boot features

## Hygiene
- **privatize-cond-dot**: Make `cond.` private in both ff.boot and ff64.boot (`:` → `:.`). DG confirmed oversight.
- **remove-loop**: Remove LOOP from ff64.boot — not a FreeForth word. Use TIMES...REPEAT instead.
- **add-stderr-x86**: Add `stderr` constant to ff.boot (x86). Already in ff64.boot.
- **exp-tmp-cleanup**: Move experiment temp files from /tmp to local dirs (~20+ Makefiles).

## Side quests
- **dis-move-to-lib**: Move dis.ff to lib/ as cross-platform tool (gdb-based, arch-independent).
- **dis-see-shared-words**: Factor shared header-walking words between dis.ff and see.ff into common utility.
- **register-aliases**: Consider exposing register names like compat.ff `tos>si` for x86-64.
- **fpu-x86-64**: Explore FPU/floating point for x86-64 (x87 still works, but SSE2 is modern default).
