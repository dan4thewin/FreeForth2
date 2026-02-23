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

## Experiment 010: Flow Control (IF/THEN/ELSE, BEGIN/UNTIL/WHILE/REPEAT)

**Goal**: Implement compile-time words that generate conditional and looping
machine code, enabling branching and iteration in defined words.

**New concepts**:
- **Compile-time words (ct=1)**: When `_find` returns a word with ct=1, the
  compiler *executes* it immediately instead of emitting a call. These words
  emit inline machine code (branches, jumps) into the code buffer and use the
  Forth data stack (rbx/rdx/r15) at *compile time* to track forward-reference
  patch addresses.
- **CF-based _find signaling**: Changed from ZF to CF (carry flag) for
  found/not-found. ecx holds the ct value when found. This avoids conflicts
  with ct field testing.
- **Flag-preserving DROP1**: Conditional branch words (IF, UNTIL) compile
  `test rbx,rbx` followed by DROP1 followed by `jz rel32`. The DROP1 must
  not clobber the flags set by `test`. Solution: use `lea r15,[r15+8]`
  instead of `add r15,8` — LEA does not modify flags.

**Compile-time words implemented**:

| Word | Compile-time action |
|------|---------------------|
| IF | Emit `test rbx,rbx; DROP1; jz <forward>`. Push patch address. |
| THEN | Patch the forward jump at the address on the data stack. |
| ELSE | Emit `jmp <forward>`. Patch previous IF. Push new patch address. |
| BEGIN | Push current compilation pointer (loop target) onto data stack. |
| AGAIN | Emit `jmp <backward>` to BEGIN target. |
| UNTIL | Emit `test rbx,rbx; DROP1; jz <backward>` to BEGIN target. |
| WHILE | Same as IF (push patch address for forward jump). |
| REPEAT | Emit `jmp <backward>` to BEGIN, then patch WHILE's forward jump. |

**Runtime comparison words added**: `=`, `<`, `>`, `0=`, `0<>`, `0<`, `negate`, `1`, `2`

**Bugs found and fixed** (a chronicle of x86-64 encoding subtleties):

1. **IF flag clobbering** (subtle): `add r15, 8` in DROP1 clobbers ZF from
   the preceding `test rbx,rbx`. Fix: encode as `lea r15, [r15+8]` which
   preserves all flags. Encoded as `4D 8D 7F 08`.

2. **Comparison flag clobbering**: `add r15, 8` in `_eq`/`_lt`/`_gt`
   clobbered flags before `setX cl` could capture the comparison result.
   Fix: execute `setX cl` immediately after `cmp`, before any flag-modifying
   instructions.

3. **`_number` rdx corruption**: Compile-time words use rdx/r15 (the data
   stack) during compilation to track patch addresses. When the compiler
   encounters a number literal, `_number` was clobbering rdx (used as an
   accumulator). Fix: save/restore rdx around `_number`. Changed success/
   failure signaling to use ZF: `cmp rax,rax` (always sets ZF) for success,
   `test rax,rax` (nonzero clears ZF) for failure.

4. **The REX prefix single-bit bug** (the most insidious): The flag-preserving
   `lea r15, [r15+8]` was encoded as `49 8D 7F 08`. REX prefix `49` has
   REX.W=1, REX.R=0, REX.B=1. The ModR/M byte `7F` has reg=111 (7) and
   r/m=111 (7). With REX.B=1, r/m extends to r15 ✓. But with REX.R=0,
   reg stays as 7 = rdi. So the instruction was actually `lea rdi, [r15+8]`
   — it wrote to rdi instead of r15! The data stack pointer was never
   updated, causing a one-cell offset that corrupted values during recursive
   calls. The fix: change `49` to `4D` (set REX.R=1), making reg=15=r15.
   **One bit, four days of debugging.**

**Result**: ✅ Pass.
```
: abs dup 0< IF negate THEN ; -42 abs . cr ;        → 42
: max over over < IF swap THEN drop ; 3 7 max . cr ; → 7
: fact dup 1 > IF dup 1 - fact * THEN ;
5 fact . cr ;                                        → 120
10 fact . cr ;                                       → 3628800
: recsum dup 1 > IF dup 1 - recsum + THEN ;
3 recsum . cr ;                                      → 6
10 recsum . cr ;                                     → 55
: fib dup 1 > IF dup 1 - fib swap 2 - fib + THEN ;
10 fib . cr ;                                        → 55
: countdown BEGIN dup . cr 1 - dup 0= UNTIL drop ;
3 countdown ;                                        → 3 2 1
```

This experiment proves the x86-64 port can handle arbitrary control flow,
including deep recursion. The REX prefix bug is a cautionary tale about
x86-64 instruction encoding: r15 requires both REX.R (for the reg field)
and REX.B (for the r/m field) to be set in the same instruction. Missing
either one silently targets a different register.

---

## Experiment 011: Memory Access, Arithmetic, and Stack Operations

