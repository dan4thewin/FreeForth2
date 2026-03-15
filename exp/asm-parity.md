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
| `nip`` | asm | forth | forth/forth | 1 | no-op — already bifurcated |
| `under`` | asm | forth | forth/forth | 1 | no-op — already bifurcated |
| `move` | asm | forth | forth/forth | 2 | pending — backtick macro |
| `cmove>` | — | asm | forth/forth | 2 | pending — write for i386 |
| `read` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `write` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `close` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `openr` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `openw` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `openw0` | asm | forth | forth/forth | 3 | pending — move to fflin2.boot |
| `type` | asm | forth | forth/forth | 3 | pending — shared once write is Forth |
| `search` | asm | — | forth/forth | 4 | pending — preserve repnz/repz algo |
| `$-.` | asm | — | forth/forth | 5 | pending — DG exercise |
| `,1` | forth | asm | forth/forth | 6 | pending — write x64 Forth def |
| `,2` | forth | asm | forth/forth | 6 | pending — write x64 Forth def |
| `,3` | forth | asm | forth/forth | 6 | pending — write x64 Forth def |
| `,4` | forth | asm | forth/forth | 6 | pending — write x64 Forth def |
| `tailrec` | asm | — | asm/asm | 7 | pending — expose on x64 |
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
| `;;`` | asm | forth | forth/forth | 8 | pending — move i386 to Forth |
| `>cs` | — | asm | x64-only | 8 | accepted — i386 differs |
| `cs>` | — | asm | x64-only | 8 | accepted — i386 differs |

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
  `under`` were already bifurcated — no changes needed. 131 tests pass.
