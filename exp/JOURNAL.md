# FreeForth2 x86-64 Port — Experiment Journal

## Prologue

FreeForth was created by Christophe Lavarenne (1956–2011), a Forth
programmer who spent decades refining interactive, minimal development
environments. FreeForth2 carries his work forward on Linux x86-32.

This journal documents the incremental journey of porting FreeForth2
to x86-64. Rather than attempt a monolithic rewrite of ~1700 lines of
hand-crafted i386 assembly and Forth boot code, we proceed through a
series of small, self-contained experiments. Each experiment produces a
working binary that demonstrates one architectural concept needed for
the 64-bit port.

### Design decisions (established in planning)

- **Separate files** from the 32-bit version (no conditional assembly)
- **rbx = TOS, rdx = NOS** (same register encoding as i386 ebx/edx)
- **r15 = data stack pointer** (replaces the i386 `xchg eax,esp` trick)
- **rsp = call/return stack** (standard usage)
- **rbp = compilation pointer** ("here", same role as i386)
- **8-byte cells** (native 64-bit)
- **`syscall` instruction** with x86-64 Linux syscall numbers

### The i386 ↔ x86-64 translation at a glance

| i386 | x86-64 | Notes |
|------|--------|-------|
| `int $80` | `syscall` | Different instruction, different ABI |
| eax=syscall# | rax=syscall# | Same concept, different numbers |
| ebx,ecx,edx,esi,edi,ebp args | rdi,rsi,rdx,r10,r8,r9 args | Completely different arg registers |
| `xchg eax,esp` (1 byte: $94) | r15 dedicated DSP | Design change; avoids 2-byte xchg |
| `mov ebx,edx` (2 bytes: $89D3) | `mov rbx,rdx` (3 bytes: $48 89 D3) | REX prefix needed |
| `push edx` ($52) | `push rdx` ($52) | Same encoding (push/pop default to 64-bit) |
| `dd` (4-byte data) | `dq` (8-byte data) | Cell size doubles |
| `format elf` | `format elf64` | ELF format |
| `ld -m elf_i386` | `ld -m elf_x86_64` | Linker |

---

## Experiment 001: Hello World — proving fasm x86-64 works

**Goal**: Produce a minimal x86-64 Linux binary using fasm that prints
"Hello, 64-bit FreeForth2!" and exits. This validates our toolchain and
confirms the basic syscall convention.

**Key concepts proven**:
- fasm can produce x86-64 ELF objects
- `syscall` instruction works with correct register mapping
- Linking with `ld -m elf_x86_64` produces a working binary

**Reasoning**: Before touching any FreeForth concepts, we need to know
our assembler and linker can produce a 64-bit binary. This is the
foundation everything else builds on.

**Result**: ✅ Pass. fasm 1.73.32 produces x86-64 ELF objects. `syscall`
with rax=1(write)/60(exit), rdi/rsi/rdx args works correctly.
Binary size: 688 bytes.

---

## Experiment 002: Data Stack with r15

**Goal**: Implement DUP, DROP, SWAP using r15 as a dedicated data stack
pointer with rbx=TOS, rdx=NOS. Verify push/pop/swap operations produce
correct results.

**Key concepts proven**:
- r15 as data stack pointer works (grows downward, sub/add to push/pop)
- DUP1: `sub r15,8; mov [r15],rdx; mov rdx,rbx; mov rbx,<arg>`
- DROP1: `mov rbx,rdx; mov rdx,[r15]; add r15,8`
- SWAP: `xchg rbx,rdx` (runtime version; compile-time version in exp 005)

**Reasoning**: The i386 FreeForth uses a clever `xchg eax,esp` (1 byte)
to swap between call and data stack pointers. On x86-64 this costs 2
bytes ($48 $94) and is conceptually confusing. A dedicated r15 register
is cleaner and provides the same functionality.

**Result**: ✅ Pass. Three test sequences all produce correct output
(30 20 10 / 20 30 10 / 30 20 10).

---

## Experiment 003: Runtime Code Generation

**Goal**: Generate x86-64 machine code into a writeable+executable buffer
at runtime using rbp as the compilation pointer ("here"), then call the
generated code.