**Goal**: Extend the x86-64 Forth with memory access (`@`, `!`, `c@`, `c!`,
`+!`), division and modulus (`/`, `mod`, `/mod`), bitwise operations (`and`,
`or`, `xor`, `not`), shift operations (`lshift`, `rshift`), more stack words
(`rot`, `nip`, `tuck`, `depth`), memory compilation (`here`, `allot`, `,`,
`c,`), and comment handling (`(` and `\`).

**New runtime words (26 total)**:

| Category | Words |
|----------|-------|
| Memory | `@ ! c@ c! +!` |
| Arithmetic | `/ mod /mod` |
| Bitwise | `and or xor not` |
| Shifts | `lshift rshift` |
| Stack | `rot nip tuck depth` |
| Memory compilation | `here allot , c,` |
| Literals | `2` |
| Comments (ct=1) | `( \` |

**Division implementation note**: x86-64 `idiv` takes the dividend in `rdx:rax`
and the divisor as an operand. Since `rdx` is our NOS register (the dividend
in Forth's `a b /`), and `cqo` overwrites `rdx` with the sign extension, the
divisor must first be saved to `rcx`. The sequence is:
```
mov rcx, rbx    ; save divisor (TOS)
mov rax, rdx    ; load dividend (NOS)
cqo             ; sign-extend rax → rdx:rax
idiv rcx        ; quotient in rax, remainder in rdx
```

**Bug found and fixed**: `_tuck` had an unnecessary `xchg rbx,rdx` that
swapped TOS/NOS after pushing. Since `tuck ( a b -- b a b )` only needs to
push a copy of TOS below NOS, just `sub r15,8; mov [r15],rbx` suffices —
rbx (b) and rdx (a) are already in the right positions.

**Result**: ✅ Pass. All 26 new words work correctly alongside the existing
set from experiment 010.
```
10 3 / . cr ;                          → 3
10 3 mod . cr ;                        → 1
10 3 /mod . . cr ;                     → 3 1
$FF $0F and . cr ;                     → 15
$F0 $0F or . cr ;                      → 255
1 8 lshift . cr ;                      → 256
256 2 rshift . cr ;                    → 64
1 2 3 rot . . . cr ;                   → 1 3 2
1 2 tuck . . . cr ;                    → 2 1 2
here dup 42 swap ! here @ . cr ;       → 42
here dup $41 swap c! c@ . cr ;         → 65
: fact dup 1 > IF dup 1 - fact * THEN ;
10 fact . cr ;                         → 3628800
( this is a comment ) 3 4 + . cr ;     → 7
```

---

## Experiment 012: Variables, Constants, Strings, and ct Rework

**Goal**: Add `variable`, `constant`, and `."` (dot-quote string printing).
This requires reworking the compile-type (ct) system to support three
distinct behaviors.

**ct field rework**: The original experiments used ct=0 for runtime and
ct=1 for compile-time words. This experiment introduces ct=1 for literal
words (variables, constants) whose xt value should be pushed as an inline
literal during compilation, and moves compile-time words to ct=2:

| ct | Compiler action | Examples |
|----|----------------|----------|
| 0 | Emit `call xt` | `+ - * dup drop .` |
| 1 | Emit literal push of xt value | variables (push addr), constants (push value) |
| ≥2 | Execute xt immediately | `IF THEN ELSE BEGIN ( \` |

**variable implementation**: `variable x` parses the name "x", allocates
an 8-byte cell in the code buffer (initialized to 0), creates a header
with xt = cell address and ct=1. When `x` is subsequently used, the
compiler emits a literal push of the cell's address. `x @` reads, `x !`
writes.

**constant implementation**: `42 constant answer` first executes the
accumulated anonymous code (via `_semi_exec`) to put 42 on the data stack,
then creates a header with xt=42 (the TOS value) and ct=1. When `answer`
is used, 42 is pushed as an inline literal.

**`."` (dot-quote) implementation**: A compile-time word (ct=2) that
scans input until the closing `"` and compiles an inline string print.
The generated code is: `call _dotstr_rt` followed by a length byte and
the string data. At runtime, `_dotstr_rt` pops its return address (which
points to the string), prints it via sys_write, and jumps past the string
data. This is a common Forth technique — strings are embedded directly
in the instruction stream.

**Result**: ✅ Pass.
```
variable x  42 x !  x @ . cr ;               → 42
42 constant answer  answer . cr ;             → 42
variable counter  0 counter !
1 counter +!  1 counter +!  counter @ . cr ;  → 2
: show ." x = " x @ . ." answer = " answer . cr ;
42 x ! show ;                                 → x = 42 answer = 42
99 x ! show ;                                 → x = 99 answer = 42
: fact dup 1 > IF dup 1 - fact * THEN ;
10 fact . cr ;                                → 3628800
```

---

## Experiment 013: File I/O (include)

**Goal**: Add the ability to load and compile Forth source from files,
enabling code to be organized across multiple files.

**New capability**: `include <filename>` — opens a file, reads its contents
into a buffer, compiles it (exactly as if the text were typed at the REPL),
then restores the previous input state.

**Implementation details**:
- Uses x86-64 Linux syscalls: `open` (2), `read` (0), `close` (3)
- Input state (`tin`, `tp`) saved/restored on the call stack
- A `filebuf_ptr` tracks the current position in a 64KB file buffer,
  advancing with each nesting level. This allows nested includes (a file
  that includes another file) without overwriting the parent's buffer.
- Each include level gets up to 16KB of buffer space
- Error handling: missing files print an error and continue

**Nested includes**: When `main.ff` includes `lib.ff`, the buffer layout is:
```
filebuf: [main.ff content...][gap][lib.ff content...]
```
Each level saves/restores `filebuf_ptr` along with `tin`/`tp`.

**Result**: ✅ Pass.
```
> include test.ff
> 5 square . cr ;     → 25   (square defined in test.ff)
> 3 cube . cr ;       → 27   (cube defined in test.ff)
> greet ;             → Hello from file!
> include main.ff     → 42 7 3  (nested: main.ff includes lib.ff)
> include bogus.ff    → error: cannot open file  (graceful error)
> 3 4 + . cr ;        → 7    (continues after error)
```

---

## Experiment 014: Return Stack and String Operations

**Goal**: Add return stack words (`>r`, `r>`, `r@`) and string/memory
operations (`zlen`, `cmove`, `fill`, `erase`, `emit`).

**Return stack implementation**: On x86-64, `rsp` is the call/return stack.
The return stack words must work around the fact that calling `>r` itself
pushes a return address. Solution: pop the return address into `rax`, do the
operation, then `jmp rax` instead of `ret`. This is the standard Forth
technique for return stack manipulation.

**Result**: ✅ Pass. All words work correctly.
```
: swap-r >r >r swap r> r> ; 1 2 3 4 swap-r . . . . cr ;  → 4 3 1 2
$41 emit $42 emit $43 emit cr ;                           → ABC
42 >r r> . cr ;                                           → 42
```

---

## Experiment 015: SWAPbit Infrastructure

**Goal**: Add the SWAPbit infrastructure — the SC (swap counter) variable,
`_rst` (register synchronization), and `_swap_ct` (compile-time swap toggle).

**What was built**:
- `SC` byte variable with bit 1 as the SWAPbit
- `_rst`: checks SWAPbit; if set, emits `xchg rbx,rdx` and clears it
- `_swap_ct`: toggles SWAPbit without emitting code
- `_call_compile` and `_semi` call `_rst` before emitting code

**Why swap remains runtime**: Full SWAPbit integration requires ALL primitives
to use inline code generation with s01/s08/s09 register selection. Currently,
primitives like `_sub` have internal `xchg rbx,rdx` that conflicts with `_rst`'s
xchg — the two cancel out. The original FreeForth solves this by making
primitives compile inline with SWAPbit-aware register encoding, but that's a
fundamental restructuring best done in the final ff64 assembly.

**Status**: Infrastructure in place. `swap` uses runtime `call _swap` (ct=0).
The SWAPbit optimization is deferred to the final assembly phase where
primitives will be rewritten as inline code generators.

**Result**: ✅ Pass (with runtime swap). All existing tests pass.

---

## Final Assembly: ff64.asm and ff64.boot

**Goal**: Assemble the proven experiment code into the production `ff64.asm`
and `ff64.boot` files, integrated into the project Makefile.

**What was done**:
- `ff64.asm`: Assembled from experiment 015 (which accumulated all features
  from experiments 001–015). This is the x86-64 kernel with 60 built-in words.
- `ff64.boot`: Minimal boot source providing standard Forth words (`2dup`,
  `2drop`, `abs`, `max`, `min`, `within`, `>=`, `<=`, `<>`, `?`, `on`, `off`,
  `space`, `spaces`, `?dup`, `2swap`, `TRUE`, `FALSE`).
- `Makefile`: Updated with `ff64` target. `make all` now builds both `ff`
  (32-bit) and `ff64` (64-bit).
- Command-line `-f <file>` support: `./ff64 -f ff64.boot` loads the boot
  file before entering the REPL. Multiple `-f` flags supported.

**Built-in word inventory (60 words)**:

| Category | Words |
|----------|-------|
| Arithmetic | `+ - * / mod /mod negate` |
| Comparison | `= < > 0= 0<> 0<` |
| Stack | `dup drop swap over rot nip tuck depth` |
| Return stack | `>r r> r@` |
| Memory | `@ ! c@ c! +! here allot , c,` |
| Bitwise | `and or xor not lshift rshift` |
| I/O | `. cr emit` |
| Literals | `1 2` |
| String/mem ops | `zlen cmove fill erase` |
| Control flow (ct=2) | `IF THEN ELSE BEGIN AGAIN UNTIL WHILE REPEAT` |
| Comments (ct=2) | `( \` |
| Strings (ct=2) | `."` |

**Architecture summary**:
- rbx=TOS, rdx=NOS, r15=data stack, rsp=call stack, rbp=compilation pointer
- ct=0 → compile call, ct=1 → compile literal, ct≥2 → execute immediately
- 8-byte cells, subroutine-threaded, CALL rel32 linking
- `syscall` instruction with x86-64 Linux ABI
- Interactive REPL with `> ` prompt and `ok` response
- Named definitions with `:` and `;`, variables and constants
- File loading via `include` (with nesting) and `-f` command-line flag
- SWAPbit infrastructure present (SC, _rst) but not yet activated

---

## Epilogue

This journal documents the incremental creation of a 64-bit x86-64 port of
FreeForth2, Christophe Lavarenne's minimal Forth system. Through 15
experiments, each building on the last, the port was assembled piece by piece:
from a bare "Hello World" syscall to a complete interactive Forth compiler
capable of recursive definitions, flow control, variables, constants, string
printing, and file loading.

The most memorable bug was a single bit in a REX prefix (experiment 010):
`49` instead of `4D` caused `lea r15, [r15+8]` to silently target `rdi`
instead of `r15`, corrupting the data stack during recursive calls. One bit,
days of debugging, and a lesson in x86-64 instruction encoding that no
textbook could teach as effectively.

The SWAPbit optimization — FreeForth's most distinctive feature, where `swap`
emits zero instructions by tracking register assignments at compile time —
was proven at the instruction level (experiment 005) but awaits deep
integration into the code generator. This is a natural next step for anyone
continuing Christophe's work.

FreeForth2 lives on.

---

## Phase 2: Deep Integration

Phase 2 moves beyond proving individual concepts to building a production-quality
code generator. Where Phase 1 used runtime `call` instructions for every
primitive, Phase 2 converts them to inline machine code — the technique that
makes FreeForth distinctive.

### Experiment 016: Inline Code Generation

**Goal:** Convert 10 core primitives from runtime calls (ct=0, 5-byte `call`
instructions) to inline code generators (ct=2, emit machine code directly).

**Primitives converted:**

| Word | Runtime bytes | Inline bytes | Savings |
|------|:---:|:---:|:---:|
| `negate` | 5 (call) + 4 (body) | 3 | 6 bytes |
| `not` | 5 + 4 | 3 | 6 bytes |
| `swap` | 5 + 4 | 3 | 6 bytes |
| `nip` | 5 + 8 | 7 | 6 bytes |
| `dup` | 5 + 8 | 10 | 3 bytes |
| `drop` | 5 + 8 | 10 | 3 bytes |
| `over` | 5 + 8 | 10 | 3 bytes |
| `+` | 5 + 8 | 10 | 3 bytes |
| `*` | 5 + 8 | 11 | 2 bytes |
| `-` | 5 + 10 | 13 | 2 bytes |

Each inline code generator is a function that writes machine code bytes
at `rbp` (the compilation pointer). When the compiler sees `+`, it calls
`_add_inline`, which writes these 10 bytes:

```
48 01 D3        add rbx, rdx       ; TOS += NOS
49 8B 17        mov rdx, [r15]     ; new NOS from stack
49 83 C7 08     add r15, 8         ; shrink data stack
```

Compare to the old approach, which compiled `E8 xx xx xx xx` (call _add)
and at runtime executed the same instructions plus `call`/`ret` overhead.

**Subtlety: subtraction order.** The `-` inline emits `sub rdx, rbx`
(NOS minus TOS) rather than `sub rbx, rdx`, because Forth's `-` expects
`( a b -- a-b )` where TOS=b and NOS=a. The result is then moved to rbx
via `mov rbx, rdx`.

**Result:** All 13 tests pass. The generated code is both smaller and faster.
The runtime function bodies are preserved as internal helpers but are no
longer registered in the dictionary.

**Files:** `exp/016-inline64/{inline64.asm,Makefile}`

---

### Experiment 017: Deep SWAPbit Integration

**Goal:** Make `swap` a zero-cost compile-time operation by deeply integrating
the SWAPbit into all inline code generators.

**How it works:**

The SWAPbit is a single flag (bit 1 of SC). When clear, rbx=TOS and rdx=NOS
(the normal assignment). When set, the registers are logically reversed:
rdx=TOS and rbx=NOS.

`swap` simply toggles this flag — it emits **zero bytes** of machine code.
All subsequent inline code generators adjust their register encoding to match.

Three functions implement the register swap:

| Function | XOR mask | What it swaps |
|----------|:--------:|---------------|
| `s01` | `$01` | r/m field only (destination register) |
| `s08` | `$08` | reg field only (source register) |
| `s09` | `$09` | Both fields |

They work because rbx (register 3, binary 011) and rdx (register 2, binary
010) differ by exactly one bit. XORing the appropriate bit in the ModR/M
byte switches between them.

**Example: how `+` adapts to the SWAPbit**

Normal (SWAPbit=0):
```
48 01 D3        add rbx, rdx       ; ModR/M = D3
49 8B 17        mov rdx, [r15]     ; reg field = rdx (2)
49 83 C7 08     add r15, 8
```

After swap (SWAPbit=1):
```
48 01 DA        add rdx, rbx       ; ModR/M = D3 XOR 09 = DA
49 8B 1F        mov rbx, [r15]     ; reg field = rbx (3), 17 XOR 08 = 1F
49 83 C7 08     add r15, 8
```

The generated code is different, but the result is identical: the sum
goes into TOS (whichever register that is), and a new NOS is popped.

**Sync points:** Before `call` and `ret` instructions, `_rst` emits
`xchg rbx,rdx` (3 bytes) if the SWAPbit is set, then clears the flag.
This ensures called functions always see the standard register assignment.
IF and UNTIL also call `_rst` before emitting test/branch code.

**Key test: `3 10 swap - . cr ;` → 7**

Without swap, `3 10 -` = 3-10 = -7. With swap, `-` emits `sub rbx, rdx`
instead of `sub rdx, rbx`, correctly computing 10-3 = 7.

**Result:** All 16 tests pass, including swap+add, swap+sub, swap+dup+mul,
double-swap cancellation, and swap within named definitions. This is the
most significant optimization from the original FreeForth now ported to x86-64.

**Files:** `exp/017-swapbit-deep/{swapdeep64.asm,Makefile}`

---

### Experiment 018: More Inline Primitives

**Goal:** Convert 8 more primitives to SWAPbit-aware inline code generators,
completing the set of common operations.

**Primitives converted:**

| Word | Inline bytes | SWAPbit mask | Pattern |
|------|:---:|:---:|---|
| `and` | 10 | s09 | Same as `+`: binary op + DROP_NOS |
| `or` | 10 | s09 | Same pattern |
| `xor` | 10 | s09 | Same pattern |
| `@` | 3 | s09 | `mov rbx,[rbx]` — address and result both in TOS |
| `c@` | 3 | s09 | `movzx ebx,byte [rbx]` — no REX needed |
| `0<` | 4 | s01 | `sar rbx,63` — split-emit for immediate byte |
| `rot` | 6 | s08 | `xchg NOS,[r15]; xchg rbx,rdx` |
| `tuck` | 7 | s08 | `sub r15,8; mov [r15],TOS` |

**Notable encoding detail: `c@` without REX.** The `movzx ebx, byte [rbx]`
instruction is 3 bytes (0F B6 1B) with no REX prefix. Writing to a 32-bit
register (ebx) on x86-64 automatically zero-extends to 64 bits. This saves
a byte compared to the `48 0F B6 1B` encoding that fasm generates for
`movzx rbx, byte [rbx]`.

**Notable: `0<` split-emit trick.** The `sar rbx, 63` instruction has an
immediate byte ($3F) after the ModR/M byte. The s01 function XORs [rbp-1],
which would target the immediate instead of the ModR/M. Solution: emit the
opcode + ModR/M (3 bytes), call s01, then emit the immediate separately.

**SWAPbit bug fix in ff64.asm:** Added `_rst` to THEN, ELSE, BEGIN, AGAIN,
and REPEAT to sync the SWAPbit at flow control join points. Without this,
`swap` inside IF bodies corrupted register assignments because the
compile-time SWAPbit toggle always runs, but the runtime swap (which the
SWAPbit replaces) is conditional on the IF branch.

**Running tally:** 18 of 38 words are now inline code generators.

**Files:** `exp/018-moreinline64/{moreinline64.asm,Makefile}`

---

## Experiment 019: Inline Comparison Operators

**Goal:** Convert the five comparison words (`=`, `<`, `>`, `0=`, `0<>`)
from runtime calls (ct=0) to inline code generators (ct=2).

**Rationale:** These comparisons appear in nearly every conditional Forth
word (`min`, `max`, `abs`, `within`, loop bounds). Each currently compiles
a 5-byte CALL instruction. Inlining eliminates the call/ret overhead
(~6 cycles) and enables the SWAPbit to track register state through
comparisons without forced syncs.

### How the original i386 `=` works (ff.asm)

```asm
_eq:  cmp edx, ebx      ; compare NOS to TOS
      sete cl            ; cl = 1 if equal, 0 otherwise
      movzx ebx, cl      ; zero-extend to 32 bits
      neg ebx            ; 0 → 0, 1 → -1 (all-bits-set flag)
      DROP_NOS           ; pop NOS from data stack
      ret
```

All five comparisons follow this pattern: `cmp/test` + `setcc` + `movzx` +
`neg` + optional `DROP_NOS`. The only variation is the `setcc` condition
code: `sete` (=), `setl` (<), `setg` (>), `sete` (0=), `setne` (0<>).

### How the x86-64 inline generators work

Each comparison emits the same 4-instruction sequence directly:

| Word | CMP/TEST instruction | setcc | Bytes | SWAPbit ops |
|------|---------------------|-------|:-----:|-------------|
| `=` | `cmp rdx,rbx` (48 39 DA) | `sete cl` | 16 | s09 + s01×2 |
| `<` | `cmp rdx,rbx` (48 39 DA) | `setl cl` | 16 | s09 + s01×2 |
| `>` | `cmp rdx,rbx` (48 39 DA) | `setg cl` | 16 | s09 + s01×2 |
| `0=` | `test rbx,rbx` (48 85 DB) | `sete cl` | 12 | s09 + s01×2 |
| `0<>` | `test rbx,rbx` (48 85 DB) | `setne cl` | 12 | s09 + s01×2 |

Binary comparisons (`=`, `<`, `>`) use s09 on the `cmp` ModR/M, then s01
on both `movzx` and `neg` to target the correct result register. They end
with `jmp _emit_drop_nos_s` to emit the NOS pop.

Unary comparisons (`0=`, `0<>`) use s09 on the `test` ModR/M (both fields
must swap since `test rbx,rbx` has rbx in both positions). They end with
`jmp _s01` to apply the final SWAPbit.

**Note on equality:** `cmp` with `sete` tests ZF. Since ZF depends only on
whether the result is zero, `cmp a,b` and `cmp b,a` give the same ZF. So
the s09 swap on `=` doesn't affect correctness — only `<` and `>` are
sensitive to operand order.

### Bug found and fixed: flow control SWAPbit reconciliation

When first built, the `min` test failed:
```
: min over over > IF swap THEN drop ; 3 10 min . cr ;
Expected: 3
Got: 10
```

**Root cause:** This was the same SWAPbit flow control bug found in exp 018
and fixed in production ff64.asm, but experiments 017, 018, and 019 were
missing the fix. `swap` inside an IF body toggles the compile-time SWAPbit
flag, but the runtime swap is conditional. At the THEN join point, both
paths must agree on register assignments.

**Fix:** Added `call _rst` to THEN, ELSE, BEGIN, AGAIN, and REPEAT in all
three experiments (017, 018, 019). The `_rst` function checks if SWAPbit
is set; if so, it emits `xchg rbx,rdx` and clears the flag. The jz from
IF jumps to AFTER this xchg, so:
- **Taken path:** IF body code (with swapped register semantics) → xchg
  (restores normal order) → continues.
- **Not-taken path:** jz jumps past body AND xchg → continues with normal
  register order.

Both paths end up with the same register assignment. All tests pass.

### Tests (15 total, all PASS)

| # | Input | Expected | Tests |
|---|-------|----------|-------|
| 1 | `3 3 = .` | -1 | equality true |
| 2 | `3 4 = .` | 0 | equality false |
| 3 | `3 4 < .` | -1 | less-than true |
| 4 | `4 3 < .` | 0 | less-than false |
| 5 | `4 3 > .` | -1 | greater-than true |
| 6 | `3 4 > .` | 0 | greater-than false |
| 7 | `0 0= .` | -1 | zero-equal true |
| 8 | `5 0= .` | 0 | zero-equal false |
| 9 | `0 0<> .` | 0 | nonzero false |
| 10 | `5 0<> .` | -1 | nonzero true |
| 11 | abs(-5) | 5 | unary with 0< + negate |
| 12 | max(3,10) | 10 | < + swap-in-IF |
| 13 | min(3,10) | 3 | > + swap-in-IF |
| 14 | 10! | 3628800 | recursive factorial |
| 15 | fib(10) | 55 | recursive fibonacci |

**Running tally:** 23 of 38 words are now inline code generators.

**Files:** `exp/019-cmpinline64/{cmpinline64.asm,Makefile}`

---

## Experiment 020: Flags-Based Conditionals

**Goal:** Replace the stack-boolean conditional approach (standard Forth)
with FreeForth's native FLAGS-based approach, where comparison words set
CPU flags and store a conditional jump opcode rather than producing boolean
values on the data stack.

**Rationale:** FreeForth's defining innovation is that comparison words like
`<`, `>`, `=` do NOT modify the data stack. Instead, they emit a CMP
instruction (setting CPU FLAGS) and store the appropriate conditional jump
opcode (e.g., $7C for jl) in a compiler variable called `?#` (implemented
as `cond_jmp`). Then `IF`/`UNTIL`/`WHILE` read this variable and emit the
correct conditional jump directly — no boolean creation, no test, no DROP.

This eliminates ~16 bytes of inline code per comparison (the setcc+movzx+neg
+DROP_NOS sequence) and preserves the data stack across comparisons, enabling
idioms like:
```
: min < IF swap THEN nip ;    ( no over over, no drop — elegant! )
: abs 0- 0< IF negate THEN ;  ( 0- sets FLAGS, 0< stores condition )
```

### How the original FreeForth conditionals work

In the original ff.boot, comparisons are defined as:
```
variable ?#
:. _?1 ?# c! ;                    \ store condition byte in ?#
:. _?2 _?1 $DA39, s09 ;           \ _?1 + emit cmp edx,ebx
$7C ... : <` lit _?2 ;            \ push $7C, call _?2
```

And IF:
```
: cond ?@ ?nn 1^ ;                \ read ?#, validate, invert condition
: IF` cond c, SC, ;               \ compile conditional jump byte
```

The `1^` (XOR 1) inverts the condition because IF must jump PAST the body
when the condition is FALSE (e.g., `<` stores jl; IF inverts to jge to skip
the body when NOT less-than).

### How the x86-64 port implements this

The `cond_jmp` variable (1 byte) replaces `?#`. Each comparison word is
an assembly inline generator (ct=2) that stores the condition and optionally
emits `cmp rdx,rbx`:

```asm
_lt_flags:                           ; <
    mov byte [cond_jmp], $7C         ; store jl opcode
    jmp _emit_cmp_s                  ; emit cmp rdx,rbx with SWAPbit

_zlt_flags:                          ; 0<
    mov byte [cond_jmp], $7C         ; store jl opcode (no cmp needed)
    ret
```

IF checks `cond_jmp`:
- If non-zero: invert condition (XOR 1), emit long conditional jump
  (`0F 8x rel32`), clear `cond_jmp`. No test, no DROP — 6 bytes total.
- If zero: fallback to boolean-on-stack (test+DROP1+jz) for backward
  compatibility with code that doesn't use flags-based comparisons.

The short-to-long opcode conversion: `$7x + $10 = $8x` (e.g., jl $7C →
near jl = $0F $8C).

### Critical change: flags-preserving stack operations

The original FreeForth uses ESP (hardware stack pointer) for the data stack.
Push/pop don't affect FLAGS, so stack operations between comparison and IF
naturally preserve the condition.

Our x86-64 port uses R15 as the data stack pointer with explicit arithmetic:
`sub r15, 8` and `add r15, 8`. These MODIFY FLAGS, which would corrupt
the condition between comparison and IF.

**Fix:** All inline code generators now emit `lea r15, [r15±8]` instead
of `sub/add r15, 8`. The LEA instruction computes addresses without
modifying FLAGS. Both encodings are 4 bytes:
```
sub r15, 8      = 49 83 EF 08   → lea r15, [r15-8] = 4D 8D 7F F8
add r15, 8      = 49 83 C7 08   → lea r15, [r15+8] = 4D 8D 7F 08
```

This means `drop`, `nip`, `dup`, `over`, and literal push all preserve
FLAGS, enabling patterns like:
```
: fact dup 1 > drop nip IF ... ;    \ drop and nip preserve FLAGS from >
```

### Comparison word inventory

| Word | Type | Emits | Stores | Stack effect |
|------|------|-------|--------|-------------|
| `<` | binary | `cmp rdx,rbx` | $7C (jl) | none |
| `>` | binary | `cmp rdx,rbx` | $7F (jg) | none |
| `=` | binary | `cmp rdx,rbx` | $74 (je) | none |
| `<>` | binary | `cmp rdx,rbx` | $75 (jne) | none |
| `<=` | binary | `cmp rdx,rbx` | $7E (jle) | none |
| `>=` | binary | `cmp rdx,rbx` | $7D (jge) | none |
| `0-` | unary | `test rbx,rbx` | — | none |
| `0<` | cond | — | $7C (jl) | none |
| `0=` | cond | — | $74 (je) | none |
| `0<>` | cond | — | $75 (jne) | none |
| `0>` | cond | — | $7F (jg) | none |
| `0<=` | cond | — | $7E (jle) | none |
| `0>=` | cond | — | $7D (jge) | none |
| `<.` | dotted | boolean | — | ( a b -- flag ) |
| `>.` | dotted | boolean | — | ( a b -- flag ) |
| `=.` | dotted | boolean | — | ( a b -- flag ) |
| `0<.` | dotted | boolean | — | ( n -- flag ) |
| `0=.` | dotted | boolean | — | ( n -- flag ) |
| `0<>.` | dotted | boolean | — | ( n -- flag ) |

### Idiomatic FreeForth patterns vs standard Forth

| Operation | Standard Forth | FreeForth (flags-based) |
|-----------|---------------|------------------------|
| min | `over over > IF swap THEN drop` | `< IF swap THEN nip` |
| max | `over over < IF swap THEN drop` | `> IF swap THEN nip` |
| abs | `dup 0< IF negate THEN` | `0- 0< IF negate THEN` |
| ?dup | `dup IF dup THEN` | `0- 0<> IF dup THEN` |
| fact guard | `dup 1 > ...` (bool consumes) | `dup 1 > drop nip IF ...` |

### Tests (19 total, all PASS)

| # | Input | Expected | Tests |
|---|-------|----------|-------|
| 1 | abs(-5) flags-based | 5 | 0- 0< IF negate THEN |
| 2 | abs(5) flags-based | 5 | positive passthrough |
| 3 | min(3,10) | 3 | < IF swap THEN nip |
| 4 | min(10,3) | 3 | reverse order |
| 5 | max(3,10) | 10 | > IF swap THEN nip |
| 6 | max(10,3) | 10 | reverse order |
| 7 | 10! | 3628800 | recursive with > drop nip |
| 8 | fib(10) | 55 | recursive with < drop nip |
| 9-14 | dotted comparisons | -1 | =. <. >. 0=. 0<>. 0<. |
| 15-16 | fallback IF (no cond) | 0, 10 | dup IF dup + THEN |
| 17-18 | <= and >= | 0, 77 | nip nip cleanup |
| 19 | BEGIN..UNTIL countdown | 3 2 1 | 0- 0= UNTIL |

**Files:** `exp/020-flagscond64/{flagscond64.asm,Makefile}`

---

## Production Update: Require explicit conditions

**Date:** 2026-02-23

### Goal

Align the 64-bit port with FreeForth2's design philosophy:
1. `IF`, `UNTIL`, `WHILE` require an explicit preceding condition — no fallback.
2. Remove dotted comparison generators (`=.`, `<.`, `>.`, `0=.`, `0<>.`, `0<.`)
   and `IF.`/`WHILE.`/`UNTIL.` from assembly. These belong in Forth, not assembly.
3. Preserve the character of the original: assembly is intentionally minimal;
   most things are implemented in Forth.

### Reasoning

The README states: "requires explicit conditions before IF — avoids source of
faulty assumptions." The fallback path (test+DROP+jz) was a backward-compat
shim that contradicted this design. Dotted comparisons and IF./WHILE./UNTIL.
are legitimate words but belong in ff64.boot once FreeForth macros are stable,
following Lavarenne's principle of keeping assembly short and implementing as
much as possible in Forth.

### Changes

- `IF`/`UNTIL`/`WHILE` now error with "requires preceding condition" when no
  comparison word precedes them
- Error handler resets data stack, SWAPbit, and compilation pointer for clean
  recovery in the REPL
- Removed ~130 lines of dotted comparison assembly code
- Removed IF./WHILE./UNTIL. assembly implementations
- `ff64.boot` unchanged — already uses FLAGS-based idioms exclusively
- `GUIDE.md` updated to remove dotted comparison references

### Lesson

Lavarenne's choice to implement `dup` as `under` `nipdup` (in Forth, not
assembly) reveals a deep principle: the assembly kernel should be the smallest
possible set of primitives. Everything else builds on those primitives using
Forth itself. The dotted comparisons and boolean-conditional words will return
as Forth definitions once the macro system (`s01`, `s08`, `s09`, `c,`, `,`)
is available from the boot source.

---

## Experiment 021: Trailing-comma literal compiler

**Date:** 2026-02-23

### Goal

Implement the FreeForth trailing-comma syntax (`$DA89,`) that is the
foundation for all Forth-defined inline code generators (backtick macros).
Also expose the SWAPbit helpers (`s01`, `s08`, `s09`, `s1`) and compilation
pointer advancement words (`,1`, `,2`, `,3`, `,4`) as callable Forth words.

### Background: How ff.boot macros work

In the original FreeForth, most inline code generators are defined in Forth,
not assembly. A "backtick macro" like `: nipdup` $DA89, s09 ;` defines a
compile-time word that emits machine code. The trailing comma in `$DA89,` is
not the `,` word — it's a special syntax handled by the compiler's number
parser. When the compiler sees a number ending with `,`, it calls `litcomma`,
which emits a `mov [ebp], value` instruction of the appropriate size
(byte, word, or dword).

The key insight: `litcomma` writes bytes at [ebp] (the compilation pointer)
but does NOT advance it. The `s01`/`s08`/`s09` words handle advancement
(by 2 bytes) AND apply the SWAPbit correction. The `s1` word advances by
only 1 byte. The `,1` through `,4` words advance without SWAPbit action.

### How it works in x86-64

The trailing-comma handler (`_litcomma`) checks the value's magnitude and
emits the smallest possible `mov [rbp], imm` instruction:

| Value range | Instruction | Code bytes | Total |
|------------|-------------|------------|-------|
| ≤ $FF | `mov byte [rbp], imm8` | C6 45 00 xx | 4 |
| ≤ $FFFF | `mov word [rbp], imm16` | 66 C7 45 00 xx xx | 6 |
| ≤ $FFFFFFFF | `mov dword [rbp], imm32` | C7 45 00 xx xx xx xx | 7 |

For x86-64, instructions need REX prefixes that the i386 version didn't.
The 64-bit `nipdup` (= `mov rdx, rbx`) is 3 bytes: `48 89 DA`. This
requires two litcomma steps:
```forth
: nipdup  $48, ,1  $DA89, s09 ;
```
The REX prefix ($48) is compiled with `,1` (advance by 1, no SWAPbit),
then the opcode+ModR/M ($DA89) with `s09` (advance by 2, SWAPbit-aware).

### Changes

- Added `_litcomma` function (byte/word/dword size selection)
- Modified compiler loop to detect trailing `,` on number literals
- Added `_s01_word`, `_s08_word`, `_s09_word`, `_s1_word` (callable wrappers)
- Added `_comma1` through `_comma4` (compilation pointer advancement)
- Registered s01, s08, s09, s1, ,1, ,2, ,3, ,4 as WORD64 entries

### Tests (5 total, all PASS)

| # | Input | Expected | Tests |
|---|-------|----------|-------|
| 1 | 1 2 + . cr | 3 | Basic arithmetic unchanged |
| 2 | nipdup ($48,,1 $DA89,,s09) bytes | 218 137 72 | 3-byte mov rdx,rbx |
| 3 | $48,,1 byte + advancement | 72, advance 1 | Single byte litcomma |
| 4 | $DA89,,2 word + advancement | 218 137, advance 2 | Word litcomma |
| 5 | $04C38348,,4 dword + advancement | 4 72, advance 4 | Dword litcomma |

**Files:** `exp/021-litcomma64/{litcomma64.asm,Makefile}`

---

## Experiment 022: Backtick name mangling and Forth-defined macros

**Date:** 2026-02-23

### Goal

Implement the backtick name mangling mechanism that is the heart of
FreeForth's compile-time macro dispatch, then define the first set of
inline code generators entirely in Forth — proving that the assembly
kernel can stay minimal while building complex behavior in the language
itself.

### Background: How FreeForth dispatches macros

In the original FreeForth, when the compiler encounters a word like `dup`
during compilation, it first appends a backtick to create `dup`` and
searches the dictionary. If a word named `dup`` exists, it is executed
immediately — generating inline machine code for the operation. If no
backtick version is found, the compiler falls back to the plain word
and dispatches based on its ct (compile-time) flag: ct=0 compiles a call,
ct=1 compiles a literal, ct≥2 executes immediately.

This naming convention IS the dispatch mechanism. Any word can have a
backtick counterpart that defines its compile-time behavior. The word
`dup`` is just a regular ct=0 word that happens to emit machine code
when called — it gets its compile-time behavior purely from the naming
convention, not from any special ct flag.

### The beauty of the design

Consider the chain: When you write `dup` in a definition:
1. Compiler appends backtick → finds `dup`` → executes it
2. `dup`` calls `under`` and `nipdup``
3. `under`` emits push-NOS code (7 bytes), `nipdup`` emits mov NOS←TOS (3 bytes)
4. Your definition now contains 10 bytes of inline `dup` code

When defining `dup`` itself: `: dup` under` nipdup` ;`
1. `under`` is found via NORMAL lookup (ct=0) → compiled as a call
2. `nipdup`` is found via NORMAL lookup (ct=0) → compiled as a call
3. So `dup``'s body is just: call under` / call nipdup` / ret

When used inside another MACRO definition: `: 2dup` over` over` ;`
1. `over`` is found via normal lookup (ct=0) → compiled as a call
2. At runtime, each call to `over`` emits 10 bytes of inline code

The backtick is never consumed or transformed — it's literally part of
the word's name. The compiler's temporary-append trick makes it invisible
to the user.

### Changes

1. **Backtick name mangling in the compiler**: Before the normal dictionary
   lookup, the compiler temporarily appends a backtick to the parsed word
   (modifying the input buffer in-place, then restoring it). If the
   backtick version is found, it's executed immediately.

2. **`swap`` as an assembly primitive**: Registered as a ct=0 word that
   toggles the SWAPbit. This is the one stack operation that MUST be in
   assembly because it modifies the compile-time register naming state
   rather than emitting code.

3. **Forth macros defined in macros.ff**:
   - `under`` — emit push-NOS (7 bytes: lea r15,[r15-8]; mov [r15],rdx)
   - `nip`` — emit pop-NOS (7 bytes: mov rdx,[r15]; lea r15,[r15+8])
   - `nipdup`` — emit copy TOS→NOS (3 bytes: mov rdx,rbx)
   - `drop`` — swap` nip` (toggle SWAPbit + pop NOS)
   - `dup`` — under` nipdup` (push NOS + copy TOS)
   - `over`` — under` swap` (push NOS + toggle SWAPbit)

4. **`\` comment fix**: Changed from "skip to end of buffer" to "skip to
   next newline". The original behavior broke when input was piped (all
   lines read in one sys_read), because `\` would skip ALL remaining input.

### Tests (12 total, all PASS)

| # | Input | Expected | Tests |
|---|-------|----------|-------|
| 1 | 1 2 + . cr ; | 3 | Basic arithmetic unchanged |
| 2 | : t nipdup ; 7 t . cr ; | 7 | nipdup copies TOS to NOS |
| 3 | : t under nip ; 10 20 t . cr ; | 20 | under+nip = identity |
| 4 | : t dup ; 42 t . . cr ; | 42 42 | Forth-defined dup |
| 5 | : t drop ; 10 20 t . cr ; | 10 | Forth-defined drop |
| 6 | : t over ; 10 20 t . . . cr ; | 10 20 10 | Forth-defined over |
| 7 | : t swap ; 10 20 t . . cr ; | 10 20 | Forth-defined swap |
| 8 | : t nip ; 10 20 t . cr ; | 20 | Forth-defined nip |
| 9 | : double dup + ; 21 double . cr ; | 42 | dup+add composition |
| 10 | : diff over swap - ; 100 58 diff . cr ; | 42 | over+swap+sub |
| 11 | : t swap dup ; 10 20 t . . . cr ; | 10 10 20 | SWAPbit interaction |
| 12 | : abs dup 0< IF negate THEN ; 0 42 - abs . cr ; | 42 | Full macro + flow control |

### Insight: Lavarenne's design philosophy revealed

This experiment crystallizes something profound about FreeForth's design.
The entire inline code generation system — the thing that makes FreeForth
fast — is built from just a few assembly primitives:

- `swap`` (toggle a bit)
- `s01`/`s08`/`s09` (advance compilation pointer + SWAPbit fixup)
- litcomma (write bytes at compilation pointer)

Everything else — dup, drop, over, nip, all arithmetic operators, memory
access, even flow control macros — is defined in Forth using these
primitives. The assembly kernel stays astonishingly small while the
language builds itself up through composition.

This is what DG means by "preserving the character of FreeForth."

**Files:** `exp/022-backtick64/{backtick64.asm,macros.ff,Makefile}`

---

## Experiment 023: Forth-defined inline code generators

**Date:** 2026-02-23

### Goal

With the litcomma mechanism (exp 021) and backtick dispatch (exp 022)
proven, define a comprehensive set of inline code generators entirely
in Forth. This demonstrates that the x86-64 assembly kernel can remain
minimal while building the full set of stack, arithmetic, and memory
operations from Forth macros.

### Macros defined (27 total)

**Stack operations** (7):
```forth
: under` $F87F8D4D, ,4 $49, ,1 $1789, s08 ;
: nip` $49, ,1 $178B, s08 $087F8D4D, ,4 ;
: nipdup` $48, ,1 $DA89, s09 ;
: drop` swap` nip` ;
: dup` under` nipdup` ;
: over` under` swap` ;
: tuck` swap` over` ;
```

**Binary arithmetic** (12 — 6 "over" variants + 6 consuming):
```forth
: over+` $48, ,1 $D301, s09 ;    ( and similarly over-`, over&`, etc. )
: +` over+` nip` ;               ( and -, *, &, |, ^ )
```

**Unary operations** (5):
```forth
: negate` $48, ,1 $DBF7, s01 ;
: ~` $48, ,1 $D3F7, s01 ;
: 1+` $48, ,1 $C3FF, s01 ;
: 1-` $48, ,1 $CBFF, s01 ;
: 2+` 1+` 1+` ;
```

**Memory access** (2):
```forth
: @` $48, ,1 $1B8B, s09 ;
: c@` $48, ,1 $0F, ,1 $1BB6, s09 ;
```

### Production promotion

All macros were promoted to ff64.boot, along with the production
changes to ff64.asm:
- `_litcomma` function (byte/word/dword size selection)
- Trailing-comma detection in compiler loop
- Callable s09/s08/s01/s1 + ,1-,4 as WORD64 entries
- `swap`` as ct=0 assembly word
- Backtick name mangling in compiler
- `\` comment fix (scan to newline, not end of buffer)

### The `\` comment fix

A bug discovered in exp 022: the `\` comment word set the input pointer
to the end of the ENTIRE buffer. When input is piped (common in our
tests), sys_read may deliver multiple lines at once, so `\` would skip
ALL remaining input. Fixed to scan forward to the next newline character.

### x86-64 opcode patterns

All binary arithmetic ops follow the same 3-byte pattern with REX.W:
```
$48, ,1 $xxxx, s09    (or s01 for unary ops)
```

The specific opcodes for the ModR/M+opcode word:
| Operation | Opcode word | Instruction |
|-----------|-------------|-------------|
| add | $D301 | add rbx,rdx |
| sub | $D329 | sub rbx,rdx |
| and | $D321 | and rbx,rdx |
| or  | $D309 | or rbx,rdx  |
| xor | $D331 | xor rbx,rdx |
| neg | $DBF7 | neg rbx |
| not | $D3F7 | not rbx |
| inc | $C3FF | inc rbx |
| dec | $CBFF | dec rbx |

The `s09`/`s01` call applies SWAPbit correction to the ModR/M byte,
swapping rbx↔rdx when the SWAPbit is set.

### Tests (23 total, all PASS)

Stack: dup, drop, over, swap, nip, tuck
Arithmetic: +, -, *, and, or, xor, negate, ~, 1+, 1-
Memory: @, c@
SWAPbit: swap+dup interaction
Composition: abs, max, over+, 2dup+

**Files:** `exp/023-forthmacros64/{forthmacros64.asm,macros.ff,Makefile}`

### Reflection

This experiment marks a turning point. We've now reproduced Lavarenne's
key insight: define the machine in assembly, then build the language in
itself. The ff64.boot file now contains 27 inline code generators that
were previously hard-coded in ff64.asm. Each one is a tiny composition
of litcomma calls, SWAPbit helpers, and other macros. The assembly
kernel provides only the irreducible primitives: the compiler loop,
the SWAPbit mechanism, litcomma, and the handful of operations that
can't be expressed as inline code (I/O, flow control, _rst).

The assembly inline generators (ct=2 words) remain as fallbacks — they
work without ff64.boot. But with the boot file loaded, the Forth macros
shadow them via the backtick dispatch. This dual-layer approach means
the binary is self-contained while the boot file extends it in the
spirit of the original.
