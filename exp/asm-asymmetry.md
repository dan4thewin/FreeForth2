# Assembly Word Asymmetry: i386 vs x86-64

Words provided by assembly on one arch but not the other.
Verified against ffpp-generated ff.boot and ff64.boot.

## Forth-for-both: Yes (23 words)

| Word | i386 | x64 | Notes |
|------|------|-----|-------|
| `;;`` | asm | forth | i386 asm could be replaced by Forth |
| `close` | asm | forth | thin syscall wrapper |
| `cmove>` | none | asm | write Forth def for i386 |
| `drop`` | asm | forth | `swap` nip`` composes from primitives |
| `erase` | asm | forth | `0 fill` |
| `fill` | asm | forth | pure Forth loop |
| `move` | asm | forth | cmove>/cmove dispatch |
| `openr` | asm | forth | thin syscall wrapper |
| `openw` | asm | forth | thin syscall wrapper |
| `openw0` | asm | forth | thin syscall wrapper |
| `over`` | asm | forth | `under` swap`` |
| `read` | asm | forth | thin syscall wrapper |
| `type` | asm | forth | `1 write drop` |
| `write` | asm | forth | thin syscall wrapper |
| `zlen` | asm | forth | pure Forth loop |
| `>C0` | asm | forth | no-op on x64, real on i386 |
| `>C1` | asm | forth | no-op on x64, real on i386 |
| `nip`` | asm | forth | bifurcated litcomma in [64]/[ELSE] |
| `under`` | asm | forth | bifurcated litcomma in [64]/[ELSE] |
| `,1` | forth | asm | already Forth on i386, bifurcate for x64 |
| `,2` | forth | asm | already Forth on i386, bifurcate for x64 |
| `,3` | forth | asm | already Forth on i386, bifurcate for x64 |
| `,4` | forth | asm | already Forth on i386, bifurcate for x64 |

## Already shared (3 words)

| Word | i386 | x64 | Notes |
|------|------|-----|-------|
| `libc` | forth | forth | variable |
| `stdin` | forth | forth | constant |
| `stdout` | forth | forth | constant |

## Possible (2 words)

| Word | i386 | x64 | Notes |
|------|------|-----|-------|
| `$-.` | asm | none | case-insensitive $-, could write for both |
| `search` | asm | none | byte-search, could write in Forth |

## Unclear — compiler internals (15 words)

| Word | i386 | x64 | Notes |
|------|------|-----|-------|
| `>S1` | asm | none | i386 SWAPbit helper |
| `>SC` | asm | none | i386 SC-byte writer |
| `>cs` | none | asm | x64 cstack push, i386 different mechanism |
| `?#` | forth | asm | variable on i386, constant on x64 |
| `c04` | asm | none | i386 ModR/M fixup |
| `classes` | asm | none | char-class table for number parser |
| `cs>` | none | asm | x64 cstack pop, i386 different mechanism |
| `litcomp` | asm | none | i386 exposes, x64 inlines |
| `notfound` | asm | none | i386 vector, x64 inlines |
| `number` | asm | none | i386 vector, x64 inlines |
| `number.` | asm | none | i386 number-with-dot parser |
| `rst` | asm | none | i386 SWAPbit reset, x64 uses >S0 |
| `tailrec` | asm | none | tail-recursion variable |
| `which` | asm | none | compiler state variable |
| `xfp` | asm* | asm | exists in both asm, only x64 exposes to dict |
