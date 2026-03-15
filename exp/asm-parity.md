# Assembly Parity: i386 ↔ x86-64

Running tracker. Updated after each experiment.

Legend: **asm** = assembly only, **forth** = Forth boot only,
**both** = asm exists but Forth shadows it, **—** = not present.

## Asymmetric words (43)

| Word | i386 | x64 | Target | Tier | Status |
|------|------|-----|--------|------|--------|
| `drop`` | asm | forth | forth/forth | 1 | **done** — Forth def in [ELSE] block |
| `over`` | asm | forth | forth/forth | 1 | **done** — Forth def in [ELSE] block |
| `fill` | asm | forth | forth/forth | 1 | **done** — moved to shared |
| `erase` | asm | forth | forth/forth | 1 | **done** — moved to shared |
| `zlen` | asm | forth | forth/forth | 1 | **done** — moved to shared |
| `>C0` | asm | forth | forth/forth | 1 | no-op — already bifurcated |
| `>C1` | asm | forth | forth/forth | 1 | no-op — already bifurcated |
| `nip`` | asm | forth | forth/forth | 1 | **done** — Forth in [ELSE], shared s01. |
| `under`` | asm | forth | forth/forth | 1 | **done** — Forth in [ELSE], shared s01. |
| `move` | asm | forth→**forth** | forth/forth | 2 | **done** — Forth with std/place/cld, removed cmove> |
| `cmove>` | — | ~~asm~~ | removed | 2 | **done** — replaced by move's backward path |
| `read` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `write` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `close` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `openr` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `openw` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `openw0` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `type` | asm | forth | forth/forth | 3 | pending — shared once write is Forth |
| `search` | asm | — | forth/forth | 4 | pending — preserve repnz/repz algo |
| `$-.` | asm | — | forth/forth | 5 | pending — DG exercise |
| `,1` | forth | asm→**forth** | forth/forth | 2 | **done** — self-bootstrap chain |
| `,2` | forth | asm→**forth** | forth/forth | 2 | **done** — uses ,4 |
| `,3` | forth | asm→**forth** | forth/forth | 2 | **done** — uses ,4 |
| `,4` | forth | asm→**forth** | forth/forth | 2 | **done** — self-bootstrap |
| `tailrec` | asm | — | asm/asm | 7 | **done** — added to ff64.asm + WORD64 |
| `which` | asm | — | asm/asm | 7 | pending — expose on x64 |
| `xfp` | asm* | asm | asm/asm | 7 | pending — expose on i386 |
| `?#` | forth | asm | TBD | 7 | pending — type mismatch |
| `notfound` | asm | — | asm/asm | 7 | pending — x64 vector |
| `number` | asm | — | asm/asm | 7 | pending — x64 vector |
| `litcomp` | asm | — | asm/asm | 7 | pending — x64 label+WORD64 |
| `number.` | asm | — | TBD | 7 | pending — structural diff |
| `classes` | asm | — | TBD | 7 | pending — structural diff |
| `>SC` | asm | — | TBD | 7 | pending — structural diff |
| `>S1` | asm | — | TBD | 7 | pending — structural diff |
| `c04` | asm | — | skip | 7 | accepted — i386-only encoding |
| `rst` | asm | — | TBD | 7 | pending — x64 uses >S0 |
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