**Key concepts proven**:
- rbp works as compilation pointer (same role as i386 FreeForth)
- Generated code can manipulate r15/rbx/rdx data stack
- Writeable+executable memory allows runtime compilation

**Reasoning**: FreeForth is fundamentally a compiler — it reads Forth
words and generates native machine code on the fly. We must prove this
works on x86-64 before building the full compiler loop.

**Result**: ✅ Pass. Generated "DUP1 42; RET" at runtime, called it,
TOS correctly set to 42.

---

## Experiment 004: Subroutine Threading (CALL rel32)

**Goal**: Generate `call rel32` instructions (E8 + 32-bit relative offset)
at runtime to link generated code to pre-written subroutines. This is
FreeForth's POSTPN macro — the heart of subroutine-threaded code.

**Key concepts proven**:
- `call rel32` (opcode E8) is identical on i386 and x86-64 ✓
- POSTPN macro: emit $E8, advance 5, store target, subtract rbp to make relative
- Multiple CALL instructions chain correctly

**Reasoning**: FreeForth compiles each non-macro Forth word as a CALL to
its runtime entry point. The POSTPN macro generates these calls. Because
x86-64 still uses 32-bit relative offsets for CALL, this mechanism works
unchanged — a critical simplification.

**Result**: ✅ Pass. Generated "call _add; call _dot; ret", executed it
with stack [17, 25], correctly printed 42.

---

## Experiment 005: Compile-Time Register Renaming (SWAPbit)

**Goal**: Prove FreeForth's most distinctive optimization works on x86-64:
SWAP emits zero instructions. Instead, a SWAPbit flag causes code generators
(s01, s08, s09) to XOR register-encoding bits in the ModR/M byte, swapping
rbx↔rdx at compile time.

