# Assembly Parity: i386 ↔ x86-64

Running tracker. Updated after each experiment.

Legend: **asm** = assembly only, **forth** = Forth boot only,
**both** = asm exists but Forth shadows it, **—** = not present.

## Asymmetric words (43)

| Word | i386 | x64 | Target | Tier | Status |
|------|------|-----|--------|------|--------|
| `drop`` | asm | forth | forth/forth | 1 | **done** — Forth def in [ELSE] block |
| `over`` | asm | forth | forth/forth | 1 | **done** — Forth def in [ELSE] block |
| `fill` | ~~asm~~ | forth | forth/forth | 1 | **done** — shared, asm removed from ff.asm |
| `erase` | ~~asm~~ | forth | forth/forth | 1 | **done** — shared, asm removed from ff.asm |
| `zlen` | asm | forth | forth/forth | 1 | **done** — moved to shared |
| `>C0` | asm | forth | forth/forth | 1 | no-op — already bifurcated |
| `>C1` | asm | forth | forth/forth | 1 | no-op — already bifurcated |
| `nip`` | asm | forth | forth/forth | 1 | **done** — Forth in [ELSE], shared s01. |
| `under`` | asm | forth | forth/forth | 1 | **done** — Forth in [ELSE], shared s01. |
| `move` | asm | forth→**forth** | forth/forth | 2 | **done** — Forth with std/place/cld, removed cmove> |
| `cmove>` | — | ~~asm~~ | removed | 2 | **done** — replaced by move's backward path |
| `read` | ~~asm~~ | forth | forth/forth | 3 | **done** — in syscalls.ff (both arches) |
| `write` | ~~asm~~ | forth | forth/forth | 3 | **done** — shared in ff2.boot |
| `close` | ~~asm~~ | forth | forth/forth | 3 | **done** — in syscalls.ff (both arches) |
| `openr` | ~~asm~~ | forth | forth/forth | 3 | **done** — in syscalls.ff (both arches) |
| `openw` | ~~asm~~ | forth | forth/forth | 3 | **done** — in syscalls.ff (both arches) |
| `openw0` | ~~asm~~ | forth | forth/forth | 3 | **done** — in syscalls.ff (both arches) |
| `type` | ~~asm~~ | forth | forth/forth | 3 | **done** — shared in ff2.boot |
| `exit` | ~~asm~~ forth | ~~asm~~ forth | forth/forth | 3 | **done** — shared via syscalls.ff (both arches) |
| `accept` | ~~asm~~ | ~~asm~~ | forth/forth | 3 | **done** — shared `:^ accept 0 read 0 max ;` |
| `search` | asm→forth | forth | forth/forth | 4 | ✓ done — pure Forth with >>r locals, $- comparison |
| `$-.` | asm | — | forth/forth | 5 | pending — same as ff |
| `,1` | forth | asm→**forth** | forth/forth | 2 | **done** — self-bootstrap chain |
| `,2` | forth | asm→**forth** | forth/forth | 2 | **done** — uses ,4 |
| `,3` | forth | asm→**forth** | forth/forth | 2 | **done** — uses ,4 |
| `,4` | forth | asm→**forth** | forth/forth | 2 | **done** — self-bootstrap |
| `tailrec` | asm | — | asm/asm | 7 | **done** — added to ff64.asm + WORD64 |
| `which` | asm | — → **asm** | asm/asm | 7 | **done** — variable + WORD64 + _find saves hfa |
| `xfp` | ~~—~~ → **asm** | asm | asm/asm | 7 | **done** — WORD header on i386 |
| `?#` | forth | ~~asm~~ forth | forth/forth | 7 | **done** — shared `variable ?#` in ff2.boot, removed asm cond_jmp+WORD64 |
| `notfound` | asm | — | asm/asm | 7 | **deferred** — x64 inlines char/string/number |
| `number` | asm | — → **asm** | asm/asm | 7 | **done** — WORD64 exposing _number |
| `litcomp` | asm | — | asm/asm | 7 | **deferred** — x64 inlines suffix dispatch |
| `number.` | asm | — | TBD | 7 | **deferred** — structural diff |
| `classes` | asm | — | TBD | 7 | **deferred** — structural diff |
| `>SC` | asm | — | TBD | 7 | **deferred** — structural diff |
| `>S1` | asm | — | TBD | 7 | **deferred** — structural diff |
| `c04` | asm | — | skip | 7 | accepted — i386-only encoding |
| `rst` | asm | — → **asm** | asm/asm | 7 | **done** — WORD64 alias for _rst (>S0) |
| `;;`` | asm | forth→**asm** | asm/asm | 8 | **done** — _semisemi in ff64.asm, Forth def removed |
| `>cs` | — | asm | x64-only | 8 | accepted — i386 differs |
| `cs>` | — | asm | x64-only | 8 | accepted — i386 differs |

## Deferred: asm→Forth compiler words

The original plan had a tier 4 calling for these core compiler words
to become Forth. DG deferred this — they stay assembly-only on both
arches. Revisit if self-hosting ever seems worthwhile.

| Word | i386 | x64 | Status |
|------|------|-----|--------|
| `:`  | asm  | asm | **deferred** — stay asm |
| `;`  | asm  | asm | **deferred** — stay asm |
| `anon` | asm | asm | **deferred** — stay asm |
| `anon:` | asm | asm | **deferred** — stay asm |
| `;;` | asm | asm | **done** — was Forth on x64, moved to asm for parity |

## Symmetric words (already in parity)

| Word | i386 | x64 | Notes |
|------|------|-----|-------|
| `libc` | forth | forth | variable — shared |
| `stdin` | forth | forth | constant — shared |
| `stdout` | forth | forth | constant — shared |

The remaining dictionary words that appear in assembly on both
arches (dup, swap, nip, under, ;, :, find, eval, etc.) are
symmetric — no action needed. Most stack ops, arithmetic, flow
control, and defining words are Forth backtick macros in ff2.boot,
not assembly.

## Changelog

- **Tier 1 (exp 154)**: Moved `fill`/`erase`/`zlen` from [64] block
  to shared section. Added Forth `drop``/`over`` to [ELSE] block
  (i386 now has Forth defs that shadow assembly). `>C0`/`>C1`/`nip``/
  `under`` were already bifurcated -- no changes needed. 131 tests pass.
- **Tier 2**: Added `,4`` self-bootstrap in [64] block using
  litcomma + comma-string (same trick as i386 `,3``). Then `,3``/`,2``
  use `,4`, `,1`` uses `,3`. All four generate identical code to asm.
- **Restructure**: ff2.boot now has 3 sections: primitives (bifurcated
  `,N``/`under``/`nip``/`ext`), shared compositions (`over``/`drop``/
  `dup``/`nipdup``/`tuck``/`s01.`/`s08.`/`s09.`), arch-specific macros.
  i386 `under``=`>C1 $52, s1`, `nip``=`>C1 $5A, s1` (Forth backtick
  macros shadowing assembly). `s01.`/`s08.`/`s09.` now shared.
- **;;` + tailrec**: DG reversed ;;` target: keep in assembly on both
  arches (not Forth). Added `_semisemi` to ff64.asm with tailrec check,
  short-jump optimization, `_semi` calls `_semisemi` (matching i386).
  `tailrec` variable exposed via WORD64. Forth `;;`` removed from
  ff2.boot. Tier 4 compiler words (: ; anon anon:) deferred — stay
  asm-only, revisit if self-hosting.
- **move / cmove>**: Rewrote x64 `move` as pure Forth using `std`
  + `place` + `cld` — `place` emits inline `rep movsb`, `std`/`cld`
  bracket it for backward direction. Removed `cmove>` from ff64.asm
  (was a 64-ism). `_remove_hdr` now uses `move`. Updated exp 071 test.
  Also removed asm `fill`/`erase`/`move` from ff.asm — all shared Forth.
- **Tier 7 exposures**: Added `rst` (alias for >S0), `which` (variable
  + _find saves hfa), `number` (WORD64) to ff64.asm. Added `xfp`
  (WORD header) to ff.asm.
- **search**: Pure Forth using >>r locals and $- comparison. DG wrote
  the definition using 4 >>r locals (r0=@hay r1=#hay r2=@ndl r3=#ndl),
  START/ENTER/WHILE/REPEAT loop, BREAK on match. Returns (@ # ; z?)
  via boolean→flags conversion. Removed asm search from ff.asm.
  Added to ff2.boot after zlen (shared, both arches). 131 PASSED.
- **Tier 3 (I/O parity)**: Removed 10 assembly I/O words from
  fflinio.asm (exit, read, write, close, openr, openw, openw0, type,
  stdin, stdout) and 48-line _accept from ff64.asm.  Replacements:
  `write` shared in ff2.boot with `[64] [IF] 1 [ELSE] 4 [THEN]`
  syscall number; `type` = `stdout write drop ;` (after stdout const);
  `exit` in lib/x86/syscalls.ff; `read`/`open*`/`close` in both
  syscalls.ff; `accept` = `:^ accept 0 read 0 max ;` (shared Forth,
  vector for override).  Structural: moved `^Vff2lin.boot` before REPL
  in ff2.boot (unlocks Forth exit/read before bye); turnkey section
  moved from ff2lin.boot to ff2.boot (depends on _top/doargv).
  Rewrote ff.asm `dotstr` to inline `int $80` sys_write (no _type
  dependency). Removed ff.asm dead debugger REPL (46 lines).  Unified
  SEGV handler with `cell*` arithmetic (6 shared lines).  fflinio.asm
  reduced from 160 to ~85 lines (syscall, sigrestorer, dlopen block).
  151 PASSED.
- **Tier 3 (OS extraction)**: Extracted `fflin64io.asm` (223 lines)
  from `ff64.asm` — mirrors i386's `fflinio.asm` separation.  Contains
  `_syscall`, `_segv_restorer`, and full dlopen block (`_dllib`,
  `_dlfun`, `dl_err`, `_dlcall` + static stubs).  Found and removed
  dead `_segv_handler` (17 lines) + `segv_msg` data — the Forth
  `SEGVhndlr` in ff2lin.boot replaces it at boot.  Both `fflin64.asm`
  and `fflin64s.asm` define `macro OSINCLUDE { include "fflin64io.asm" }`.
  ff64.o shrank 88 bytes, ff64s shrank 96 bytes.  151 PASSED.
- **i386 static binary (ffs)**: Added `fflins.asm` (mirrors
  `fflin64s.asm`).  Restructured `fflinio.asm`: moved `_dlcall`
  inside `ffdl` guard, added static stubs for `#lib`/`#fun`/`#call`
  (return 0).  Added `BSSSECTION` macro to `fflin.asm`/`fflins.asm`
  (`section '.bss'` vs no-op) — FASM's 32-bit `format elf executable`
  doesn't support `section` directives.  ffs: 20,091 bytes, 14/15
  tests pass (only malloc needs libc).
- **shell.ff promoted to native syscalls**: Removed `[64] [IF]` gate
  — `fork`/`execve`/`wait4` are in both arches' `syscalls.ff`.
  `_sh_argv` uses `cell*` for portable pointer offsets.  Removed dead
  libc `getpid`/`getppid` block.  This is what unlocked ffs passing
  fileio, shell, mmap, and system tests.