**Key concepts proven**:
- rbx(reg 3) and rdx(reg 2) differ by 1 bit in encoding — identical to i386
- XOR $01 on ModR/M swaps r/m field (destination register)
- XOR $08 swaps reg field (source register)  
- XOR $09 swaps both
- s01/s08/s09 advance rbp by 2 (matching FreeForth's behavior)
- rst: emits `xchg rbx,rdx` ($48 $87 $DA) only when SWAPbit needs clearing

**Reasoning**: This is the heart of FreeForth's code quality — "swap" is
free at compile time, which encourages idiomatic Forth where SWAP selects
"the other register." The ModR/M encoding trick is architecture-neutral
between i386 and x86-64 (same register numbers, just wider).

**Result**: ✅ Pass. Both straight and swap-cancelled sequences produce 30.

---

## Experiment 006: Dictionary Headers and FIND

**Goal**: Implement FreeForth's header structure with 8-byte xt fields and
word lookup via linear search.

**Key concepts proven**:
- 64-bit header layout: xt[8] + ct[1] + sz[1] + name[N] + NUL[1]
- h.ct=8, h.sz=9, h.nm=10 (shifted from i386's 4, 5, 6)
- GENWORDS macro chains (fasm macro-redefines-itself pattern) work for 64-bit
- _find traverses headers, compares names, returns xt on match
- Headers grow forward in assembly but represent a backward-growing dictionary

**Reasoning**: The dictionary is FreeForth's symbol table. Every word
lookup during compilation goes through _find. The 8-byte xt field is the
single biggest structural change from i386 — it shifts all header offsets.

**Result**: ✅ Pass. Found "drop" with xt=222, correctly failed on "bogus".

---

## Experiment 007: Minimal Compiler Loop

**Goal**: Build a minimal but functional compiler that reads whitespace-
delimited words from an input buffer, looks them up in a dictionary of
primitives, compiles calls to their runtime code, and executes the result
when ";" is encountered. This is the core of FreeForth's main loop.

**Target**: Compile and execute `3 4 + . cr ;` → should print `7`.

**Architecture**: The compiler loop itself uses only rax/rcx (general-purpose
scratch registers) and never touches the Forth data stack (rbx/rdx/r15).
Generated code uses the data stack. This separation is critical — the i386
original's compiler loop uses ebx/edx for both, but that works only because
the `xchg eax,esp` trick provides a clean way to switch contexts. On x86-64,
with r15 as a dedicated data stack pointer, mixing compiler and generated
code would corrupt the stack.

**Built-in words**: `+ - * dup drop swap over . cr`

**Key debugging episode**: `_find` worked perfectly on manually-constructed
headers but failed on GENWORDS64 macro-generated headers — even though a byte
dump confirmed identical memory layouts. The bug turned out to be trivial but
subtle: `repz cmpsb` decrements rcx as it compares bytes, so after a failed
name comparison, rcx no longer held the entry's name length. The `.skip`
instruction `lea rsi, [rsi + rcx + 1]` then advanced by the wrong amount,
landing in the middle of the next header instead of at its start. The fix:
`push rcx` / `pop rcx` around `repz cmpsb`, exactly as in experiment 006.
The bug was introduced when rewriting _find for the rax/rcx register
interface (exp 006 used rbx/rdx and had the push/pop; they were accidentally
omitted in 007).

**Result**: ✅ Pass. Three tests all produce correct output:
```
3 4 + . cr ;   → 7
10 3 - . cr ;  → 7
6 7 * . cr ;   → 42
```

This is a milestone: a complete compile-and-execute cycle on x86-64. The
binary reads source text, parses words, looks them up, compiles machine code
into a buffer, and executes it. The generated code manipulates the Forth data
stack using r15/rbx/rdx just as the eventual ff64 will.

---


## Experiment 008: Interactive REPL

**Goal**: Add stdin reading to the compiler loop, creating an interactive
read-eval-compile loop. Print `> ` prompt and `ok` after each line.

**New capability**: `_readline` function using `sys_read` (syscall 0) from
stdin into a 4096-byte input buffer. The REPL loop: print prompt → read
line → reset compilation pointer → compile/execute → print "ok" → repeat.
On EOF, exit cleanly.

**Bug fix carried forward**: The `_number` function's `r9d` sign flag was
only cleared in the decimal path. When parsing hex numbers (e.g. `$FF`),
the code jumped past `xor r9d, r9d`, leaving r9d with a stale value from
`_find` (which uses r9 to save word length). Fix: move `xor r9d, r9d`
before the `$` check. This bug was retroactively fixed in experiment 007
as well.

**Error handling**: Unknown words print `error: <word>` and continue
processing. This allows recovery within the same session.

**Result**: ✅ Pass.
```
> 3 4 + . cr ;
7
ok
> $FF . cr ;
255
ok
> 5 dup * . cr ;
25
ok
> -42 . cr ;
-42
ok
```

---

## Experiment 009: Named Definitions (Colon Compiler)

**Goal**: Implement `:` (colon) to create named definitions at runtime.
`: square dup * ;` should create a word "square" that can be called later.

**New capabilities**:
- `_header`: Creates dictionary headers at runtime. Headers grow downward
  from the built-in word headers. Takes name addr/len, xt, and ct in
  registers. Allocates space below [H], stores xt (8 bytes), ct (1 byte),
  name length (1 byte), name (N bytes), and NUL terminator.
- `_colon`: Parses the next word as a definition name, creates a header
  with xt = current compilation pointer (rbp), sets `[anon]` to 0.
- Modified `_semi`: Distinguishes named vs anonymous definitions.
  Named (anon=0): compile ret, advance rbp, set anon=rbp (body persists).
  Anonymous (anon≠0): compile ret, execute, recycle space (rbp reset).

**Key insight**: FreeForth creates the header BEFORE compiling the body.
The xt is set to the current rbp, where the body will be compiled. This
allows recursive definitions — the word can find itself in the dictionary.

**Memory layout**: Code grows upward in codebuf. Headers grow downward
from the built-in GENWORDS64 entries. A 64KB headbuf is reserved below
heads64 for runtime headers.

**Result**: ✅ Pass.
```
: square dup * ; 5 square . cr ;       → 25
: cube dup dup * * ; 4 cube . cr ;     → 64
: quad square square ; 3 quad . cr ;   → 81  (definition calling definition)
: double dup + ; 5 double . cr ;       → 10
-3 double . cr ;                       → -6
```

---
