# FreeForth2 x86-64 Port — A Historian's Guide

*For anyone continuing Christophe Lavarenne's work.*

This document explains how FreeForth2 works, how the x86-64 port works,
and why they differ. It is written for someone with only a rudimentary
grasp of assembly language.

**A note on authorship:** This guide was written by an AI (Claude,
Anthropic) working under the direction of DG, the human maintainer of
FreeForth2. The AI wrote the prose and the code; DG directed the effort,
corrected errors, and provided the understanding of Lavarenne's design
that the AI could not have arrived at alone. See the Prologue of
`JOURNAL.md` for a fuller account of how this collaboration works.

---

## Part 1: The Machine Underneath

### Registers: named boxes that hold numbers

A CPU has a small number of very fast storage locations called
**registers**. Think of them as named variables that the processor can
access instantly. On x86-64, the main ones are:

| Register | FreeForth2 role | Explanation |
|----------|----------------|-------------|
| `rbx` | TOS (Top Of Stack) | The most recently pushed value |
| `rdx` | NOS (Next On Stack) | The second value on the stack |
| `r15` | Data stack pointer | Points to the rest of the stack in memory |
| `rsp` | Call/return stack | Tracks where to return after a function call |
| `rbp` | "here" / compilation pointer | Where the next compiled byte goes |
| `rax` | Scratch / syscall number | Temporary; also used for Linux system calls |
| `rcx` | Scratch / counter | Temporary; used in string operations |
| `rdi`,`rsi` | Syscall arguments | Used to pass arguments to Linux |

On the original i386 FreeForth, the same roles existed but with 32-bit
registers (ebx, edx, eax, etc.) and two crucial differences:

1. **No dedicated data stack register.** The original used a clever trick:
   `xchg eax, esp` (swap eax with the stack pointer) to momentarily switch
   between the call stack and data stack. This single-byte instruction made
   the data stack "free" but deeply entangled the two stacks.

2. **4-byte cells** instead of 8-byte. Every pointer, every stack slot,
   every dictionary entry was 4 bytes.

### The data stack: a tower of numbers

Forth's fundamental data structure is a stack — a tower of numbers where
you can only touch the top. In FreeForth2:

```
         rbx  →  42      ← TOS (top of stack)
         rdx  →  17      ← NOS (next on stack)
  r15 →  [memory]  →  8  ← third item
  r15+8 → [memory] →  3  ← fourth item
  ...
```

The top two items live in CPU registers (very fast). Everything below
lives in memory pointed to by r15. To push a value:

```asm
; DUP1: push a new value onto the stack
sub r15, 8          ; make room on the memory stack
mov [r15], rdx      ; save old NOS to memory
mov rdx, rbx        ; old TOS becomes new NOS
mov rbx, <value>    ; new value becomes TOS
```

To pop:

```asm
; DROP1: remove the top value
mov rbx, rdx        ; NOS becomes TOS
mov rdx, [r15]      ; load new NOS from memory
add r15, 8          ; reclaim the memory slot
```

### Machine code: the CPU's native language

The CPU executes sequences of bytes. Each instruction is 1-15 bytes.
Some examples:

| Bytes | Instruction | What it does |
|-------|-------------|-------------|
| `48 01 D3` | `add rbx, rdx` | TOS = TOS + NOS |
| `48 87 DA` | `xchg rbx, rdx` | Swap TOS and NOS |
| `48 89 D3` | `mov rbx, rdx` | Copy NOS into TOS |
| `E8 xx xx xx xx` | `call <address>` | Call a function |
| `C3` | `ret` | Return from a function |

The `48` prefix is called a **REX prefix** — it tells the CPU to use
64-bit registers instead of 32-bit. On i386, the same `add ebx, edx`
was just `01 D3` (no prefix needed).

### System calls: talking to Linux

To print text or read input, the program asks Linux via a **system call**.
On x86-64:

```asm
mov rax, 1          ; syscall 1 = write
mov rdi, 1          ; file descriptor 1 = stdout
mov rsi, <address>  ; pointer to the text
mov rdx, <length>   ; how many bytes to write
syscall             ; ask Linux to do it
```

On the original i386, this was `int $80` with different register
assignments and different syscall numbers (write was 4, not 1).

---

## Part 2: The Dictionary — How Forth Finds Words

When you type `dup` at the Forth prompt, the system must find what `dup`
means. It searches a **dictionary** — a linked list of word headers.

### Header structure (x86-64 port)

Each header is laid out in memory like this:

```
Offset  Size  Field
  0      8    xt (execution token — address of the code, or literal value)
  8      1    ct (compile type — how the compiler handles this word)
  9      1    name length
 10      N    name bytes (e.g., "dup")
 10+N    1    NUL terminator
```

The `ct` field controls compilation behavior:

| ct | Meaning | What the compiler does |
|----|---------|----------------------|
| 0  | Code word | Emits `call <xt>` — a 5-byte function call |
| 1  | Literal | Emits inline code to push `xt` as a number |
| ≥2 | Compile-time | Executes `xt` immediately during compilation |

**Variables** have ct=1 with xt = address of their data cell. When the
compiler sees a variable name, it emits code to push that address.

**Constants** have ct=1 with xt = the constant's value. When the compiler
sees the constant name, it emits code to push that value.

**IF, THEN, BEGIN**, etc. have ct=2. When the compiler sees them, it
runs their code immediately — they emit branch instructions and manage
forward/backward references on the data stack.

### The original i386 difference

The i386 headers used 4-byte xt fields (offset h.ct was 4, h.sz was 5,
h.nm was 6). The x86-64 port doubled the xt field to 8 bytes, shifting
all subsequent offsets.

### How headers are generated: the FASM macro-nesting trick

The assembly-defined words (primitives like `drop`, `emit`, variables
like `H`, `SC`) need dictionary headers so Forth can find them. FASM's
macro system generates these at assembly time using a clever nesting
technique invented by Lavarenne.

Each `WORD64` invocation **redefines** the `GENWORDS64` macro to emit
that word's header and then call the previous definition of `GENWORDS64`:

```nasm
macro WORD64 name, xt_val, ct_val, namelen {
    macro GENWORDS64 \{
        dq xt_val
        db ct_val
        db namelen
        db name
        db 0
        GENWORDS64          ;; calls the PREVIOUS definition
    \}
}
```

The base case emits a sentinel:

```nasm
macro GENWORDS64 {
        dq 0                ;; don't-care xt
        db -1               ;; $FF ct — stop value for hidepvt
        db 0                ;; sz=0 — stop value for words
        db 0                ;; empty name
}
```

When `GENWORDS64` is finally invoked (at the end of the `.flat`
section), FASM unwinds the nested macros — each redefinition calls the
one before it, emitting headers in reverse order (last defined word
first, base sentinel last). This produces a contiguous block of headers
at assembly time with no runtime cost.

The i386 `WORD` / `GENWORDS` macros work identically, just with `dd`
(4-byte xt) and a counted-string `CDB` macro instead of an explicit
length byte.

### Memory layout and the headbuf tradeoff

At runtime, new headers grow **downward** from the `H` pointer into
`headbuf`. The assembly-generated headers sit at the top of headbuf
(at label `heads64`), and `H` starts there. As Forth defines new words,
`H` decreases.

In the i386 binary, headers are emitted into the `.flat` section but
**relocated** at startup — `_start` does a `rep movsd` to copy headers
(and boot source) from their file position to the runtime location in
`.bss`. This keeps the binary small: the header growth area is in `.bss`
(uninitialized, not stored on disk).

The x86-64 port takes a different approach: `headbuf` (64KB) is placed
directly in the `.flat` section (PROGBITS), and `heads64` / `GENWORDS64`
emit headers right after it. No relocation is needed — `_start` simply
sets `[H]` to point at `heads64` and begins compiling. The tradeoff is
that 64KB of zeros are stored on disk (the unused portion of headbuf),
accounting for roughly 64% of the ~100KB binary. The i386 binary avoids
this with ~6 instructions of startup relocation code.

---

## Part 3: The Compiler — From Text to Machine Code

FreeForth is a **subroutine-threaded compiler**. Each Forth word compiles
to a native `call` instruction. When you type:

```forth
3 4 + . cr ;
```

The compiler:
1. Reads `3` → not a word → it's a number → emits code to push 3
2. Reads `4` → not a word → emits code to push 4
3. Reads `+` → found in dictionary (ct=0) → emits `call _add`
4. Reads `.` → found (ct=0) → emits `call _dot`
5. Reads `cr` → found (ct=0) → emits `call _cr`
6. Reads `;` → compiles `ret`, executes the whole sequence

The generated machine code looks like:

```
[push 3][push 4][call _add][call _dot][call _cr][ret]
```

Each `[push N]` is a DUP1 sequence (10 or 15 bytes depending on value
size). Each `[call X]` is 5 bytes. The `[ret]` is 1 byte.

### Named definitions

When you write `: square dup * ;`, the compiler:
1. Sees `:` → reads the next word (`square`) as a name
2. Creates a dictionary header: xt = current compilation pointer, ct=0
3. Compiles `dup` and `*` as calls
4. Sees `;` → compiles `ret`, marks the definition as complete

Now `square` is in the dictionary. When the compiler later sees `square`,
it emits `call <square's address>`.

### Literal compilation

Numbers are compiled as inline "push" sequences. For small numbers (fits
in 32 bits):

```asm
; DUP1 with immediate value (small literal)
49 83 EF 08     sub r15, 8
49 89 17        mov [r15], rdx
48 89 DA        mov rdx, rbx
BB xx xx xx xx  mov ebx, <32-bit value>    ; 5 bytes
```

For large numbers (needs full 64 bits):

```asm
49 83 EF 08     sub r15, 8
49 89 17        mov [r15], rdx
48 89 DA        mov rdx, rbx
48 BB xx xx xx xx xx xx xx xx  mov rbx, <64-bit value>  ; 10 bytes
```

### Quick reference: compiled code byte patterns

This table consolidates all the byte patterns that FreeForth's compiler
emits. It serves as a reference for anyone reading generated code in GDB
or writing tools that process compiled FreeForth output.

| Pattern | Bytes | Meaning |
|---------|-------|---------|
| `49 83 EF 08` `49 89 17` `48 89 DA` | 10 | DUP1 preamble: push NOS to memory stack, move TOS→NOS |
| `BB imm32` | 5 | Small literal: `mov ebx, imm32` (follows DUP1) |
| `48 BB imm64` | 10 | Large literal: `mov rbx, imm64` (follows DUP1) |
| `E8 rel32` | 5 | `call` — word invocation (subroutine threading) |
| `E9 rel32` | 5 | `jmp` — tail-call optimization (`;` rewrites last `E8` to `E9`) |
| `C3` | 1 | `ret` — end of definition |
| `0F 8x rel32` | 6 | Conditional jump (`IF`/`UNTIL`/`WHILE`): 8x encodes the condition |
| `E9 rel32` (backward) | 5 | Unconditional backward jump (`AGAIN`/`REPEAT`) |
| `call _litstr_rt` + `db len, "str...", 0` | 5+N | Inline string literal (`"..."`) |
| `call _dotstr_rt` + `db len, "str...", 0` | 5+N | Inline print-string (`."`/`."`) |
| `4D 8D 7F 08` | 4 | Flag-preserving DROP1: `lea r15, [r15+8]` |
| `49 83 C7 08` | 4 | Standard DROP1: `add r15, 8` (clobbers flags) |
| `48 85 DB` | 3 | `test rbx, rbx` — test TOS for zero (fallback IF path) |

**Reading a definition in GDB:** Use `x/Ni addr` to disassemble from a
word's execution token. Look for `E8`/`E9` to identify which words it
calls, `BB`/`48 BB` for its literals, and `C3` for its end. Inline
strings follow their `call` instruction as raw bytes — GDB will show
them as nonsense instructions; use `x/Ns addr` to read the string.

### Number literal parsing

When the compiler encounters a token that isn't in the dictionary, it
tries to parse it as a number. Lavarenne's original parser is
table-driven: a 128-byte character classification table maps each ASCII
value to one of 13 handler methods, dispatched via a jump table.

The x86-64 port preserves this design exactly. Supported formats:

| Prefix/syntax | Meaning | Example | Value |
|---------------|---------|---------|-------|
| (none) | Decimal | `42` | 42 |
| `-` | Negative | `-7` | -7 |
| `$` | Hexadecimal | `$FF` | 255 |
| `&` | Octal | `&100` | 64 |
| `%` | Binary | `%1010` | 10 |
| `N#` | Base N | `8#77` | 63 |
| `'` | Quoted ASCII | `'A` | 65 |
| `'` `,` `/` | Skip (digit grouping) | `1'000` | 1000 |
| `-` (interior) | Gregorian date | `2000-3-1` | 730485 |
| `:` | Time (×60) | `1:30:0` | 5400 |
| `_` | Day-hour (×24) | `1_12:0:0` | 129600 |

The date parser uses the Gregorian calendar algorithm (origin March 1,
five-month period approximation). Combined with the suffix mechanism
(where `2000-3-1-` means "push date, compile subtract"), this enables
compact compile-time expressions:

```forth
[ 1970-1-1 2000-3-1- 24:0:0* 1:0:0+ ]   \ → -951865200 (epoch offset)
```

**x86-64 porting note:** The only non-trivial issue was sign extension
in the date algorithm. `sub eax, 123` can produce a negative result,
but writing to `eax` on x86-64 zeros the upper 32 bits, turning -1
into 4294967295. A single `cdqe` instruction fixes this.

---

## Part 4: Flow Control — Branches and Loops

### IF / THEN

`IF` compiles a conditional forward jump. It supports two paths:

**Flags-based path** (when `cond_jmp` is set by a preceding comparison):

1. Read the stored condition from `cond_jmp` and clear it
2. Invert the condition (XOR 1) — e.g., jl ($7C) becomes jge ($7D)
3. Emit a long conditional jump: `0F 8x rel32` (6 bytes)
4. Push the placeholder's address onto the compile-time data stack

The inversion is needed because IF must jump PAST the body when the
condition is FALSE. For example, `< IF ...` means "if less than, do the
body." The `<` stores jl (jump if less). IF inverts to jge (skip body
if NOT less).

**Fallback path** (when no comparison precedes IF — backward compat):

1. Emit `test rbx, rbx` (is TOS zero?)
2. Emit DROP1 (remove the flag from the stack) using flag-preserving
   `lea r15, [r15+8]` instead of `add r15, 8`
3. Emit `jz <placeholder>` (jump if zero — skip the IF body)
4. Push the placeholder's address onto the compile-time data stack

`THEN` patches the placeholder:

1. Call `_rst` to reconcile SWAPbit at the join point
2. Pop the placeholder address
3. Calculate: offset = current_position - placeholder - 4
4. Write the offset into the placeholder

**Critical encoding detail (the REX prefix bug):** The flag-preserving
DROP1 uses `lea r15, [r15+8]`, encoded as `4D 8D 7F 08`. The REX
prefix must be `4D` (REX.W=1, REX.R=1, REX.B=1) because r15 appears
in both the destination (reg field, needs REX.R) and source (r/m field,
needs REX.B). Using `49` (REX.R=0) would silently encode
`lea rdi, [r15+8]` — writing to the wrong register. This single-bit
error caused days of debugging during phase 1.

### BEGIN / UNTIL

`BEGIN` pushes the current compilation address onto the data stack.
`UNTIL` compiles a conditional backward jump to that address. Like IF,
it checks `cond_jmp` first (flags-based path) and falls back to
test+DROP1+jz if no condition was set.

### WHILE / REPEAT

`WHILE` is like IF (forward jump). `REPEAT` compiles an unconditional
backward jump to BEGIN, then patches WHILE's forward jump.

---

## Part 5: The Boot File (ff64.boot)

The boot file defines higher-level Forth words using the built-in
primitives. Each definition is explained below.

### Reading stack diagrams

Stack effect comments use the notation `( before -- after )` where the
**rightmost** item is the Top Of Stack (TOS). Items are consumed from
the left side and produced on the right side. For example:

- `( a b -- a+b )` means: takes two values, produces their sum
- `( a b -- a b a b )` means: the two values remain, plus copies on top
- `( a b -- )` means: both values are consumed, nothing is left
- `( -- x )` means: nothing is consumed, one value is produced
- `( a b c d -- c d a b )` means: four items rearranged

In a stack diagram, `a` is always deeper than `b`, `b` deeper than `c`,
and so on. The rightmost item on either side is TOS. When you see
`. . . .` in Forth, it prints TOS first (rightmost), so the printed
order appears "reversed" compared to the diagram.

### Stack manipulation

```forth
: 2dup over over ;
```
**2dup** ( a b -- a b a b ) — Duplicates the top two stack items.
`over` copies NOS to TOS, then `over` copies the (new) NOS to TOS.

```forth
: 2drop drop drop ;
```
**2drop** ( a b -- ) — Removes the top two items.

```forth
: 2swap rot >r rot r> ;
```
**2swap** ( a b c d -- c d a b ) — Swaps the top two pairs.
First `rot` brings `b` (third from top) to TOS: `a c d b`. Then `>r`
saves `b` on the return stack: `a c d`. Second `rot` brings `a` (third
from top) to TOS: `c d a`. Finally `r>` restores `b`: `c d a b`.

```forth
: ?dup 0- 0<> IF dup THEN ;
```
**?dup** ( x -- x x | 0 ) — Duplicates TOS only if it's nonzero.
`0-` emits `test rbx,rbx` to set FLAGS from TOS (without consuming it).
`0<>` stores the "not zero" condition. `IF` uses that condition. If
nonzero, `dup` copies TOS. If zero, nothing happens — the zero remains.

### Arithmetic

```forth
: abs 0- 0< IF negate THEN ;
```
**abs** ( n -- |n| ) — Absolute value. `0-` sets FLAGS from TOS.
`0<` stores the "negative" condition. If TOS is negative, `negate` it.
Note: unlike standard Forth `dup 0< IF negate THEN`, the flags-based
version doesn't need `dup` because `0-` doesn't consume TOS.

```forth
: max > IF swap THEN nip ;
```
**max** ( a b -- max ) — Keeps the larger of two values.
`>` emits `cmp NOS,TOS` and stores the "greater than" condition.
The stack is unchanged: still `( a b )`. If NOS > TOS (a > b), `swap`
puts a on top. `nip` removes NOS (the smaller value). Unlike standard
Forth `over over < IF swap THEN drop`, the flags-based version needs no
`over over` (comparison doesn't consume values) and uses `nip` instead
of `drop`.

```forth
: min < IF swap THEN nip ;
```
**min** ( a b -- min ) — Same logic, opposite comparison.

### Memory

```forth
: ? @ . ;
```
**?** ( addr -- ) — Fetch and print. Shorthand for `@ .`.

```forth
: on -1 swap ! ;
```
**on** ( addr -- ) — Store TRUE (-1) at address.

```forth
: off 0 swap ! ;
```
**off** ( addr -- ) — Store FALSE (0) at address.

### Output

```forth
: space $20 emit ;
```
**space** ( -- ) — Print a single space character (ASCII 0x20).

```forth
: spaces BEGIN 0- 0> WHILE space 1 - REPEAT drop ;
```
**spaces** ( n -- ) — Print n spaces. At each iteration, `0-` tests
TOS (the counter) and `0>` stores the "positive" condition. `WHILE`
uses that condition to continue or exit. `space` prints a space, `1 -`
decrements the counter. When the counter reaches 0, `0>` is false
and `WHILE` exits. `drop` removes the zero counter.

### Constants

```forth
-1 constant TRUE
0 constant FALSE
```
**TRUE** = -1 (all bits set), **FALSE** = 0. In Forth, any nonzero value
is truthy, but the canonical true is -1 because bitwise operations work
correctly: `TRUE AND x = x`, `TRUE OR x = TRUE`.

---

## Part 6: The SWAPbit — FreeForth's Signature Innovation

In most Forth systems, `swap` generates a runtime instruction to exchange
the top two stack items. In FreeForth, `swap` generates **nothing**. Instead,
a compile-time flag called the **SWAPbit** tracks which register is
"logically" TOS.

### How it works

The CPU has two registers caching the top of the data stack: ebx and edx
(or rbx/rdx on x86-64). Normally, ebx = TOS. When the SWAPbit is set,
edx = TOS.

When the compiler encounters `swap`, it just toggles the SWAPbit.
Subsequent code generators check the flag and emit instructions with the
correct register encoding.

The key insight: in x86 encoding, ebx is register 3 (binary 011) and
edx is register 2 (binary 010). They differ by exactly one bit. So
swapping between them requires only an XOR on specific bits in the
instruction's ModR/M byte:

| XOR mask | Effect |
|----------|--------|
| `$01` | Swap destination register (bits [2:0]) |
| `$08` | Swap source register (bits [5:3]) |
| `$09` | Swap both |

The functions `s01`, `s08`, and `s09` apply these masks to the last
compiled instruction when the SWAPbit is set. The result: zero-cost
register renaming at compile time.

### Why the x86-64 port now supports it (experiments 016-017)

Full SWAPbit integration requires every primitive to be an **inline code
generator** (not a called function). Experiment 016 converted 10 core
primitives to inline code generators. Experiment 017 made them
SWAPbit-aware by adding s01/s08/s09 register-swap functions.

Now when the compiler sees `swap`, it runs `_swap_inline`, which simply
toggles bit 1 of SC — emitting zero bytes. All subsequent inline
generators (dup, drop, +, -, *, negate, not, over, nip) check the
SWAPbit and XOR the appropriate ModR/M bits.

Before `call` and `ret` instructions, `_rst` syncs the registers by
emitting `xchg rbx,rdx` (3 bytes) if the SWAPbit is set. This ensures
called functions always see the standard register assignment.

The cost of swap is amortized: often `swap` is followed by an inline
operation that absorbs the register swap, and no `xchg` is ever emitted.
Only when a non-inline word (ct=0) follows swap does the 3-byte `xchg`
appear.

---

## Part 7: Inline Code Generation (Phase 2)

### The goal

Replace `call _add` (5 bytes, function call overhead) with inline
`48 01 D3` (3 bytes, `add rbx, rdx`). This makes the generated code:
- **Smaller**: 3 bytes instead of 5
- **Faster**: No call/return overhead
- **SWAPbit-compatible**: The ModR/M byte can be XORed to swap registers

### The approach

Each primitive becomes a **compile-time word** (ct=2) that emits its
machine code bytes directly into the code buffer. For example, when the
compiler sees `+`, it calls `_add_inline`:

```asm
_add_inline:
    mov byte [rbp], $48         ; REX.W prefix
    mov word [rbp+1], $D301     ; add rbx, rdx
    add rbp, 3
    call _s09                   ; XOR ModR/M if SWAPbit set
    jmp _emit_drop_nos_s        ; pop new NOS from stack
```

The `_s09` call checks the SWAPbit and XORs `$09` into the ModR/M byte
at `[rbp-1]`, changing `add rbx,rdx` to `add rdx,rbx` if needed.

### Current inline primitives

| Category | Words | Pattern |
|----------|-------|---------|
| Arithmetic | `+ - * negate` | Binary op + DROP_NOS, or unary |
| Stack | `dup drop swap over nip rot tuck` | DUP_NOS/DROP_NOS combinations |
| Bitwise | `and or xor not` | Same as arithmetic |
| Memory | `@ c@` | Unary: `mov rbx,[rbx]` |
| **Flags-based** | `< > = <> <= >= 0- 0< 0= 0<> 0> 0<= 0>=` | Emit cmp/test, store condition |

### FLAGS-based conditionals (FreeForth approach)

A defining feature of FreeForth is that **comparison words do not produce
boolean values**. Instead:

1. Binary comparisons (`<`, `>`, `=`, etc.) emit `cmp rdx,rbx` (setting
   CPU FLAGS) and store a conditional jump opcode in the `cond_jmp` variable.
2. Unary conditions (`0<`, `0=`, etc.) just store the condition — they
   expect a preceding `0-` (which emits `test rbx,rbx`) or any other
   FLAGS-setting instruction.
3. `IF`/`UNTIL`/`WHILE` read `cond_jmp`, invert the condition (XOR 1),
   and emit a long conditional jump. No test, no DROP.

**Key insight: `0=`, `0<>`, `0<`, `0>` etc. emit NO runtime code.**
They only store a Jcc opcode in `cond_jmp` — it is `0-` (which emits
`or reg,reg`) or a binary comparison (`=`, `<`, etc., which emits
`cmp rdx,rbx`) that sets CPU FLAGS at runtime. This means CPU FLAGS
survive across word boundaries: `CALL`/`RET` don't modify RFLAGS, and
`drop` uses `mov`+`lea` (also flags-preserving). A word can set FLAGS
internally (e.g., via subtraction), and the caller can simply write
`0= IF` — the `0=` just tells `IF` which jump opcode to use, without
clobbering the surviving flags.

This eliminates the setcc+movzx+neg+DROP sequence (~16 bytes) and
preserves the data stack, enabling the elegant FreeForth idioms:

```forth
: min < IF swap THEN nip ;       ( vs standard: over over > IF swap THEN drop )
: abs 0- 0< IF negate THEN ;    ( vs standard: dup 0< IF negate THEN )
```

**Flags-preserving stack ops:** All inline code generators use
`lea r15, [r15±8]` instead of `sub/add r15, 8`. The LEA instruction
doesn't modify FLAGS, so stack operations between a comparison and IF
preserve the condition. This is essential because our x86-64 port uses
R15 for the data stack (unlike the original which uses ESP with push/pop,
which naturally preserves FLAGS).

### The flag-setting vocabulary

Nearly every ALU word in FreeForth sets CPU flags, and those flags
are meaningful. The `-` suffix is a naming convention signaling
"subtraction" — `$2F -` compiles `sub reg, 0x2F`, so ZF=1 means
the value was 0x2F — but the pattern extends far beyond subtraction.

**Flag-setting words** (all set ZF when the result is zero):

| Word | x86 instruction | ZF=1 means |
|------|-----------------|------------|
| `0-` | `or reg,reg` | value was zero |
| `-` | `sub rdx,rbx` | operands were equal |
| `$2F -` | `sub reg, 0x2F` | value was 0x2F |
| `+` | `add rdx,rbx` | sum is zero |
| `1+` | `inc reg` | value was -1 |
| `1-` | `dec reg` | value was 1 |
| `&` | `and rdx,rbx` | no common bits |
| `$FF &` | `and reg, 0xFF` | low byte is zero |
| `3 &` | `and reg, 3` | aligned (low 2 bits clear) |
| `\|` | `or rdx,rbx` | both were zero |
| `^` | `xor rdx,rbx` | operands were equal |
| `=`,`<`,`>` | `cmp rdx,rbx` | (per condition) |

**Flags-preserving words** (use only `mov`, `lea`, `push`, `pop`):
`drop`, `nip`, `2drop`, `dup`, `over`, `swap`, `r>`, `>r`,
`@`, `c@`, `!`, `c!`.

This means almost any computation can feed a conditional. The
idiom `$2F - 0= drop IF` is not a comparison *followed by* a
boolean test — it is a subtraction that sets ZF, a Jcc selector
(`0=`), a flags-preserving cleanup (`drop`), and a jump (`IF`).
The CPU flags flow through the entire sequence unbroken.

### Words that remain as runtime calls

| Category | Words | Why |
|----------|-------|-----|
| I/O | `cr . emit` | Perform syscalls — must be called |
| Division | `/ mod /mod` | Use rdx:rax for idiv — conflict with NOS |
| Shifts | `lshift rshift` | Need rcx for shift count |
| Memory write | `! c! +!` | Consume 2-3 items, complex DROP |
| Compilation | `here depth allot , c,` | Interact with rbp |
| Bulk ops | `cmove fill erase zlen` | Loop-based, use rsi/rdi/rcx |
| Return stack | `>r r> r@` | Interact with rsp |
| Literals | `1 2` | Could be inlined but low priority |

### Flow control and the SWAPbit

A subtle issue arises when `swap` appears inside a conditional body:

```forth
: min < IF swap THEN nip ;
```

The `swap` toggles the SWAPbit at compile time (unconditionally), but
at runtime the IF body may be skipped. This creates a mismatch: code
after THEN would use the wrong register assignment for the not-taken path.

The solution: **sync at join points.** Every flow control word that
creates a join point (THEN, ELSE, BEGIN, AGAIN, REPEAT) calls `_rst`
before emitting code. This inserts `xchg rbx,rdx` on the taken path
if the SWAPbit was toggled, ensuring both paths arrive at the join
point with the same register assignment (SWAPbit=0).

Note: `xchg` does not affect FLAGS, so the _rst sync is safe even in
the flags-based conditional path.

---

## Part 8: The Trailing-Comma Literal Compiler

### Why this matters

In the original FreeForth, most inline code generators are **not** written
in assembly. They're Forth words — "backtick macros" — defined in ff.boot.
For example, `nipdup` is defined as:

```forth
: nipdup` $DA89, s09 ;        ( i386: mov edx, ebx — 2 bytes )
```

This single line replaces what would otherwise be an assembly routine.
Lavarenne kept the assembly kernel minimal and built the rest in Forth.
To port ff.boot to ff64.boot, we need the same mechanism in the 64-bit
port.

### The trailing-comma syntax

When the compiler encounters a number token ending with `,`, it doesn't
push the number as a literal. Instead, it calls `litcomma`, which emits
a `mov [rbp], value` instruction into the code being compiled. When that
code later runs (as part of a macro), it writes the value's bytes at the
current compilation pointer — but does NOT advance it.

This is the secret: **litcomma writes bytes, s01/s08/s09 advance past
them.** The separation allows the SWAPbit fixup to happen in exactly
the right place.

### Size selection

The literal compiler chooses the smallest instruction:

| Value | Instruction emitted | Machine code |
|-------|-------------------|--------------|
| `$48,` (≤ $FF) | `mov byte [rbp], $48` | C6 45 00 48 |
| `$DA89,` (≤ $FFFF) | `mov word [rbp], $DA89` | 66 C7 45 00 89 DA |
| `$04C38348,` (≤ $FFFFFFFF) | `mov dword [rbp], $04C38348` | C7 45 00 48 83 C3 04 |

### i386 vs x86-64 difference

In i386, `mov edx, ebx` is 2 bytes: `89 DA`. One litcomma and one `s09`.

In x86-64, `mov rdx, rbx` is 3 bytes: `48 89 DA`. The REX prefix ($48)
must be emitted separately:

```forth
: nipdup  $48, ,1  $DA89, s09 ;     ( x86-64: 48 89 DA — 3 bytes )
```

- `$48,` — litcomma writes the REX prefix byte at [rbp]
- `,1` — advance rbp by 1 (no SWAPbit action on the REX byte)
- `$DA89,` — litcomma writes the opcode + ModR/M at [rbp]
- `s09` — advance rbp by 2 AND apply SWAPbit to the ModR/M byte

### The SWAPbit helpers

| Word | Action | Use |
|------|--------|-----|
| `s09` | advance 2, XOR [rbp-1] with $09 | Both reg fields (most ops) |
| `s08` | advance 2, XOR [rbp-1] with $08 | Source reg field only |
| `s01` | advance 2, XOR [rbp-1] with $01 | Dest reg field only |
| `s1` | advance 1, XOR [rbp-1] with $01 | Single-byte opcodes |
| `,1` through `,4` | advance N, no XOR | Fixed bytes (REX prefixes) |
| `s09.` | `,1` + `s09` = advance 3, XOR $09 | x86-64: REX + op + ModR/M |
| `s08.` | `,1` + `s08` = advance 3, XOR $08 | x86-64: REX + op + ModR/M |
| `s01.` | `,1` + `s01` = advance 3, XOR $01 | x86-64: REX + op + ModR/M |

The 3-byte dotted variants (experiment 152) compose `,1` with the
2-byte adjuster, matching the stride of REX-prefixed register ops.
They allow the REX byte to be packed into the litcomma value:

```forth
\ Before (x86-64): 2 litcomma calls
: nipdup` $48, ,1 $DA89, s09 ;

\ After: 1 litcomma call
: nipdup` $DA8948, s09. ;
```

On i386, `s09.` is aliased to `s09` (no REX prefix, 2-byte stride).
**Caution**: shared macros using `ext` must NOT use dotted adjusters —
`ext` already includes `,1`, so `ext ... s09.` double-advances.

The XOR values correspond to the bit positions that encode rbx vs rdx
in the x86 ModR/M byte: bit 0 flips the r/m field (dest), bit 3 flips
the reg field (source), and $09 = both.

## Part 9: Backtick Name Mangling and Forth-Defined Macros

### The backtick dispatch mechanism

FreeForth's compiler has a unique approach to compile-time macros: it
uses word naming conventions instead of special flags or syntax. When
the compiler encounters any word during compilation, it first appends
a backtick character (`\``) to the word and searches the dictionary.

```
User writes:    dup          (inside a definition)
Compiler tries: dup`         (appends backtick)
Found?          YES → execute immediately (emit inline code)
                NO  → try "dup" normally (compile a call)
```

This means ANY word can have a compile-time macro variant. You just
define a word with a backtick suffix. The compiler's name mangling
makes the connection automatically.

### How it works in the compiler

```nasm
lea rdi, [rax + rcx]    ; point past end of word
push qword [rdi]        ; save whatever byte is there
push rdi
mov byte [rdi], '`'     ; temporarily append backtick
inc ecx                 ; increase length
call _find              ; search dictionary
pop rdi
pop qword [rdi]         ; restore original byte
jc .no_backtick         ; not found → try without backtick
call rax                ; found → execute the macro
jmp _compiler           ; continue
```

The trick: the input buffer is modified in-place (temporarily overwriting
the byte after the word with a backtick), then restored. This is a
zero-allocation search — no string copying needed.

### Defining Forth macros

A backtick macro is just a regular word (ct=0) whose name ends with
backtick. When called, it emits machine code using litcomma and the
SWAPbit helpers:

```forth
: under` $F87F8D4D, ,4  $49, ,1  $1789, s08 ;
: nip`   $49, ,1  $178B, s08  $087F8D4D, ,4 ;
: nipdup` $48, ,1  $DA89, s09 ;
: drop`  swap` nip` ;
: dup`   under` nipdup` ;
: over`  under` swap` ;
```

When `dup`` is defined, the compiler sees `under`` and `nipdup`` as
plain ct=0 words and compiles calls to them. When `dup`` later
EXECUTES (because the compiler found it via backtick search), those
calls run and emit inline code:

1. `under`` emits 7 bytes: `lea r15,[r15-8]; mov [r15],rdx` (push NOS)
2. `nipdup`` emits 3 bytes: `mov rdx,rbx` (copy TOS to NOS)
3. Result: 10 bytes of inline `dup` code in the user's definition

### The one assembly primitive: `swap``

Almost all macros are defined in Forth, but `swap`` must be in
assembly because it modifies the compile-time SWAPbit state rather
than emitting code:

```nasm
_swap_inline:
    xor byte [SC], 2    ; toggle SWAPbit
    ret
```

This is what makes `swap` "zero-cost" — it emits no code at all.
The compiler just remembers that TOS and NOS registers are
conceptually swapped, and subsequent code generators account for it.

### Restoring Lavarenne's compiler loop (exp 090)

The x86-64 port's compiler originally had five hardcoded keyword checks
before the backtick/dictionary lookup path. When the compiler read a
token, it checked:

1. Is it `;`? → call `_semi` directly
2. Is it `:`? → call `_colon` directly
3. Is it `variable`? → call `_variable` directly
4. Is it `constant`? → call `_constant` directly
5. Is it `include`? → call `_include` directly

Only if all five checks failed did it proceed to the backtick name
mangling and dictionary lookup that Lavarenne designed.

Lavarenne's original ff.asm compiler (lines 1063-1089) has none of these
fast-paths. Its loop is pure and simple:

```
wsparse → append backtick → find → dispatch by ct
                                → OR strip backtick → find → dispatch by ct
                                → OR literalcompiler
```

Every word — including `;`, `:`, `variable`, `constant` — is found via
dictionary lookup. `;`` and `:`` are ct=2 backtick macros in the
dictionary. `variable`` and `constant`` are Forth definitions in ff.boot.
No special cases.

This is a core Lavarenne principle: the compiler is *uniform*. It treats
every word the same way. The dictionary IS the dispatch mechanism. Adding
keyword fast-paths undermines this uniformity and creates maintenance
burden — as proven by the anon-flush bug (exp 089), where the assembly
`_variable` didn't flush pending anonymous blocks but the Forth
`variable`` definition (via `:`` → `_colon` → `_semi`) would have.

Experiment 090 removed all five fast-paths (197 lines of assembly) and
moved the `create``, `variable``, and `constant`` Forth definitions
earlier in ff64.boot so they're available before first use. The compiler
loop now matches Lavarenne's design exactly.

### The `\` comment fix

The `\` comment word originally set the input pointer to the end of
the buffer. This broke when input was piped (multiple lines read in
one sys_read call). Fixed to scan forward to the next newline only.

### Restoring the comparison factory (exp 091–092)

**Exp 091** removed 13 ct=2 WORD64 entries for stack/arithmetic words
(`dup`, `drop`, `swap`, `over`, `nip`, `rot`, `tuck`, `negate`, `+`,
`-`, `*`, `@`, `c@`) and their dead assembly routines. These were
redundant because the compiler always found the backtick version first.

**Exp 092** replaced all 34 comparison WORD64 entries and ~70 lines of
assembly with Lavarenne's elegant factory pattern from ff.boot:

```forth
: 0-` $48, ,1 $DB85, s09 ;          \ test rbx,rbx (i386: $DB09,)
:. _?1 ?# c! ;                       \ store Jcc opcode
:. _?2 _?1 $48, ,1 $DA39, s09 ;     \ store Jcc + cmp rdx,rbx
$74 dup : 0=`  lit _?1 ; : =`  lit _?2 ;
$75 dup : 0<>` lit _?1 ; : <>` lit _?2 ;
$7C dup : 0<`  lit _?1 ; : <`  lit _?2 ;
...
```

Each line in the factory defines two words simultaneously: a unary
condition (`0=\``) and a binary condition (`=\``). The `dup` before
the pair leaves the Jcc opcode for the second definition. `lit`
compiles the opcode as a literal push into the macro body — when the
macro later executes during user compilation, it pushes the opcode and
`_?1`/`_?2` stores it in `?#`.

The x86-64 differences are minimal: `0-\`` emits `48 85 DB` (test
rbx,rbx with REX prefix) instead of i386's `09 DB` (or ebx,ebx), and
`_?2` emits `48 39 DA` (cmp rdx,rbx) instead of `39 DA` (cmp edx,ebx).

**Carry flag conditionals (exp 127)**: `C1?\`` and `C0?\`` test the CPU
carry flag (JB=$72, JAE=$73) as unary conditions, sharing opcodes with
`u<\``/`u>=\``:

```forth
$72 dup : C1?` lit _?1 ; : C1?.` lit _?1. ;
$73 dup : C0?` lit _?1 ; : C0?.` lit _?1. ;
$72 dup : u<`  lit _?2 ; : u<.`  lit _?2. ;
$73 dup : u>=` lit _?2 ; : u>=.` lit _?2. ;
```

The `dup` shares one opcode between both consumers. Each `;` executes
the preceding anonymous definition, consuming one value. This is the
same sharing pattern as the signed comparisons — one `dup`, two
definitions. An early attempt with two `dup`s left extra items on
the compile-time stack.

**Dotted condition factories (exp 130)**: `_?1.`/`_?2.` produce Forth
booleans (-1/0) directly in a register, using SETcc. Each factory line
now defines up to four words — FLAGS and dotted, unary and binary:

```forth
$74 dup : 0=` lit _?1 ; dup : 0=.` lit _?1. ; dup : =` lit _?2 ; : =.` lit _?2. ;
```

The dotted factory helpers differ from i386 only in `_?1b.`:

```forth
\ i386:  :. _?1b. 1^ $20+ 8<< $49C1000F | ,            $CB89, ,1 s1 ;
\ x64:   :. _?1b. 1^ $20+ 8<< $48C1000F | here d! 4 allot $C9FF, ,2 $48, ,1 $CB89, ,1 s1 ;
```

Two differences: (1) i386 `dec ecx` is single byte `$49`; x86-64
`dec rcx` requires `48 FF C9` (REX.W). (2) i386 `,` stores 4 bytes
(cell=4); ff64 `,` stores 8 bytes (cell=8), so `here d! 4 allot` is
used for the exact 4-byte store.

**Condition validation (exp 130)**: `?@` fetches and zeroes `?#`;
`?nn` errors if no condition was set. `cond` chains them:

```forth
:. ?@ ?# c@ 0 ?#! ;
:. ?nn 0- ,"t^AC~" !"is_not_preceded_by_a_condition"
: cond ?@ ?nn 1^ ;
: cond. 0-` drop` 0<>` ;
```

`cond.` (no backtick — a plain word, not a macro) converts a stack
boolean to FLAGS for dotted flow control (`IF.``, `WHILE.`` etc.).

As part of exp 092, ff64.boot was comprehensively reordered to match
ff.boot's logical structure: infrastructure → defining words →
comparisons → flow control → runtime words.

WORD64 count dropped from 126 to 78 across experiments 090–092.

---

## Part 10: The Macro Library Grows (Experiments 024–029)

With the backtick mechanism stable, the work shifts from building
infrastructure to porting ff.boot's inline code generators. Each
macro teaches something about x86 encoding, the SWAPbit mechanism,
or FreeForth's design philosophy.

### Store operations and fall-through definitions (exp 024, restored exp 125)

FreeForth uses **fall-through definitions** — a definition that
doesn't end with `;` continues into the next definition's code:

```forth
: r>` over`
: dropr>` $5B, s1 ;
```

Here `r>`` executes `over`` then falls through to `dropr>``'s body.
The `:` starts a new named definition WITHOUT terminating the
previous one's code. This is how Lavarenne achieved code reuse
without the overhead of a call — `r>`` and `dropr>`` share the
`$5B, s1` instruction.

**Critical principle**: `:` does NOT close the previous named
definition. It only closes a pending *anonymous* definition. For
named definitions, `:` simply creates a new header pointing at the
current code emission address. The previous definition's code
continues seamlessly into the new one.

This principle also underlies `0;`/`;THEN`, `[IF]`/`[ELSE]`/`[THEN]`,
and all other multi-`:` definition groups in ff.boot.

The store operations use Lavarenne's **fall-through triads** — three
words defined on a single line, each building on the previous:

```forth
: over!`  swap` : tuck!`  2dup!`  nip` ; : !`  tuck!`  drop` ;
: overc!` swap` : tuckc!` 2dupc!` nip` ; : c!` tuckc!` drop` ;
: overw!` swap` : tuckw!` 2dupw!` nip` ; : w!` tuckw!` drop` ;
: over+!` swap` : tuck+!` 2dup+!` nip` ; : +!` tuck+!` drop` ;
: over-!` swap` : tuck-!` 2dup-!` nip` ; : -!` tuck-!` drop` ;
```

Reading the first line: `over!`` emits `swap`` then falls through
to `tuck!``'s body (`2dup!`` + `nip``). After `nip``'s `;`, the
next `:` creates `!``'s entry point. `!`` emits `tuck!`` (the code
just before it!) then `drop``. Five store variants × three access
patterns = 15 words, defined in 5 lines with shared code throughout.

During the initial port, these chains were broken into standalone
definitions because we didn't understand `:` fall-through semantics.
Experiment 125 restored them.

### The xchg [r15] rotation trick (exp 024)

Rotation on a register-based stack is surprisingly elegant:

```forth
: -rot` swap`
: >rswapr>` $49, ,1 $1787, s08 ;
: rot` >rswapr>` swap` ;
```

`xchg rdx, [r15]` (3 bytes) exchanges the NOS register with the
third stack item. Combined with SWAPbit toggles:

- `rot` = xchg + swap`: exchange register with memory, then
  conceptually swap the two registers
- `-rot` = swap` + xchg: conceptually swap first, then exchange

### Return stack macros

On x86-64, the return stack IS the hardware call stack (rsp). The
inline `push`/`pop` instructions are only 1–2 bytes:

```forth
: dup>r` $53, s1 ;     ( push rbx/rdx, 1 byte )
: dropr>` $5B, s1 ;    ( pop rbx/rdx, 1 byte )
```

The `s1` helper advances rbp by 1 and conditionally XORs bit 0,
switching between `$53` (push rbx) and `$52` (push rdx), or
`$5B` (pop rbx) and `$5A` (pop rdx).

Reading without popping requires an addressing mode with the SIB
byte (because [rsp] requires it on x86-64):

```forth
: r` over` $48, ,1 $1C8B, s08 $24, ,1 ;   ( 48 8B 1C 24 = mov rbx,[rsp] )
```

### Load variants and addressing patterns (exp 025)

The fetch operations reveal how x86-64's ModRM byte encoding
interacts with the SWAPbit. The base pattern:

```forth
: @`  $48, ,1 $1B8B, s09 ;      ( 48 8B 1B = mov rbx,[rbx] )
: c@` $48, ,1 $0F, ,1 $1BB6, s09 ;  ( 48 0F B6 1B = movzx rbx,byte[rbx] )
```

The `s09` XOR toggles both bit 0 and bit 3 of the ModRM byte,
switching BOTH the source and destination registers simultaneously.
For `@``: `$1B` (mod=00, reg=rbx, r/m=rbx) becomes `$12`
(reg=rdx, r/m=rdx) — reading through NOS into NOS.

The `dup@`` variant preserves the address:

```forth
: dup@` over` $48, ,1 $1A8B, s09 ;
```

After `over`` copies the address, the fetch uses cross-register
addressing: `$1A` = mov rbx,[rdx] (read through NOS, result in TOS).

### The lit` literal compiler (exp 026)

`lit`` is the bridge between compile-time values and runtime code.
It takes a number from the compile-time stack and emits instructions
that push that number at runtime.

The implementation in ff64.asm uses three size paths:
- **Byte** (−128..127): `push imm8; pop rbx` = 3 bytes
- **32-bit** (positive ≤ $7FFFFFFF): `mov ebx, imm32` = 5 bytes
  (auto-zero-extends to 64-bit)
- **64-bit**: `mov rbx, imm64` = 10 bytes (REX.W + full 64-bit)

A critical bug was discovered: the internal `_s01`/`_s08`/`_s09`
functions use `mov ch, $XX` which clobbers bits 15:8 of rcx. The
lit` implementation initially stored the literal value in rcx — a
value of 1000000 became 983360 because the middle bytes were
corrupted. Fix: use r8 instead.

### Compilation emit macros — c,`, w,`, ,` (exp 027)

These macros store a value from a register to the compilation
pointer and advance it. They are the runtime counterparts of
litcomma.

```forth
: c,` $5D88, s08 $00, ,1 $C5FF48, ,3 drop` ;
```

This emits 6 bytes:
- `88 5D 00` = mov byte [rbp], bl (store byte from TOS)
- `48 FF C5` = inc rbp (advance compilation pointer)

On i386, `inc ebp` was 1 byte ($45). On x86-64, `inc rbp` is 3
bytes ($48 FF C5), making c,` grow from 4 to 6 bytes.

### The litcomma two-level insight

Understanding litcomma requires holding two levels in mind:

**Level 1 — Definition time:** When you write `$5D88, s08` in a
backtick macro definition, litcomma emits a `mov [rbp], imm`
instruction INTO the macro's body. This is code that will run
later (when the macro is invoked).

**Level 2 — Invocation time:** When the macro is later invoked
(during compilation of a user word), those mov instructions EXECUTE,
writing their immediate values at the USER's [rbp]. The s08 call
then adjusts the last written byte based on the current SWAPbit.

The litcomma's VALUE is the machine code being generated. `$5D88,`
doesn't mean "the number 0x5D88" — it means "the bytes 88 5D",
which is the x86 opcode for `mov [rbp], bl`. Litcomma is a
machine-code quoting mechanism.

### The >S0 word and register reconciliation (exp 028)

Some operations (like integer division) require specific registers
in fixed roles — `idiv rbx` divides rdx:rax by rbx. This conflicts
with SWAPbit, which may have TOS in rdx instead of rbx.

The `>S0` word resolves this: it tests SWAPbit and, if set, emits
`xchg rbx,rdx` (3 bytes on x86-64) to physically swap the
registers, then clears SWAPbit. After >S0, rbx IS TOS regardless
of prior SWAPbit state.

The `_rst` function in ff64.asm already implemented this logic
(used internally before CALL/RET instructions). Exposing it as
`>S0` required only a single dictionary entry.

### Division — /%` (exp 028)

Integer division is remarkably clean on x86-64:

```forth
: /%` >S0 $48D08948, ,4 $FBF74899, ,4 $C38948, ,3 ;
```

The 11-byte sequence:
- `48 89 D0` = mov rax, rdx (NOS → dividend)
- `48 99`    = cqo (sign-extend rax → rdx:rax)
- `48 F7 FB` = idiv rbx (rdx:rax / TOS)
- `48 89 C3` = mov rbx, rax (quotient → TOS)

The remainder lands in rdx (NOS) naturally. Contrast with i386,
which needed push/pop eax around the division to preserve the
data stack pointer.

### 3dup` — deep stack access (exp 028)

The i386 version used `push [esp+8]`, leveraging the hardware stack.
With r15, there's no single-instruction equivalent. Instead:

```forth
: 3dup` 2dup` $F87F8D4D, ,4 $18478B49, ,4 $078949, ,3 ;
```

After `2dup`` places copies of TOS and NOS on the stack, three
instructions copy the remaining deep item:
- `lea r15,[r15-8]`  — allocate one cell
- `mov rax,[r15+24]` — load the deep value (using rax as scratch)
- `mov [r15],rax`    — store at the new top

This bypasses SWAPbit entirely — rax is outside the TOS/NOS pair.

### String/memory copy — place` (exp 029)

The i386 place` is a masterclass in the two-level mechanism:

```forth
: place` $D189DF89, s08 s08 >C1 $5AA4F35E, ,3 s1 ;
```

The `s08 s08` sequence initially looks like a no-op (XOR twice on
the same byte cancels). But each s08 also advances the caller's rbp
by 2. The two calls advance past the 4-byte litcomma data in 2-byte
steps, each applying SWAPbit adjustment to its respective `mov`
instruction independently.

This is the macro body as a "program that writes programs" — the
litcomma deposits raw bytes, then s08 calls walk through those
bytes applying register adjustments based on compile-time state.

For x86-64, we use >S0 instead of per-instruction s08 adjustment:

```forth
: place` >S0
    $DF8948, ,3 $D18948, ,3 $378B49, ,3
    $08578B49, ,4 $10C78349, ,4 $A4F3, ,2 ;
```

The 19-byte sequence sets up rdi (dest), rcx (count), rsi (src from
[r15]), restores NOS from below, pops 2 cells from r15, then
executes `rep movsb`. Using >S0 is a pragmatic choice that trades
3 bytes (for the potential xchg) against complex SWAPbit choreography.

### Shift arithmetic (exp 029)

The shift operations scale cleanly from i386 to x86-64 — only a
REX.W prefix is needed:

```forth
: 2*` $48, ,1 $E3D1, s01 ;    ( shl rbx/rdx, 1 )
: 4*` $48, ,1 $E3C1, s01 $02, ,1 ;  ( shl rbx/rdx, 2 )
```

The s01 XOR on the ModRM byte switches between rbx (r/m=011) and
rdx (r/m=010), exactly as in i386.

Note that `4+`` (add 4) exists alongside `8+`` (add 8 = cell size).
On i386, `4+`` was the cell-size add. On x86-64, `8+`` fills that
role, but `4+`` remains useful for 32-bit offset arithmetic.

### Current state (after exp 029)

The ff64.boot file now contains ~93 inline code generators, covering:
- Stack: dup, drop, swap, over, nip, tuck, under, nipdup, rot, -rot,
  2xchg, 2dup, 3dup, 2drop, 2swap
- Arithmetic: +, -, *, /%, /, %, negate, ~, 1+, 1-, 2+, 4+, 8+, 8-,
  2*, 2/, 4*, 4/, 8*, 8/, &, |, ^, <<, >>
- Memory: @, c@, w@, cs@, ws@, dup@, dupc@, dupw@, !, c!, w!, +!, -!,
  tuck/over/2dup variants, @+, c@+, w@+, 2@, 2!
- Return stack: >r, r>, r@, 2r@, dup>r, dropr>, rdrop, 2rdrop
- String: place, cmove, bounds, bswap, flip
- Compilation: here, allot, c,, w,, ,, lit, off, on
- Composed: 2dup+, 2r>, 2dup>r, 2>r

---

## Part 11: Extended Arithmetic and the Parameterization Pattern (Experiment 030)

### The problem: double-cell arithmetic

Some operations need more precision than a single 64-bit cell.
The `*/` word (pronounced "star-slash") multiplies two numbers and
divides by a third, using a 128-bit intermediate to avoid overflow:

```
10 3 7 */    ( computes 10*3/7 = 4, no overflow even for large inputs )
```

This requires "mixed" multiply and divide operations that work with
double-cell (128-bit) values.

### Parameterized code generation

Lavarenne's most elegant pattern: signed and unsigned variants share
a single helper, with the caller passing raw opcode bytes:

```forth
: _m/mod >S0 $078B49, ,3 $08C78349, ,4 $48, ,1 w, $C38948, ,3 ;
: m/mod`  $FBF7 _m/mod ;    ( $FBF7 = F7 FB = idiv rbx )
: um/mod` $F3F7 _m/mod ;    ( $F3F7 = F7 F3 = div rbx  )
```

When `m/mod`` is invoked during compilation:
1. `$FBF7` pushes the signed divide opcode onto the stack
2. `_m/mod` runs, emitting setup code
3. `$48, ,1` writes a REX.W prefix at the compilation pointer
4. `w,` pops the opcode from the stack and writes it at [rbp]
5. More code follows for the cleanup

The `w,` word is the key — it's a runtime word (not a backtick macro)
that writes 2 bytes at the compilation pointer. It acts as a "splice
point" where caller-provided machine code gets inserted into the
emitted instruction stream.

This needed a new `w,` word in ff64.asm (the i386 kernel had one,
but the x86-64 port initially only had `c,` and `,`).

### The multiply helper

The same pattern serves multiplication:

```forth
: _m* >S0 $D08948, ,3 $48, ,1 w, $D38948, ,3 $C28948, ,3 ;
: m*`  $EBF7 _m* ;     ( $EBF7 = F7 EB = imul rbx )
: um*` $E3F7 _m* ;     ( $E3F7 = F7 E3 = mul rbx  )
```

After `imul rbx`, the 128-bit result is in rdx:rax. Two moves
distribute it: `mov rbx, rdx` (high → TOS), `mov rdx, rax`
(low → NOS). The order matters — rdx must be read before
it's overwritten.

### Scale operations as pure composition

With m* and m/mod as building blocks, */mod and */ are trivial:

```forth
: */mod` >r` m*` r>` m/mod` ;   ( a b c -- rem a*b/c )
: */` */mod` nip` ;               ( a b c -- a*b/c )
```

This pushes the divisor to the return stack, multiplies a*b to
get a double-cell result, retrieves the divisor, and divides.
Pure Forth composition, no assembly needed.

### Definition order in single-pass compilation

A subtle issue: `*/mod`` references `>r`` and `r>`` (return stack
macros), which must be defined earlier in ff64.boot. FreeForth's
single-pass model means the definition order in the boot file IS
the dependency order. The extended arithmetic helpers go near the
top (with the other arithmetic), but */mod` and */ must be placed
after the return stack section.

### Current state (after exp 030)

~103 words/macros ported. The ff64.boot macro library now covers
all the major categories from ff.boot except:
- Dictionary manipulation (pvt`, alias`, create`, variable`, constant`)
- State/control (execute, reverse`, [`, ]`, :^`)
- Extended flow control (conditional compilation, etc.)

---

## Part 12: Macro Composition and Utility Words (Experiment 031)

### The composition challenge

Up to now, our backtick macros have been "leaf" macros — each one
directly emits machine code bytes via litcomma. But Lavarenne's
FreeForth builds higher-level macros FROM simpler ones:

```forth
: 0;` 0-` 0=` IF` drop`
: ;THEN` ;;` THEN` ;
```

**Fall-through (restored in exp 127)**: `0;`` falls through to `;THEN`` — there
is no `;` after `drop``. When `0;`` executes, it emits test/conditional-jump/drop,
then falls directly into `;THEN``'s code which emits ret + patches the forward
jump. This is Lavarenne's original pattern; the ff64 port initially made `0;``
self-contained (calling `;THEN`` explicitly) because the fall-through semantics
of `:` were not yet understood.

This says: "define `0;` as a macro that, when invoked, calls `0-`
(emit test), `0=` (set condition), `IF` (emit conditional jump),
`drop` (emit drop code), and `;THEN` (emit ret + patch jump)."

The problem: `IF`, `THEN`, `0-`, and friends have ct=2 in our
dictionary. When the compiler encounters them during `0;``'s
definition, it executes them immediately — writing code into `0;``'s
body instead of compiling calls to them.

### The dual-name solution

The fix mirrors what Lavarenne's ff.boot implicitly achieves: each
compile-time primitive gets a second dictionary entry with an explicit
backtick in its name and ct=0:

```fasm
WORD64 "IF",  _if, 2, 2    ; user-facing: executed immediately
WORD64 "IF`", _if, 0, 3    ; macro-facing: compiled as a call
```

When the compiler processes `IF`` inside `0;``'s definition:
1. Backtick mangling tries `IF``` — not found
2. Normal lookup finds `IF`` — ct=0, compiled as `call _if`
3. Later when `0;`` runs, it calls `_if` which emits the conditional
   jump into the user's code

We added 21 such entries covering all conditions, comparisons, and
flow control words.

### Building `;;`` and `;THEN``

The `;;`` (double-semicolon) macro compiles a `ret` instruction:

```forth
: ;;` >S0 $C3, ,1 ;
```

`>S0` reconciles the SWAPbit state (emitting `xchg rbx,rdx` if
needed), then `$C3,` writes a ret byte via litcomma and `,1`
advances past it.

`;THEN`` combines `;; ` with forward-jump patching:

```forth
: ;THEN` ;;` THEN` ;
```

Note the use of `THEN`` (with explicit backtick) — the ct=0 entry.
Using `THEN` (ct=2) here would execute the THEN logic during `;THEN``'s
own compilation, not during the user's compilation. This was the source
of an early segfault that took careful analysis to diagnose.

### The 8-byte store bug

An early `;THEN`` implementation tried:
```forth
: ;THEN` ;;` here over - 4 - swap ! ;
```
This calculates the jump offset manually and stores it with `!`.
But `!` writes 8 bytes (a qword), while the JNZ instruction's rel32
field is only 4 bytes. The extra 4 bytes corrupt the instruction
stream. Using `THEN`` (which does proper 32-bit patching internally)
fixes this cleanly.

### Practical utility words

With the macro infrastructure working, we added useful runtime words:

**`type`** (addr n --) prints a string character by character:
```forth
: type BEGIN 0- 0> WHILE swap dup c@ emit 1 + swap 1 - REPEAT 2drop ;
```
This is pure Forth — no inline assembly, no macros. It demonstrates
that the compiler, flow control, and runtime primitives are all working
together for practical string output.

**`fill`** (addr n c --) uses triple rotation to maintain the fill
character, address, and count through a loop:
```forth
: fill rot rot BEGIN 0- 0> WHILE 1 - -rot 2dup c! 1 + rot REPEAT drop 2drop ;
```

**`reverse``** pops the return address and calls it — turning a
`call` into what's effectively a `jmp`. Same 3-byte encoding on
both i386 and x86-64: `pop rcx; call rcx` ($59 $FF $D1).

### Current state (after exp 031)

~121 words/macros ported. The macro library now includes composable
flow control macros (`;;``, `;THEN``, `0;``, `0<>;``, `?dup``),
string output (`type`, `count`), memory operations (`fill`, `erase`),
and the `reverse`` control flow primitive.

Next: dictionary manipulation words, state/control primitives, and
the remaining ff.boot infrastructure.

---

## Part 13: Flow Control Macros (Experiment 032)

### From flags to values: BOOL`

FreeForth's comparison system is FLAGS-based — comparisons set CPU
flags, and `IF`/`WHILE` consume them directly. This is efficient
(no extra instructions to convert flags to values) but creates a
gap: standard Forth idioms like `within` expect boolean values.

`BOOL`` bridges this:
```forth
: BOOL` 0 lit` IF` ~` THEN` ;
```

After any condition (`<`, `>`, `=`, `0=`, etc.), `BOOL` converts
the flags to a standard Forth boolean: -1 for true, 0 for false.

```forth
: t < BOOL . cr ;
3 5 t    \ prints -1
5 3 t    \ prints 0
```

### Long jumps vs short jumps

The original ff.boot uses short jumps ($EB, 1-byte offset) for
SKIP and ELSE. Our x86-64 port uses long jumps ($E9, 4-byte offset)
consistently. This trades 4 extra bytes per jump for simpler code —
no need for offset range checking or short-to-long promotion.

### CASE as a pattern

CASE` is elegant in its simplicity:
```forth
: CASE` =` drop` IF` drop` ;

: t
  1 CASE 65 emit ELSE
  2 CASE 66 emit ELSE
  67 emit drop
  THEN THEN cr ;
```

Each `CASE` tests equality and opens an IF body. `ELSE` continues
to the next case. The final default drops the switch key. Each
`CASE` consumes one `THEN` at the end.

### Current state (after exp 032)

~125 words/macros ported. The flow control macro system now includes
BOOL` (flags→boolean), SKIP` (unconditional jump), ELSE` (if/else),
and CASE` (switch/case pattern).

---

## Part 14: Peering Into the Dictionary (Exp 033)

### From assembly to Forth

Up to now, our dictionary has been opaque — words go in, headers are
created, but we had no way to inspect or modify them from Forth.
Experiment 033 opens the hood by exposing header layout constants
and accessor words.

### Header anatomy

Every word in the dictionary has a header that grows downward from
the header space pointer `H`:

```
offset 0:  xt     (8 bytes) — execution token (code address or value)
offset 8:  ct     (1 byte)  — compile-time flags
offset 9:  sz     (1 byte)  — name length
offset 10: nm...  (N bytes) — name characters + null terminator
```

The constants `h.ct` (8), `h.sz` (9), and `h.nm` (10) give these
offsets. Given a header address, you can reach any field:

```forth
H@ 8 + c@    \ read the ct byte of the most recent word
H@ 9 + c@    \ read the name length
H@ 10 + c@   \ read the first character of the name
```

### The suffix problem and our workaround

In the original i386 FreeForth, `H@` is not a defined word — it's a
single token parsed by the literal compiler's suffix mechanism. The
compiler strips the trailing `@`, finds `H` (a variable), and applies
fetch. This gives "free" compound words: `H@`, `h.ct+`, `anon!`, etc.

Our x86-64 port doesn't have this suffix mechanism yet, so we define
explicit helper words:

```forth
: H@ H @ ;         \ push the header pointer value
: anon@ anon @ ;   \ push the anonymous definition start address
```

### Modifying headers: ct|!

The `ct|!` word ORs a bitmask into a header's ct byte:

```forth
: ct|! 8 + dupc@ rot | swap c! ;   ( mask hdr-addr -- )
```

This is a beautiful example of FreeForth idiom. The `dupc@` macro
(which was itself defined using litcomma in Part 10) duplicates the
address and byte-fetches in one inline operation. The familiar
Forth sequence `rot | swap c!` does the read-modify-write.

### Marking words private

With `ct|!` in hand, `pvt'` is trivially:

```forth
: pvt` 8 H@ ct|! ;
```

Push 8 (bit 3), push the latest header address, OR it in. The
private bit prevents words from being visible in dictionary searches.

### The ct byte's many roles

The ct byte packs several flags:

| Bits | Meaning |
|------|---------|
| 0-2  | Compile class (0=call, 1=literal, 2+=compile-time) |
| 3    | Private flag (word hidden from search) |
| 5    | Alias flag ($20 = word is an alias) |

This is why tests mask with `7 and` (bits 0-2) or `8 and` (bit 3)
when checking specific flags.

### What comes next

With header access working, we can build the remaining dictionary
operations: `alias'` (create named aliases), `create'` (generic word
creation), and the bracket words `['` / `]'` for switching compiler
state. These are the building blocks for higher-level constructs like
structures, object systems, and the `:^'` push-address pattern.

### Current state (after exp 033)

~130 words/macros ported. 107 tests across 33 experiments, all passing.

---

## Part 15: Words That Make Words (Exp 034)

### The documentation goldmine

Before diving into dictionary operations, we went back to the source:
Christophe's own documentation in `docs/FreeForth.md`, `docs/FreeForth_Primer.md`,
and the comprehensive `ff.help` reference. These files explain the architecture
far better than reverse-engineering the assembly. Key insight: **read the docs
before reading the code.**

### execute — the simplest brilliant word

```forth
: execute >r ;
```

That's the entire definition. `>r` pushes TOS (an execution token) onto
the return stack, dropping it from the data stack. Then `ret` (compiled
by `;`) pops from the return stack — but instead of returning to the
caller, it jumps to the xt we just pushed. When that code returns, it
returns to whoever called `execute`. Two instructions, infinite power.

### How alias works — the _semi_exec mechanism

The defining words (`alias`, `constant`, etc.) need to receive values
that were computed by the preceding code. For example, in `42 constant answer`,
the constant `42` needs to be available when `constant` runs.

FreeForth's secret: `_colon` (the `:` word) calls `_semi_exec` before
creating a new header. This executes any pending anonymous code, putting
computed values on the data stack. So:

1. `42` is compiled as `push 42` into the anonymous area
2. `constant` triggers `_colon`, which calls `_semi_exec`
3. `_semi_exec` runs the anonymous code → 42 is on the stack
4. `_colon` creates a header for "answer"
5. The rest stores 42 as answer's xt value

This is why FreeForth doesn't need a separate `[']` or prefix `'` — the
natural flow of anonymous definition execution provides values to
compile-time words.

#### SWAPbit reconciliation in `_semi_exec`

A subtle bug was found: `_semi_exec` was missing a `call _rst` before
writing the `C3` (ret) byte. The `_rst` function checks the SWAPbit
and, if set, emits `xchg rbx,rdx` to reconcile register assignments
before the block returns.

Without `_rst`, backtick macros that leave SWAPbit=1 (like `here\``,
which uses `over\`` → `swap\``) would return with the value in the
wrong register. The next anonymous block, compiled with SWAPbit=0,
would read the wrong register.

Example: `here : dummy 42 ; . cr 0 exit ;` printed `0` instead of
a valid code address. The `here` value was correctly placed in rdx
(NOS, because SWAPbit=1), but `.` in the next anonymous block read
rbx (TOS, SWAPbit=0) which was 0.

The i386 original didn't have this bug because `_colon` called
`_semi` (which starts with `call _rst`), while ff64's `_colon`
called `_semi_exec` directly (skipping `_rst`). The fix: add
`call _rst` at the entry of `_semi_exec`.

### The ct mask bug

Testing aliases revealed a compiler bug: the ct dispatch used the raw
byte value without masking. With ct=$20 (alias flag), the compiler saw
"ct >= 2 → execute immediately" instead of "ct class 0 → compile as call."

The fix: `and ecx, 7` before dispatch, matching the i386 original. This
extracts only the compile class bits (0-2), ignoring flags in bits 3+.

### The literal compiler suffix mechanism

Reading `ff.help` revealed something we'd been working around: the i386
literal compiler has a suffix mechanism. Tokens like `H@`, `h.ct+`,
`anon!` are NOT defined words — they're parsed by the literal compiler:

| Token  | Suffix | Remaining | Action |
|--------|--------|-----------|--------|
| `H@`   | `@`    | `H`       | Find H → fetch from its address |
| `h.ct+`| `+`    | `h.ct`    | Find h.ct → add 8 to TOS |
| `$20!` | `!`    | `$20`     | Number 32 → store at TOS |

Supported suffixes: `@ ! + - * / % & | ^ , _`

Our x86-64 port handles only trailing `,` (litcomma). We define
explicit helper words (`H@`, `anon@`) as a workaround. The full
suffix mechanism is a future enhancement.

### Bracket state switching

```forth
: [` anon@ SC c@ anon:` ;
: ]` 2>r ;` 2r> SC c! anon ! ;
```

`[` suspends the current definition: saves the anonymous pointer and
compiler state, starts a fresh anonymous definition. `]` completes
and executes the anonymous definition, then restores the saved state.

This enables compile-time computation within named definitions:
```forth
: t [ 3 4 + ] . cr ;   \ [ ] computes 7 at compile time
t                       \ prints 7
```

### Current state (after exp 034)

~140 words/macros ported. 117 tests across 34 experiments, all passing.
The dictionary manipulation infrastructure is now functional: header
inspection, ct flag modification, execute, alias, constant, and
bracket state switching.

---

## Part 16: Number Output — The Fall-Through Pattern (Exp 035)

### A Beautiful Mechanism

The most elegant code in ff.boot is the number output chain. To understand
it, DG suggested disassembling the i386 compiled code — an invaluable
technique that reveals exactly what FreeForth generates:

```
$ echo "see _d" | ./ff
_d:
  ...
  call   _d              ; recursive call to self
  add    ebx,$30          ; .digit starts HERE — no ret!
  ...
  jmp    putc             ; .digit ends with tail call
```

The key insight: `_d` is defined without `;`. Its code ends with `call _d`,
and `.digit`'s code follows immediately in memory. When `_d` recurses,
each level pushes a return address pointing at `.digit`'s code. As the
recursion unwinds, digits print from most to least significant.

### Why It Works

FreeForth's compilation model makes this natural:
- `:.` creates a private header (`: + pvt`) — nothing special about flow
- No `;` means no `ret` is compiled
- The next `:` creates a new header at the current compilation pointer
- The new word's code IS the fall-through from the previous word

This isn't a hack — it's a consequence of FreeForth's design where the
compiler always compiles forward and `:` doesn't insert padding.

### The u> drop Pattern

FreeForth's FLAGS-based conditionals don't push booleans:
```forth
: .digit $30 + $39 u> drop IF 39 + ... THEN emit ;
```
- `$39` pushes a literal (shifting TOS down)
- `u>` sets CPU flags (NOS > TOS unsigned?) but doesn't modify stack
- `drop` removes the $39 literal
- `IF` uses the stored condition flag

This generates tighter code than standard Forth's boolean approach.

### From Assembly to Forth

The Forth `.` replaces ~35 lines of assembly `_dot` with ~12 lines of
Forth, gaining arbitrary base support for free:
```forth
: . .\ space ;              \ decimal by default
16 base! 255 . ;            \ prints "ff"
10 base! ;                  \ back to decimal
$DEADBEEF .x ;              \ prints "deadbeef"
```

**Running total:** ~155 words/macros ported. 132 tests across 35
experiments, all passing.

---

## Part 17: The Holy Grail — Flow Control in Forth (Exp 036)

Flow control is the heart of any compiler. In FreeForth, IF/THEN/ELSE and
the loop words are compile-time macros that emit machine code. Moving them
from assembly to Forth is the most significant step in honoring the
FreeForth philosophy: assembly is minimal, Forth does the rest.

### Short vs Long Jumps

The i386 FreeForth uses SHORT conditional jumps: `$7x rel8` (2 bytes total,
1-byte offset, ±127 range). The x86-64 uses NEAR conditional jumps:
`$0F $8x rel32` (6 bytes total, 4-byte offset, ±2GB range). This means:

| Aspect | i386 | x86-64 |
|--------|------|--------|
| Conditional | `$7x rel8` (2 bytes) | `$0F $8x rel32` (6 bytes) |
| Unconditional | `$EB rel8` (2 bytes) | `$E9 rel32` (5 bytes) |
| Offset size | 1 byte | 4 bytes |

The `$10 +` trick converts between the two encoding families: `$74` (JE short)
→ `$84` (JE near, after $0F prefix).

### How `cond` Works

The assembly condition words (`0=`, `<`, `>`, `=`, etc.) set `cond_jmp` to
a SHORT opcode like `$74` (JE). The Forth `cond` function:
```forth
: cond ? c@ 0 ? c! 1 xor ;
```
1. Read `cond_jmp` (via `?` which returns its address)
2. Clear `cond_jmp` to zero (one-shot)
3. XOR with 1 to INVERT the condition

Why invert? IF means "if true, execute the body." But the jump must skip
the body when the condition is FALSE. JE ($74) → JNE ($75). JL ($7C) →
JGE ($7D). XOR 1 flips the least significant bit, toggling between the
paired condition codes.

### The 32-bit Store Problem

Jump offsets are 4 bytes, but our cell size is 8 bytes. Standard `!`
writes 8 bytes. We need `d!` (dword store) to patch only 4 bytes:
```forth
: 2dupd!` $49 c, $89 c, $17 c, ;  \ mov [r15], rdx (32-bit)
: tuckd!` $41 c, $89 c, $1F c, ;  \ mov [r15], rbx (32-bit)
: d!`     2dupd!` nip` ;           \ store 32-bit and drop addr
```

### CASE with ;THEN

In the i386, CASE uses SHORT jumps that happen to skip exactly one `pop`
instruction (1 byte). Our LONG jumps need explicit resolution. The pattern:
```forth
: t  0 CASE drop 10 ;THEN
     1 CASE drop 20 ;THEN
     drop 99 ;
```
CASE compiles `=` + `drop` + `IF` + `drop`. The `IF` leaves a patch address
resolved by `;THEN` (which compiles a ret and patches the forward jump).

### BOOL and the Flags Protocol

`BOOL` normalizes a condition to 0 or -1. It requires a preceding
FLAGS-setting operation AND a condition recording:
```forth
: t 0- 0= BOOL ;     \ 0- sets flags, 0= records condition
: t 3 < BOOL ;       \ < sets flags AND records condition
```
The `0 lit'` inside BOOL preserves CPU flags because our stack adjustment
uses `lea r15,[r15-8]` (flags-preserving) rather than `sub r15,8`.

### The Payoff

~155 lines of assembly became 11 lines of Forth. The flow control words
are now transparent, inspectable, and modifiable from within Forth itself.
The compiler compiles its own control structures.

**Running total:** ~170 words/macros ported. 152 tests across 36
experiments, all passing.

---

## Part 18: Counted Loops — TIMES/LOOP (Exp 037)

FreeForth's TIMES provides efficient counted loops by placing the counter
on the return stack and using `dec [rsp]; js exit` at the loop top — a
tight two-instruction pattern that modern CPUs handle very efficiently.

### How It Works

```forth
5 TIMES r@ . LOOP    \ prints: 4 3 2 1 0
0 3 TIMES 1 + LOOP   \ result: 3
```

The counter starts at N and is decremented BEFORE the body runs. The body
sees r@ values from N-1 down to 0. When the counter goes negative
(JS = Jump if Sign), the loop exits and rdrop pops the counter.

### Generated Code Pattern

```
  push rbx to rstack        ; >r (TIMES)
loop_top:
  dec qword [rsp]            ; decrement counter
  js exit                    ; exit if negative (N iterations done)
  ... body ...
  jmp loop_top               ; backward jump (LOOP)
exit:
  add rsp, 8                 ; rdrop (LOOP)
```

### TIMES/LOOP vs WHILE/REPEAT

**Important note (exp 127)**: `LOOP` is NOT an original FreeForth word — it
was invented during the ff64 port as a counted-loop terminator that combines
backward-jump + rdrop + THEN. Lavarenne's i386 FreeForth uses `REPEAT` for
both conditional and counted loops. Experiment 127 restored `.#s` to use
`TIMES...REPEAT` (matching `ff.boot`), though `LOOP` remains available for
cases where it was defined during the port.

| Pattern | When to use | Terminator |
|---------|-------------|------------|
| `BEGIN ... WHILE ... REPEAT` | Conditional loops | REPEAT` |
| `N TIMES ... REPEAT` | Counted loops (Lavarenne's original) | REPEAT` |
| `N TIMES ... LOOP` | Counted loops (ff64 port addition) | LOOP` |

### The SWAPbit Ordering Fix

A subtle bug: `>r'` toggles the SWAPbit (because it includes `dup>r'` which
calls `s1`). Placing `>S0` before `>r'` normalizes SWAPbit, then `>r'`
un-normalizes it, causing wrong register usage in the body. Fix: normalize
AFTER `>r'`:
```forth
: TIMES` >r` >S0 here ...    \ >S0 after >r`, not before
```

**Running total:** ~175 words/macros ported. 164 tests across 37
experiments, all passing.

---

## Part 19: Utility Words and a Critical Bugfix (Exp 038)

### The ct=1 Compiler Bug

While implementing `words` (dictionary listing), we discovered a bug that
silently corrupted the compile-time stack. Any ct=1 word (constant, TRUE,
FALSE, bl, noop) used inside a colon definition would overwrite the
compile-time TOS with its value. This destroyed flow control addresses
saved by BEGIN, IF, TIMES, etc.

The root cause was a single instruction in the compiler's `.compilelit`
handler:
```asm
.compilelit:
        mov rbx, rax        ; ← BUG: overwrites compile-time TOS!
        call _lit_compile
```

`_lit_compile` only uses rax (which already has the value from `_find`).
The `mov rbx, rax` was leftover from an earlier design. Removing it fixed
the bug. Numeric literals were unaffected because they go through a
different code path (`_number` → `_lit_compile`) that doesn't touch rbx.

### Hex Output

```forth
: .#s TIMES dup r@ 4* >> $F and .digit LOOP drop ;
: .b 2 .#s ;
: .w 4 .#s ;
```

`.#s` uses the TIMES/LOOP counted loop with `r@` to select nibbles from
most-significant to least-significant. Each nibble is masked with `$F and`
and passed to `.digit` for output.

### Dictionary Listing

The dictionary is a contiguous block of entries growing downward from a
sentinel. Each entry: xt(8) + ct(1) + sz(1) + name(sz) + NUL(1).

```forth
: h.next dup h.sz + c@ h.nm + 1 + + ;   \ stride = sz + 11
: h.name dup h.nm + over h.sz + c@ type space ;
: words H@ BEGIN dup h.sz + c@ 0- 0<> drop WHILE h.name h.next REPEAT drop cr ;
```

`words` walks upward from H@ (latest entry), printing names until the
sentinel (sz=0). The sentinel's zero-length name causes `0- 0<>` to fail,
exiting the WHILE loop.

### Two sentinels in the header chain

The GENWORDS64 base case emits a single sentinel entry that serves two
purposes via two distinct fields:

1. **sz=0** — stops `words` and other header-walking loops. The
   `h.sz+ c@ 0- 0<>` test fails on zero-length names.

2. **ct=$FF** — stops `hidepvt` and `xhidepvt`, which walk headers to
   remove private (`:. `) definitions after compilation. These words
   check `dup h.ct+ c@ dup $ff-` — when ct equals $FF, the subtraction
   yields zero, terminating the scan. Without this sentinel, hidepvt
   would walk off the end of the header space.

The two stop conditions are independent: `words` checks sz, `hidepvt`
checks ct. Both hit the same physical sentinel entry but read different
fields.

### Debugging Technique: GDB

When the WHILE-based `words` crashed, we used GDB to disassemble the
generated machine code. This revealed `jmp 0x9` instead of a backward
jump to the loop top — the constant value 9 (from `h.sz`) had overwritten
the BEGIN address on the compile-time stack. Without GDB, this would have
been nearly impossible to diagnose from Forth alone.

**Running total:** ~183 words/macros ported. 151 tests across 38
experiments, all passing.

---

## Part 20: Debug Output (Exp 039)

### Depth Fix

The `depth` word had an off-by-one: it counted the NOS value that depth
itself pushed to the memory stack. Adding `dec rbx` after the division
fixed it. This is an x86-64-specific issue — the i386 version uses the
`xchg eax,esp` trick which handles the counting differently.

### The Recursive Stack Printer

`_s` is a clever recursive word that prints N stack items bottom-to-top:

```forth
:. _s 1 - 0; swap >r _s depth 0- 0= drop IF space THEN r> . ;
```

It works by peeling items one at a time onto the return stack, recursing
until the count reaches zero (`0;` exits when TOS is 0). Then as each
recursion level returns, it prints the saved item with `r> .`. The
`depth 0= IF space THEN` inserts an extra space at the point where the
real stack data begins, creating a visual separator:

```
 3;  0 0 0 0 0  1 2 3
                ^^ double space marks real data
```

### .h\` System State

`.h\`` shows free memory (KB between `here` and `H@`), the SWAPbit/
condition state byte (SC), and the full stack. In ff64, dictionary
entries grow downward from H@ while compilation grows upward from here,
so free space = `here H@ -` (positive when there's space remaining).

**Running total:** ~195 words/macros ported. 163 tests across 39
experiments, all passing.

---

## Part 21: Character Literals (Exp 040)

The compiler now recognizes `'X'` as a character literal. When the
compiler can't find a word (with or without backtick), it checks if the
token is exactly 3 characters with single quotes around a character.
If so, it extracts the ASCII value and compiles it as a literal.

This enables readable code like:
```forth
:. prompt space depth .\ ';' anon@ 0- 0= drop IF 1 - THEN emit space ;
```
instead of `$3B` for the semicolon character.

Limitation: `' '` (space character) doesn't work because the tokenizer
uses space as a delimiter. Use `$20` or `bl` instead.

**Running total:** ~195 words/macros ported. 171 tests across 40
experiments, all passing.

---

## Part 22: Vectors and Tick (Exp 041)

Vectors are the core extensibility mechanism in FreeForth. A vector word
starts with a `push imm32; ret` preamble (6 bytes). The push pushes the
body address onto the return stack, and ret jumps to it. To redirect a
vector, write a new target address at xt+1.

On x86-64, `push imm32` sign-extends the 32-bit value to 64 bits.
Since our code lives well below 2GB (~4MB), this works perfectly.

The `:^` macro: `: :^` :` $68, ,1 here 4+ 1+ d, $C3, ,1 ;`
- Creates the word header (`:`)
- Compiles push opcode ($68)
- Compiles the body address as a 32-bit value (here+5 via `4+ 1+`)
- Compiles ret ($C3)

New assembly words `d,`/`d@`/`d!` handle 32-bit dword operations needed
for the push operand. `d@` uses `movsxd` for sign-extended reads.

The `callmark` variable tracks the last compiled call instruction.
`-c` uses it to uncompile a call and recover the target xt. `'` (tick)
wraps this: `foo '` uncompiles the call to foo and compiles its xt as
a literal, making it available at runtime.

Also introduced `exp/test.sh` — a reusable test helper that simplifies
writing experiment Makefiles.

**Running total:** ~205 words/macros ported. 213 tests across 41
experiments (including the test helper retroactively covering earlier
experiments), all passing.

---

## Part 23: Tail-Call Optimization (Experiment 042)

With the vector infrastructure complete, we turned to a classic compiler
optimization that FreeForth i386 has always had: tail-call optimization.
When the last thing a definition does is call another word, the `call; ret`
sequence can be replaced with a single `jmp`, saving a stack frame.

The implementation was straightforward: in `_semi`, check if `callmark + 5
== here` (the last compiled instruction was a call right at the end of the
definition). If so, change the `$E8` opcode to `$E9` (jmp) and skip
compiling `$C3` (ret).

But this optimization exposed a subtle interaction with anonymous
definitions. In FreeForth, code typed at the interactive prompt is compiled
into an anonymous definition that `_semi` executes with `call rax`. If that
anonymous definition ends with `jmp` instead of `ret`, control never
returns to `_semi`. This caused the `reverse` word — which pops a return
address from the stack and calls it — to crash spectacularly.

The fix was elegant: only apply tail-call optimization when `[anon] == 0`,
i.e., inside a named definition. Anonymous definitions always get `ret`.
This matches the i386 behavior (which has additional guards via a `tailrec`
variable) and preserves correctness for words like `reverse` that depend on
the call/return stack discipline.

**Running total:** ~205 words/macros ported. 220 tests across 42
experiments, all passing.

---

## Part 24: Shifts and System Words (Experiment 043)

With the vector and tail-call infrastructure solid, we turned to practical
building blocks. Shift operations (`<<`, `>>`) follow the established
SWAPbit pattern: `mov ecx, ebx` copies TOS (shift count) to ecx, then the
shift instruction operates on NOS with a REX.W prefix for 64-bit width. The
key realization: `mov ecx, ebx` doesn't need a REX prefix because the shift
count only uses the low 6 bits.

We also exposed the parser's internal state as Forth words: `>in` (the parse
pointer) and `tp` (the input limit). These are DATA-type words (ct=1) that
push their address, enabling Forth-level input manipulation. We added `parse`
(scan for delimiter) and `lnparse` (parse to end of line) as assembly words,
and built `bye` (clean exit), `EOF` (skip rest of input), and `exit` (sys_exit
syscall) on top.

A subtle lesson: adding new words to ff64.boot can break existing tests that
depend on `H@` returning a specific word or that use names already taken.
The `bye` macro shadowed a test alias, and `EOF` became the new "last word"
in the dictionary, breaking tests that assumed otherwise.

**Running total:** ~215 words/macros ported. 236 tests across 43
experiments, all passing.

---

## Part 25: Structured Loops — START/ENTER/BREAK/END (Exp 044, 105)

FreeForth provides a second loop family alongside BEGIN/WHILE/REPEAT:
the **START/ENTER** structured loop, and the **BEGIN/CASE/BREAK/END**
multi-way dispatch. Understanding which openers pair with which closers
is essential:

- **BEGIN** pairs with everything: WHILE/REPEAT, UNTIL, AGAIN,
  CASE/BREAK/END
- **START** pairs with ENTER + looping closers (AGAIN, REPEAT)
- **END** only resolves forward refs — it does NOT emit a backward jump
- Backward jumps come exclusively from AGAIN, UNTIL, and REPEAT

### The i386 Design

On i386, all loop constructs share the `mrk` variable (2 cells):

- `mrk[0]`: backward target address (with SC bits packed in low 2 bits)
- `mrk[4]`: linked list of forward jumps (WHILE/BREAK chain)

BREAK compiles `$EB` (short jmp) + links into mrk[4]. END walks the
chain resolving all forward jumps, then restores mrk. Critically,
**i386 END does NOT compile the backward jump** — that's done by UNTIL
(= TILL + END), REPEAT (= backward jmp + END), or AGAIN.

The canonical multi-way dispatch pattern from Lavarenne's docs:
```
BEGIN v  1 CASE action1 BREAK  2 CASE action2 BREAK  default END
```

### The x86-64 Design (exp 044 → 105 evolution)

The port went through two phases. The original implementation (exp 044)
incorrectly had END emit a backward E9 jump, treating all loops as
looping constructs. This worked for START/BREAK/END but made
BEGIN/CASE/BREAK/END infinite-loop.

**Exp 105 corrected this.** The final design uses a compile-time stack
(cstack) for break addresses and a shared `_begin` helper:

**1. Shared opener: `_begin`** — saves old mrk (2 cells) to cstack,
pushes a 0 break-sentinel, stores `here` in mrk[0].

**2. Loop openers push a flag onto the data stack:**
- `BEGIN`: pushes 0 (no rdrop needed)
- `START`: pushes 0, emits forward E9, updates mrk to after the E9
- `RTIMES`: pushes -1 (rdrop needed) + JS fixup address

**3. Loop closers use mrk for backward jumps and cstack for breaks:**
- `AGAIN`: backward E9 to mrk. If TOS is nonzero (forward ref from IF),
  resolves it via THEN instead of tearing down loop infrastructure.
  Otherwise: resolve breaks, restore mrk, drop flag.
- `UNTIL`: conditional backward to mrk, resolve breaks, restore mrk
- `REPEAT`: backward E9. Calls `_resolve_fwds` to recursively resolve
  all forward refs (WHILEs and TIMES JS) on the compile-time data stack,
  stopping at the flag (0 or -1). Then: resolve breaks, restore mrk,
  conditional rdrop based on flag (-1 means TIMES loop needs rdrop).
- `END`: resolve breaks ONLY (no backward jump!), drop flag

**4. BREAK pushes to cstack, not mrk chain:**
```forth
: BREAK` >S0 $E9 c, 0 d, here 4- >cs _then ;
```
Compiles forward E9, pushes fixup to cstack, resolves preceding IF.

**5. Two recursive resolvers — one for each stack:**

`_resolve_breaks` pops the cstack until the 0 sentinel:
```forth
:. _resolve_breaks cs> 0; _then _resolve_breaks ;
```

`_resolve_fwds` resolves forward refs on the data stack while TOS is
positive (large address). Stops at the flag (0 = BEGIN, -1 = TIMES):
```forth
:. _resolve_fwds 0- 0> IF THEN` _resolve_fwds THEN ;
```

These mirror each other: `_resolve_breaks` iterates the cstack (for
WHILE/BREAK forward jumps), `_resolve_fwds` iterates the data stack
(for WHILE and TIMES JS fixups). The recursion handles any number of
WHILEs — triple WHILE (hanoi:58) works correctly.

### Why cstack instead of linked list?

The i386 linked list stores 1-byte relative offsets between break
addresses in the compiled code — elegant for SHORT jumps. On x86-64,
we use NEAR jumps (4-byte rel32), and storing offsets between 64-bit
addresses via the compiled code creates sign-extension issues. The
cstack approach is cleaner: break addresses go on a separate stack,
not tangled into the generated code.

### The patterns

```forth
\ Multi-way dispatch (no loop — END resolves, no backward jump):
: sign BEGIN 0-
  0< IF ."negative" BREAK
  0= IF ."null"     BREAK
       ."positive"
  END drop ;

\ Loop with early exit (AGAIN provides the backward jump):
: countdown 5 BEGIN 1- dup . space 0- 0= IF BREAK AGAIN drop cr ;

\ Loop with IF BREAK but no WHILE (REPEAT skips THEN resolution):
\ test.ff:28 — chkvals:  BEGIN depth 0; dropr> <> 2drop IF depth +r BREAK REPEAT
: countup 0 BEGIN dup 9 > 2drop IF BREAK 1+ REPEAT ;

\ START skips body on first entry (ENTER patches the forward jmp):
: repl START eval ENTER ok WHILE REPEAT ;

\ Counted loop (TIMES...REPEAT, flag=-1 triggers rdrop):
: hex .#s TIMES dup r 4* >> $F & .digit REPEAT drop ;
```

### GDB Marker Technique

Debugging generated code is challenging because there are no symbols
for Forth-compiled words. We developed a marker technique using r10
(an otherwise unused register on x86-64):

```forth
: M1` >S0 $41 c, $BA c, 1 d, ;   \ mov r10d, 1
: M2` >S0 $41 c, $BA c, 2 d, ;   \ mov r10d, 2
: int3` >S0 $CC c, ;              \ software breakpoint
```

Insert `int3` at the start of a word and markers before each macro:

```forth
: t int3 5 M1 START 1- dup . space 0- 0= IF M2 BREAK M3 END drop cr ;
```

Then under GDB: `gdb -batch -ex "run -f ff64.boot < test.ff" -ex "x/50i $rip" ./ff64_dbg`

The disassembly clearly shows `mov $0x1,%r10d` before START's code,
`mov $0x2,%r10d` before BREAK, `mov $0x3,%r10d` before END — making
it immediately obvious which macro generated each section.

For i386, the `see` word provides similar capability without markers:
`see wordname` disassembles any compiled word with symbolic call targets.

**Running total:** ~220 words/macros ported. 245 tests across 44
experiments, all passing.

---

## Part 26: Dictionary State Save/Restore — mark/marker

### The Problem

When developing Forth code interactively, you often want to "undo"
definitions — redefine a word after discovering a bug, or load a
file repeatedly during development. `mark` and `marker` provide this
by saving the dictionary state and later restoring it.

### How `mark` Works

`mark foo` creates a word `foo` in the dictionary. When `foo` is called,
it restores the dictionary to the state it was in when `mark foo` was
executed — all words defined after `foo` (including `foo` itself) are
forgotten.

Two things must be restored:
1. **`here`** (compilation pointer, rbp) — restored via `allot` with a
   negative argument
2. **`H`** (dictionary header chain pointer) — restored by walking
   headers until finding the marker's own entry

### Implementation

```forth
:. _mark ;` r> 5 - here - allot anon:`
  H@ BEGIN dup@ swap h.sz + c@+ + 1 + swap here = 2drop UNTIL H ! ;
```

Step by step:
- `;`` — end the current anonymous definition (needed because `mark` is
  a compile-time word that uses `;``)
- `r>` — pop the return address from the call to `_mark`
- `5 -` — back up to the `call _mark` instruction (call = 5 bytes)
- `here -` — compute how far here has advanced since the marker was created
- `allot` — subtract that amount, restoring `here` to its saved value
- `anon:\`` — reset the anonymous definition state
- The `BEGIN...UNTIL` loop walks headers from H@ via h.next, comparing
  each header's xt with `here`. When they match, that header is the
  marker itself, and H is set to the NEXT header (forgetting the marker
  and everything after it)

### h.next — Walking Headers

Headers grow downward from the top of the dictionary. Each header is:
```
offset 0: xt (8 bytes)     — execution token (code pointer)
offset 8: ct (1 byte)      — compilation type
offset 9: sz (1 byte)      — name length
offset 10: name (sz bytes) — null-terminated name string
```
Total header size = sz + 11. `h.next` = header + h.sz + c@+ + 1 +
(read sz byte, add to current address, skip null terminator).

### FLAGS Preservation Through `2drop`

A critical detail: `=` in FreeForth sets CPU FLAGS but does NOT modify the
data stack. After `here =`, both comparison operands (xt and here) are
still on the stack. `2drop` removes them. But `UNTIL` needs the FLAGS
from `=` to survive through `2drop`.

This works because `drop` generates:
```
mov rbx, rdx           ; move doesn't affect FLAGS
mov rdx, [r15]          ; memory load doesn't affect FLAGS
lea r15, [r15+8]        ; LEA doesn't affect FLAGS (unlike ADD)
```
All three instructions are flags-preserving. `2drop` = two drops = still
flags-preserving. This is a deliberate design choice in the x86-64 port —
using LEA instead of ADD for the stack pointer adjustment.

### Three Bugs and Their Lessons

This experiment revealed three bugs in the interaction between runtime
execution and compile-time machinery:

1. **`_dotstr_rt` register clobbering** — The `write` syscall used rdx
   (NOS register) as the byte count parameter, silently destroying the
   second stack item. Fix: save/restore rdx and rbx around the syscall.

2. **`_semi` missing empty-check** — When `_mark` calls `;\`` at runtime,
   `_semi` must detect that the anonymous definition is empty and skip
   execution. Without this check (which i386 has), `_semi` overwrote
   currently-executing code. Fix: check `[anon] == rbp` before proceeding.

3. **FLAGS-based comparison stack semantics** — Comparisons in FreeForth
   only set CPU flags; they don't modify the stack. After `= WHILE`, the
   comparison operands are still on the stack. Must explicitly drop them.

### `create` and `variable`

These simpler dictionary words were also validated:

- `create name` — defines a word that pushes the address of the memory
  immediately following the definition (`here` at define time)
- `variable name` — `create` + allocate 8 bytes, initialized to zero
- `allot` — advance `here` by n bytes (used with `create` for buffers)

**Running total:** ~220 words/macros ported. 226 tests across 45
experiments, all passing.

---

## Part 27: -call, Postfix Tick, and Vector Manipulation

### Postfix Tick — `'` (tick)

Standard Forth uses prefix tick: `' word` pushes word's execution token.
FreeForth uses POSTFIX tick: `word '` — first the compiler compiles
`call word`, then `'` uncompiles that call and replaces it with a
literal push of word's xt.

```forth
: '` -call lit` ;
```

At compile time: `-call` checks if a call was just compiled (callmark
matches here). If so, it uncompiles the call (reads the displacement,
computes the absolute address, backs up 5 bytes). Then `lit`` compiles
that address as a literal.

### The -call Infrastructure

`-call` is the gatekeeper for call uncompilation:

```forth
:. -c here dup 4 - d@ + -5 allot 0 callmark ! ;
: -call callmark @ here = 2drop IF -c ELSE drop THEN ;
```

`callmark` is set by `_call_compile` (assembly) whenever a `call` is
emitted into compiled code. It stores the position AFTER the call
instruction (matching the i386 convention where `callmark == here`
means "a call was just compiled").

`-c` does the actual uncompilation:
1. `here` — current compilation pointer (right after the call)
2. `dup 4 -` — point to the rel32 displacement field
3. `d@` — read displacement (32-bit, sign-extended)
4. `+` — add displacement to here → absolute target address
5. `-5 allot` — back up 5 bytes (remove the call)
6. `0 callmark !` — clear callmark

### callmark Convention

A subtle but critical detail: `callmark` must be stored AFTER advancing
`rbp` past the call instruction. The i386 `POSTPN` macro does `add ebp,5`
THEN `mov [callmark],ebp`. If callmark is stored before advancing, it
points to the `$E8` byte (5 less than here), and the `callmark == here`
check always fails.

This same convention is used by `;;`` for tail-call optimization and
by `_semi` in the assembly.

### Conditional Call — `?`

```forth
: ?` -call 0; call, ;
```

`?` uncompiles the preceding call and re-compiles it only if the target
is non-zero. Used for conditional compilation patterns where a name
might resolve to zero (indicating "not available").

### Vector Operations — All Macros

With `-call` and `'` working, the full vector lifecycle is:

```forth
:^ greet ." hello" cr ;     \ define vector with default body
greet                        \ → "hello"
: hi ." hi" cr ;
hi ' greet !^                \ redirect greet to hi
greet                        \ → "hi"
greet x^                     \ call original body → "hello"
greet n^                     \ disable vector (nop)
greet                        \ → (nothing)
greet ^^                     \ reset to default
greet                        \ → "hello"
```

### Vector ops: i386 vs x86-64 — a lesson in porting philosophy

All six vector manipulation words are backtick macros in both
architectures.  This was not obvious during the port — an early version
made `^^`, `x^`, and `@^` into runtime words, reasoning that x86-64's
64-bit address space precluded the single-instruction encodings that
i386 uses.  That reasoning was wrong, and the path to correcting it
reveals something important about how FreeForth's compiler works.

#### The trap: instruction-level thinking

The i386 `^^` emits one machine instruction:

```
: ^^` -call $05C7, ,2 dup 1+ , 6+ , ;   \ mov dword [xt+1], xt+6
```

This `mov dword [abs32], imm32` packs both the destination address and
the value into a single x86-32 instruction.  On x86-64, there is no
equivalent — `mov [abs64], imm32` doesn't exist, because instruction
operands can't hold 64-bit absolute addresses.

The initial conclusion was: "no single instruction → can't be a macro →
must be a runtime word."  This led to `^^` taking an xt from the stack:

```forth
: ^^ dup 6+ swap 1+ d! ;         \ WRONG: runtime word, needs vec ' ^^
```

This broke the `-call` contract.  Users had to write `vec ' ^^` instead
of `vec ^^`, and `quit` needed `_top ' ^^ _top` — a departure from
i386 syntax.  The vector1.ff test suite (ported from i386) exposed the
problem: only 4 of 13 tests passed.

#### The insight: macros emit *code*, not *instructions*

A backtick macro's job is to resolve things at compile time and emit
whatever runtime code achieves the effect.  It doesn't have to emit the
*same instruction* as i386.  FreeForth's own `lit`` and `d!`` macros
are the building blocks:

```forth
: ^^` -call dup 6 + lit` 1+ lit` d!` ;
```

At macro expansion time (when the user writes `vec ^^`):
1. `-call` uncalls `vec`, recovering its xt onto the compile-time stack
2. `dup 6 +` computes the default body address (xt+6)
3. `lit`` emits a push of that address into the user's code
4. `1+` computes the target slot address (xt+1)
5. `lit`` emits a push of that address into the user's code
6. `d!`` emits an inline 32-bit store

The user's compiled code contains three operations — push, push, store
— where i386 had one.  But the *macro* still resolves everything at
compile time.  There is no function call, no dictionary lookup, no stack
gymnastics at runtime beyond the generated push/push/store sequence.

This is the same pattern `!^` already used successfully.  The mistake
was thinking `^^` was fundamentally different because its i386 version
used a different x86 encoding.

#### The six vector ops compared

**`!^` (set vector target):**

```
i386:  -call $1D89, s08 1+ , drop`      \ mov [xt+1], reg
ff64:  -call 1+ lit` d!`                 \ push(xt+1), d!(TOS)
```

Both get the xt via `-call`.  i386 emits `mov [xt+1], reg` — one
instruction that reads the value from whichever register SWAPbit
selects.  ff64 pushes `xt+1` as a literal, then compiles an inline
`d!` that takes the value from TOS at runtime.  Same effect: the
value on the data stack gets written to the vector's jump target.

**`@^` (fetch vector target):**

```
i386:  -call over` $1D8B, s08 1+ ,      \ mov reg, [xt+1]
ff64:  -call 1+ lit` $1B8B, s09          \ push(xt+1), mov ebx,[rbx]
```

i386 emits `mov reg, [xt+1]` to load the 32-bit target address into
a register.  ff64 pushes `xt+1` as a literal, then inlines the bytes
for `mov ebx, [rbx]` — a 32-bit fetch without the REX.W prefix, so
the result is zero-extended to 64 bits.  The `$1B8B` encoding *is*
the `d@` operation; there's no need for a named `d@`` macro to exist
in the dictionary — you can always inline the bytes directly.

**`^^` (reset vector to default):**

```
i386:  -call $05C7, ,2 dup 1+ , 6+ ,    \ mov dword [xt+1], xt+6
ff64:  -call dup 6 + lit` 1+ lit` d!`    \ push(xt+6), push(xt+1), d!
```

The i386 version is the most elegant — one instruction that writes a
constant to a constant address, both computed at compile time.  The
ff64 version generates three operations but achieves the same compile-
time resolution.  Both `xt+6` and `xt+1` are known when `^^` runs
(which is the user's compile time), so `lit`` bakes them into the
generated code as immediates.

This is used by `quit`:
```forth
: quit _top ^^ _top ;
```
`^^` uncalls `_top` and emits code to reset its jump target.  In i386
that's one MOV instruction.  In ff64 it's push/push/d!.  Either way,
`quit` compiles to inline code with no function call to `^^` itself.

**`n^` (nop a vector):**

```
i386:  -call nop ' lit` SKIP !^`        \ stores nop's xt at [xt+1]
ff64:  -call _nop swap 1+ d!            \ stores _nop's xt at [xt+1]
```

Both store nop's xt into the vector's jump target so that calling the
vector does nothing.  The challenge in ff64 is getting nop's xt inside
a backtick macro body.  In i386, `nop '` works because `'` is itself
a macro that uncalls the preceding `nop` — but in ff64, `'` inside a
backtick definition would execute at n^'s *definition* time, not at
macro expansion time.

The solution: a private constant.  `:. _nop ;` defines a callable
no-op, and `H@ @ constant _nop pvt` captures its xt.  Constants have
ct=$21, so when the compiler encounters `_nop` inside n^'s body, it
pushes the value as a literal.  The `swap 1+ d!` then runs on the
compile-time stack, writing nop's xt into the vector's target slot.

Note that n^'s `d!` executes at *compile time* — it modifies the
vector directly, unlike `^^` which emits runtime code.  This is
correct: `n^` always writes the same value (nop's xt), so there's no
need to defer the store to runtime.

**`x^` (execute vector body):**

```
i386:  -call 6+ dcall,                  \ call xt+6
ff64:  -call 6+ lit` >r`                \ push(xt+6), >r → ret jumps there
```

i386 emits a direct `call` to the body at `xt+6`.  ff64 can't easily
emit a 64-bit call (there's no `call abs64` encoding), so it uses the
return-stack trick: `lit`` pushes `xt+6`, `>r`` moves it to the return
stack, and the next `ret` jumps there.  The effect is a tail-call to
the body — same as i386's `call` but without the return address push
(so it's actually a jump, not a call).

**`'` (compile-time tick):**

```
i386:  -call lit`
ff64:  -call lit`
```

Identical on both architectures.  `-call` recovers the xt, `lit``
compiles it as a runtime literal.

#### What the port teaches

The vector ops illustrate a general porting principle: **port the
semantics, not the encoding.**  Every i386 vector macro resolves
addresses at compile time — that's the invariant.  The specific x86
instructions it emits are implementation details.  When those
instructions don't exist on x86-64, the answer isn't "make it a
runtime word" — it's "emit different instructions that achieve the
same compile-time resolution."

FreeForth's `lit`` and the backtick store/fetch macros (`d!``, `d@``,
`>r``) are the portable building blocks.  They abstract over the
instruction encoding, letting macros compose without knowing whether
the target is 32 or 64 bits.  The i386 versions bypass these
abstractions for efficiency (emitting raw MOV bytes), but the
abstractions are always available as a fallback.

**Running total:** ~225 words/macros ported. 234 tests across 46
experiments, all passing.

---

## Part 28: System Words and the _semi_exec Bug

### Exception Handling: catch/throw

FreeForth's exception handling is minimal but complete. `catch` wraps a word
execution in a safety net; `throw` unwinds back to it.

**catch ( xt -- exception )**

`catch` saves three things on the call stack:
1. The data stack pointer (r15)
2. The NOS register (rdx)
3. The previous exception frame pointer [xfp]

Then it sets `xfp` to the current rsp (marking the recovery point), drops
the xt from the data stack, and calls it. If the word returns normally,
`catch` cleans up the saved state and pushes 0 (no exception).

**throw ( exception -- )**

`throw` restores rsp from `xfp`, pops the three saved values (xfp, rdx, r15),
and executes `ret`. This returns directly to catch's caller with the exception
value still in TOS (rbx). The data stack is restored to its state at catch time.

```
: ok 42 . cr ;
ok ' catch . cr           \ → prints "42" then "0" (success)

: bomb 99 throw ;
bomb ' catch . cr          \ → prints "99" (exception value)

: inner 55 throw ;
: outer inner ' catch ;
outer . cr                 \ → prints "55" (propagates through call chain)
```

### I/O Primitives: write, read, accept, type

The I/O words are shared Forth definitions, not assembly. They call the
`syscall` word, which handles all register save/restore (including the
rcx/r11 clobber from the x86-64 `syscall` instruction) internally.

**write ( addr count fd -- written )**

Defined in ff2.boot with a bifurcated syscall number: `sys_write` is 4
on i386 and 1 on x86-64. The Forth definition selects the correct
number at compile time.

**type ( addr count -- )**

Defined in Forth as `stdout write drop`. Pushes fd=1, calls write,
drops the return value (bytes written).

**accept ( addr count -- n )**

A Forth vector: `:^ accept 0 read 0 max ;`. Calls `read` on fd 0
(stdin), then clamps the result with `0 max` so EOF or error returns 0
instead of a negative value. Being a vector (`:^`), it can be
redirected for custom input sources.

### The _semi_exec Allot Bug

This was a subtle and important bug in how anonymous code execution
interacted with memory allocation.

**Background:** In FreeForth, when you type `create buf 16 allot` at the
prompt, each word compiles into an anonymous definition. When `:` starts
a new definition, `_colon` calls `_semi_exec` to execute the pending
anonymous code. This anonymous code creates the `buf` header and advances
`rbp` by 16 bytes (via allot).

**The bug:** After executing the anonymous code, our `_semi_exec` was
resetting `rbp` back to `[anon]` — the START of the anonymous code area.
This effectively "forgot" that 16 bytes had been allocated for buf's data.
The next definition (`: t ...`) would compile its code starting at `rbp`,
which now overlapped with buf's data area.

**The i386 solution:** Lavarenne's original design has `_semi` fall through
to `_anon` after executing anonymous code. `_anon` does `mov [anon], ebp`,
capturing the post-execution `ebp` as the new anonymous definition start.
Since `allot` advanced `ebp`, the allocated space is preserved.

**The fix:** Instead of restoring `rbp` from a saved value, we now let
`rbp` keep whatever value it has after execution, then save it with
`mov [anon], rbp`. This matches the i386 fall-through pattern.

```
\ Before fix: buf data overwritten by t's code
create buf 16 allot
65 buf c!
: t 0 ;              \ t's code would overwrite buf!
buf c@ .              \ → garbage (77, 141, etc.)

\ After fix: buf data preserved
create buf 16 allot
65 buf c!
: t 0 ;              \ t's code compiled AFTER buf's 16 bytes
buf c@ .              \ → 65 ✓
```

This is a pattern that appears throughout FreeForth — the anonymous code
mechanism assumes that `rbp` accurately tracks all memory allocation.
Any operation that advances `rbp` (allot, create, variable) must have
its effects preserved across the anonymous→named transition.

**Running total:** ~230 words/macros ported. 243 tests across 47
experiments, all passing.

---

## Part 29: The Suffix Mechanism — Inline Optimization (Exp 048)

FreeForth's literal compiler suffix mechanism is one of its most
distinctive features. When the compiler encounters a token, it first
tries to find it as a word. If that fails, it checks whether the last
character is a recognized suffix (`+-*/%&|^,@!_`). If so, it strips
the suffix, parses the stem (as a number or ct=1 constant), and emits
optimized inline machine code instead of a function call.

### Why It Matters

Consider `5 +` vs `5+`:

- **`5 +`** generates: a literal push of 5 (10 bytes for DUP1 + mov),
  then a call to `+` (5 bytes). Total: ~15 bytes, two instructions,
  one function call.

- **`5+`** generates: a single `add rbx, 5` (4 bytes). Total: 4 bytes,
  one instruction, zero function calls.

For a language where most of the standard library is defined in Forth
(not assembly), this optimization is critical. The i386 ff.boot uses
suffixes 169 times — without them, the boot code would be significantly
larger and slower.

### The Dispatch Table

```
suffix_chars: "+-*/%&|^,@!_"
suffix_handlers: [_litadd, _litsub, _litmul, _litdiv, _litmod,
                  _litand, _litior, _litxor, _litcomma, _litfetch,
                  _litstore, _litnip]
```

The compiler walks `suffix_chars` comparing each character against the
last character of the token. If found, the index selects the handler.

### Arithmetic Suffixes (+, -, &, |, ^)

These all follow the same pattern:
1. Check if value fits in a signed byte (_lit8_64)
2. Emit `REX + opcode + ModR/M + imm8` (4 bytes) or
   `REX + opcode + ModR/M + imm32` (7 bytes)
3. Call `_s01` to handle SWAPbit — the instruction operates on rbx
   or rdx depending on SWAPbit state

The SWAPbit integration is subtle: `rbp` must be advanced past the
opcode bytes BEFORE calling `_s01`, because `_s01` XORs the byte at
`[rbp-1]` to flip the register encoding.

### Multiply (*)

Uses `imul reg, reg, imm` which has different encoding from add/sub.
The short form uses imm8 (4 bytes), the long form uses imm32 (7 bytes).
Uses `_s09` instead of `_s01` for SWAPbit because the ModR/M byte
encoding differs.

### Division (/) and Modulo (%)

These are the most complex suffixes. x86 division requires specific
registers (rax for dividend, rdx:rax for dividend pair, result in
rax with remainder in rdx). The generated code:

```
push rdx        ; save NOS
mov rax, rbx    ; dividend from TOS
cqo             ; sign-extend to rdx:rax
mov rcx, imm    ; divisor
idiv rcx        ; rax=quotient, rdx=remainder
mov rbx, rax    ; (/ takes quotient)
pop rdx         ; restore NOS
```

For `%`, the penultimate instruction is `mov rbx, rdx` (remainder).

### Fetch (@) and Store (!)

These work with variables and constants. `x@` where `x` is a ct=1
constant emits RIP-relative addressing:

```
DUP1            ; push data stack
mov rbx, [rip + disp32]  ; RIP-relative fetch
```

`x!` emits:
```
mov [rip + disp32], rbx  ; RIP-relative store
DROP             ; pop data stack
```

### Nip-Replace (_)

The `_` suffix replaces TOS without pushing: `99_` generates
`mov rbx, 99` (or `mov ebx, 99` for small values that zero-extend).
This is useful for replacing the top of stack with a constant.

### What Can't Use Suffixes

Variables (ct=0) cannot use the suffix mechanism. `mrk@` would need
to fetch from `mrk`'s *address*, but the suffix mechanism gets the
word's *value* (its xt). Since variables push their xt at runtime,
this doesn't give the right semantics. The convention is to define
explicit helper words: `: base@ base @ ;` `: base! base ! ;`

**Running total:** ~235 words/macros ported. 258 tests across 48
experiments, all passing.

---

## Part 30: Compile-time Stack and REPL Infrastructure

### The Data Stack Pollution Problem

FreeForth's `_exec` REPL uses `START ... ENTER` without a matching `END`.
This is intentional — the loop runs forever, with errors caught by `catch`.
But ff64's START was saving state on the *data stack*, and without END to
clean up, those values leaked permanently.

The i386 solution used a linked list threaded through jump-offset fields
in the generated code — elegant but dependent on 32-bit addresses fitting
in 32-bit offset fields. On x86-64, this trick fails because addresses
are 64 bits but `jmp rel32` offsets remain 32 bits.

### The Compile-time Stack (cstack)

The solution is a separate fixed-size stack for compile-time bookkeeping:

```nasm
cstack rq 16        ; 16 entries, 128 bytes
cstack_top:
csp    dq cstack_top ; grows downward
```

Two primitives `>cs` and `cs>` move values between the data stack and
the cstack. These are used by START, END, and BREAK:

```forth
: START` mrk 2@ >cs >cs 0 >cs $E9 c, 0 d, here mrk! ;
: BREAK` >S0 $E9 c, 0 d, here 4- >cs _then ;
: _resolve_breaks cs> 0; _then _resolve_breaks ;
: END`   >S0 $E9 c, mrk@ here 4+ - d, _resolve_breaks cs> cs> mrk 2! ;
```

START saves the old mrk (2 cells) and a 0 sentinel to cstack. BREAK
pushes each forward-jump address. END resolves all breaks (recursive
`_resolve_breaks` pops until hitting 0), then restores mrk.

BEGIN/WHILE/REPEAT/UNTIL remain data-stack based — they're self-contained
(BEGIN pushes, UNTIL/REPEAT consume) and don't leak.

### LEA for Flags Preservation

A subtle but critical design choice: ff64's data stack adjustments use
`lea r15,[r15±8]` instead of `add/sub r15,8`. The `lea` instruction
does not modify CPU flags, making it safe to interleave stack operations
with FreeForth's FLAGS-based conditionals:

```forth
0- 0<> drop WHILE   \ drop between condition and WHILE is safe
```

The `drop` compiles `mov rdx,[r15]; lea r15,[r15+8]` — neither instruction
modifies the flags set by `0-`'s `or rbx,rbx`.

### REPL Architecture

The Forth REPL (`_top`) is the only REPL. It matches i386's design:

- **`_top`**: `ui ... tib 4096 accept ... eval. catch` — read-eval-print loop
- **`ui`**: a vector (`:^`) defaulting to `prompt`, enabling customization
- **`prompt`**: prints ` N; ` where N is the stack depth

`_top` uses a `BEGIN ... AGAIN` infinite loop with `accept`. The
`accept` word does a bulk `0 read` (via the `syscall` word), reading
whatever data is available from stdin in one call. On EOF or error,
`accept` returns 0 (clamped by `0 max`), and `_top` calls `exit`.

Errors are caught by `catch`. If a throw occurs, `_recover` prints the
error and resumes the loop.

**Running total:** ~240 words/macros ported. 304 tests across 50
experiments, all passing.

---

## Part 31: REPL Auto-Execute and Compile-Time Macros (Exp 051)

### The Missing Piece: Auto-Execute

FreeForth's REPL has two layers. The **compiler** transforms tokens into
machine code. The **auto-execute** step runs that code. Without
auto-execute, typing `42 .` compiles the instructions but never executes
them — the result is silently discarded.

In the i386 original, `eval.` handles both: it calls `compiler`, then
`_auto`, which checks the `noauto` variable and triggers `;` to execute
the anonymous block via `_semi_exec`. The ff64 assembly REPL (`.repl` in
ff64.asm) called `_compiler` directly without the auto-execute step.
Named definitions worked because `;` in the source triggers `_semi`
internally, but standalone expressions were lost.

The fix adds 9 lines after `call _compiler` in `.repl_loop`:

```asm
mov rax, [anon]        ; load anonymous block start
test rax, rax          ; anon=0? (named def just ended)
jz .repl_ok            ; skip — no anonymous code
cmp rax, rbp           ; anon=rbp? (empty block)
je .repl_ok            ; skip — nothing compiled
call _semi_exec        ; execute the anonymous block
```

The logic: if `anon` is non-zero and differs from `rbp`, there's pending
anonymous code. `_semi_exec` compiles a `ret`, resets `rbp` to `anon`,
calls the block, and cleans up. This mirrors what `_auto` + `;` would do
in the Forth layer.

### Backtick Macro Calling Convention

FreeForth's compiler has a backtick lookup mechanism. For each token, it
appends a backtick and searches the dictionary. If `token\`` is found,
it's called immediately at compile time. This is how macros like `IF`,
`BEGIN`, `BREAK` work — their implementations are named `IF\``,
`BEGIN\``, `BREAK\`` etc.

The subtle implication: when **using** a backtick macro, you type the
name **without** the backtick. The compiler adds it. If you accidentally
type `IF\`` (with the backtick), the compiler appends another backtick,
looks for `IF\`\`` (double backtick), doesn't find it, and falls back to
compiling a regular CALL to `IF\`` — executing it at runtime instead of
compile time.

This applies to `int3\`` — the debug breakpoint macro. Define it as
`: int3\` >S0 $CC c, ;` (name includes backtick). Use it as `int3`
(no backtick) inside definitions:

```forth
: int3` >S0 $CC c, ;     ( define the macro )
: test int3 42 . cr ;     ( use without backtick — $CC inlined )
```

The compiler sees `int3`, appends backtick, finds `int3\``, calls it at
compile time. `int3\``'s body writes $CC at `[rbp]` (the current
compilation position), producing an inline breakpoint in the generated
code.

**Running total:** ~240 words/macros ported. 311 tests across 51
experiments, all passing.

---

## Part 32: Forth-based REPL (_top) (Experiment 052)

> **Note:** This part describes the *early* self-contained `_top`
> approach, which worked but diverged from Lavarenne's i386 design.
> Experiment 150 (Part 40) replaced it with the i386-aligned cross-word
> `START...UNTIL` coroutine pattern. Read this part for historical
> context on *why* the self-contained version was tried first.

The culmination of the REPL work: a self-contained Forth REPL that can
be launched from the assembly REPL.

### The i386 pattern and why it doesn't port

The original FreeForth REPL is an intertwined masterpiece. Three words
(`_eval`, `_exec`, `_top`) share a single `START`/`ENTER` loop that
crosses definition boundaries. `_exec` wraps `_eval` in `catch` for
error handling. `_top` handles input and prompt. The flow jumps between
them via `START`/`ENTER`/`TILL` constructs that would make a structured
programmer faint.

On x86-64, this pattern fails because `_eval` is the last named
definition before the unnamed `_exec`/`_top` code. After boot, the
compilation pointer (`rbp`) equals `_eval`'s code address. The assembly
REPL's auto-execute feature (exp 051) writes through `rbp`, destroying
`_eval`'s compiled code. When `_exec` later calls `_eval`, it crashes.

### The self-contained approach

The x86-64 `_top` is a single, self-contained `BEGIN`/`AGAIN` loop:

```forth
:^ _top pvt BEGIN
  ui 0 noauto!
  tib 4096 accept dup 0- 0= drop IF drop 0 exit THEN
  here saved_here! tib swap eval. ' catch
  dup 0- 0<> drop IF _recover ELSE drop THEN
AGAIN
```

Each iteration: show prompt → read input → save compilation state →
evaluate under exception protection → on error, recover and continue.

### Error flow: compiler → throw → catch → recover

**Without catch (assembly REPL):**
The compiler's `.error` handler checks `xfp`. If zero (no catch frame),
it prints `error: <word>\n` directly to stdout and continues. This is
the safe fallback — the assembly REPL never set up a catch frame.

**With catch (Forth REPL):**
`_top` wraps `eval.` in `catch`. The compiler's `.error` checks `xfp`,
finds it non-zero, and calls `_error` which pops the inline error message
("???") and falls through to `_throw`. `_throw` unwinds the call stack
to the catch frame, restoring the data stack. `catch` returns the error
message pointer as TOS (non-zero = error occurred).

### SEGV recovery

FreeForth catches segmentation faults and recovers to the REPL. This is
a two-layer system:

**Layer 1 — assembly handler (early boot):**
`_install_segv` installs `_segv_handler` via the raw `rt_sigaction`
syscall during `_start`, before any Forth code runs. This handler simply
prints "*** SEGV ***" to stderr and calls `exit(139)`. It's a safety net
for crashes during boot compilation.

**Layer 2 — Forth handler (after boot):**
During fflin64.boot compilation, `SEGVthrow` replaces the assembly
handler using libc's `sigaction()`:

```forth
create SEGVact pvt 152 allot      \ kernel_sigaction struct (BSS-zeroed)
:. SEGVhndlr !"SEGV caught" ;    \ throw with inline error message
SEGVhndlr ' SEGVact !            \ store handler xt at offset 0
$40000000 SEGVact 136+ !          \ SA_NODEFER at offset 136
:. SEGVthrow 0 SEGVact 11 3 "sigaction" libc_ drop ;
SEGVthrow                         \ install now
```

**How throw-from-signal-handler works:**
When SIGSEGV fires, the kernel saves the process state in a signal frame
on the stack and calls `SEGVhndlr`. The handler executes `!"SEGV caught"`
which does `call _error` (pops the inline string address into rbx) then
falls through to `_throw`. `_throw` does `mov rsp, [xfp]` — a longjmp-
style restore that completely replaces the stack pointer with the catch
frame's saved rsp. The signal frame is abandoned below the new rsp. The
REPL's `catch` receives the error message and calls `_recover`.

**SA_NODEFER** is required because throw doesn't return through
`sigreturn`. Without it, SIGSEGV would stay blocked after the first
throw, making subsequent segfaults fatal.

**x86-64 struct sigaction layout** (via libc, not kernel):
- handler: 8 bytes at offset 0
- sa_mask: 128 bytes (sigset_t) at offset 8
- sa_flags: 4 bytes at offset 136
- sa_restorer: 8 bytes at offset 144
- Total: 152 bytes (vs 140 on i386 where pointers are 4 bytes)

**Recovery (`_recover`):**
1. Shows input context: `tib >in@ over - type` prints everything from
   the input buffer start to where the compiler was parsing when the
   error occurred.
2. Shows error: `." <-error: " c@+ type cr` prints the counted error
   string ("???").
3. Drops the two items that `catch` restored to the data stack
   (`tib_addr` and `bytes_read` from before the eval.).
4. Dictionary cleanup: if `anon@ = 0`, a named definition was in
   progress — unlink it from the dictionary chain.
5. Code cleanup: restore `here` to its saved value, clear compiler state.

### The `eval. '` idiom

This is a FreeForth gem. `eval.` compiles a `call eval.` instruction.
`'` (tick) then uncompiles that call and pushes `eval.`'s execution
token as a literal. At runtime, the stack holds `eval.`'s xt, which
`catch` consumes and calls. The effect: `eval.` runs under `catch`'s
exception protection, with the call stack properly framed.

### Bulk-read accept

The byte-at-a-time assembly `accept` has been removed. The current
`accept` is a shared Forth vector:

```forth
:^ accept  0 read 0 max ;
```

This does a single bulk `read` on fd 0 (stdin). On piped input, all
available data lands in `tib` at once and the compiler processes it in
sequence — multi-line piped input works fine when there are no errors.

The trade-off: after an error or SEGV mid-stream, any remaining piped
input is lost (there is no per-line buffering to resume from). The
80-byte padding trick from older experiments (forcing each line to fill
exactly one `accept` call) is irrelevant with the bulk-read design.

### `-f` file `anon` reset (historical)

A subtle bug from the era when ff64 had an assembly REPL: after boot
(processing the first `-f ff64.boot`), `anon` was left at 0 because the
last definition (`_top`) used `:^` which calls `_colon`, which sets
`anon = 0`. This was fixed by resetting `anon = rbp` before compiling
each `-f` file. With the self-booting architecture (Exp 069), `-f` is
handled by Forth's `doargv` → `-f`` → `needed` → `eval`.

**Running total:** ~245 words/macros ported. 322 tests across 52
experiments, all passing.

---

## Part 33: Boot Sequence and Command-Line Access (Experiment 053)

### The boot architecture

FreeForth2's ff64 binary embeds a filtered copy of ff64.boot. At
startup, the assembly kernel compiles this embedded source, then
executes the final anonymous block `_boot ;`:

**Assembly layer** (`_start`):
1. Initialize registers and memory (rbp, r15, SEGV handler)
2. Save argc/argv for Forth access
3. Set tin/tp to the embedded boot source → call `_compiler`
4. Call `_semi_exec` to execute `_boot ;`

**Forth layer** (`_boot`):
1. `ossetup` — OS-specific initialization (currently empty vector)
2. `doargv` — evaluate command-line arguments (handles `-f`)
3. `_hidepvt` — hide private words from the dictionary
4. `_top` — enter the Forth REPL with prompt and error recovery

This mirrors how i386 ff works: the assembly kernel is minimal, with
all user-facing behavior (argument processing, REPL, error recovery)
implemented in Forth. The build system generates ff64.boot.min by
filtering out comments and blank lines:
```
grep '^[: _A-Za-z0-9]' ff64.boot > ff64.boot.min
```

### argc/argv access

On Linux, the initial stack at `_start` contains `argc` at `[rsp]` and
the argv array at `[rsp+8]`. These are saved to `ff_argc` and `ff_argv`
variables before the argloop processes `-f` files (which clobbers the
r12/r13/r14 registers that initially hold these values).

From Forth:
```forth
argc             \ ( -- n ) number of command-line arguments
0 argv type cr   \ prints program name (e.g., "./ff64")
1 argv type cr   \ prints first argument (e.g., "-f")
```

`_argv` computes `ff_argv + index*8` and fetches the pointer. `argv`
adds `zlen` to get the string length. The `8*` (8 bytes per pointer)
replaces the i386's `4*`.

### The hidepvt saga

**The bug:** The original ff64 `hidepvt` zeroed the name SIZE byte to
hide words. But `h.next` (which navigates between headers) uses the
size byte to compute step size. Zeroing it caused `h.next` to step
only 11 bytes instead of `11 + namelen`, misaligning all subsequent
header reads. The walk saw garbage as headers and eventually zeroed
random bytes throughout the header space.

**Why it wasn't caught earlier:** The experiment 049 tests passed because
the broken hidepvt happened to also corrupt the test's expected behavior
in a way that matched. The pvtmargin test expected `early` to be hidden,
which only happened because the corrupted walk hid everything.

**The fix (v1):** Zero the first name CHARACTER (`h.nm+`) instead of the
size (`h.sz+`). The size is preserved for navigation. `_find` won't
match any search because the first character is null — no valid Forth
word starts with a null byte.

**The fix (v2, Exp 071):** True compaction. Instead of just hiding names,
`_remove_hdr` physically removes private headers by shifting all newer
headers UP (toward higher addresses) by the removed header's size, using
the new `cmove>` (backward byte copy) assembly primitive. This reclaims
~485 bytes of header space. The algorithm:

1. Walk chain from H@ (newest). For each private header at `addr`:
2. Compute n = addr - H@ (bytes of newer headers to move)
3. `cmove> ( H@, H@+sz, n )` — slide newer headers up
4. H@ += sz (advance past the removed gap)
5. Return addr+sz as next scan position

The key insight: data AFTER the removed header doesn't move. The scan
pointer advances by sz to skip where the removed header was, landing on
the next (untouched) header. All newer headers shift into the gap.

Three debugging discoveries:
- ff64 has `r` (inline backtick macro) but NOT `r@` — use `r` instead
- UTF-8 characters in Forth comments cause parse errors
- `_remove_hdr` must return a scan position or the loop loses its place

### zlen: a subtle stack-effect difference

The i386 `zlen` has stack effect `( addr -- addr len )` — it preserves
the input address AND pushes the length. The original ff64 port had
`( addr -- len )` — it replaced the address with the length. This broke
any code that needed both, like `argv` which calls `_argv zlen` expecting
`( addr len )` for use with `type`.

**Running total:** ~250 words/macros ported. 333 tests across 53
experiments, all passing.

---

## Phase 3c: File I/O, Signal Handling, and File Loading

### File I/O primitives

Three new assembly words provide file I/O from Forth:

**`openr` ( addr len -- fd )**: Opens a file read-only. Copies the
filename to a separate `namebuf` buffer and NUL-terminates it (since
Linux `sys_open` needs a C string). Returns the file descriptor, or
a negative errno on failure.

**`close` ( fd -- result )**: Closes a file descriptor via `sys_close`.

**`loadfile`**: *Removed in experiment 141.* Originally a ~107-line
assembly routine that opened files, read into a private `filebuf`, and
called `_compiler`. Replaced by the i386 pattern: `needed` reads files
into `tib` (the shared source buffer) and calls `eval`. See Part 17
for the current file-loading architecture.

### The hereatexec mechanism (historical — removed in exp 141)

When `loadfile` was called from the REPL, it ran inside anonymous code
via `_semi_exec`. The problem: `_semi_exec` resets `rbp` to the start
of anonymous code before executing it. If `loadfile` compiled new
definitions at this `rbp`, they would overwrite the executing code.

The solution at the time was `hereatexec` — a variable where
`_semi_exec` saved `rbp` before resetting it. `_loadfile` used it as
the safe starting position.

**This was all unnecessary.** The i386 never had `loadfile` or
`hereatexec`. Investigation in experiment 141 revealed that the
`needs` backtick macro (`` ; wsparse needed ;` ``) does `;` first,
flushing anonymous code before `needed` runs. This prevents the
overwrite entirely. Both i386 and ff64 are "vulnerable" if `needed`
is called directly from anonymous code — but that's by design.

### The i386 boot sequence: a deliberate use of `needed` in anonymous code

The i386 `fflin.boot` ends with a subtle and deliberate construction
that appears to violate the `needed`-in-anonymous-code rule:

```forth
linsetup ' ossetup !^ _boot ' >r      \ line 60
"ff.ff" needed ' _exec ;              \ line 61
```

This is a single anonymous block. The sequence:

1. `linsetup` — call linsetup (patches SEGV handler, dlopen)
2. `' ossetup !^` — patch `_boot`'s first call to be `linsetup`
3. `_boot '` — **does not call `_boot`**. The `'` backtick macro
   converts the preceding `call _boot` into a literal push of
   `_boot`'s XT. This is a key parsing subtlety: `'` acts on the
   compiled call that precedes it, not on the next word.
4. `>r` — pushes `_boot`'s XT onto the return stack
5. `"ff.ff" needed` — loads ff.ff via `eval` (the dangerous call)
6. `' _exec` — pushes `_exec`'s XT as a literal (for `_boot`'s
   `catch` to use)
7. `;` — returns via `ret`, which pops `_boot`'s XT from the return
   stack and jumps there. `_boot` runs `ossetup doargv _top`.

The `needed` on line 61 **is** executing inside anonymous code at
`[anon]`. The `eval` inside `needed` calls `compiler`, which writes
new code starting at `[anon]` — overwriting the anonymous block being
executed. But by step 5, the CPU has already fetched and executed
instructions 1–4; the return continuation (`_boot`) is safely stashed
on the return stack, not in the anonymous code region. After `needed`
returns, `' _exec ;` compiles a literal and returns to `_boot`.

The anonymous code that gets overwritten (steps 1–4) has already
executed and is never revisited. Christophe engineered this: `' >r`
saves the continuation outside the overwrite zone. It is not an
accident — it is a careful one-shot trampoline.

**Parsing pitfall for analysis:** When reading `_boot ' >r`, it is
tempting to parse this as "call `_boot`, then `'` reads the next
token" — which would mean `_boot` executes (entering the REPL, never
returning) and `>r` never runs. The correct reading is: `_boot` emits
a call instruction, `'` converts that call into a literal, and `>r`
pushes it. `'` is a backtick macro that operates on the previously
compiled call, not a prefix parser. Understanding FreeForth's postfix
`'` is essential to reading boot sequences correctly.

### The loadfile rbp preservation rule (historical — removed in exp 141)

A deeper bug in the old `_loadfile`: after `_compiler` returned, the
code restored `rbp` to the anonymous code start, causing `_semi_exec`
to reset `[anon]` there and overwrite loaded definitions.

**Rule (no longer applicable):** `_loadfile` must NOT restore `rbp`
after `_compiler` returns. This entire class of bugs disappeared when
`_loadfile` was replaced by Forth `eval`.

### SEGV handler

The SEGV handler uses the `rt_sigaction` syscall (number 13) directly,
without any libc dependency. Three functions:

- `_segv_handler`: prints `"*** SEGV (segmentation fault) ***"` to
  stderr and exits with code 139 (128 + SIGSEGV)
- `_segv_restorer`: required on x86-64 for `SA_RESTORER` flag; calls
  `rt_sigreturn` (syscall 15)
- `_install_segv`: builds a `kernel_sigaction` struct on the stack and
  calls `rt_sigaction`; called early in `_start`

### The needed mechanism

`needed` (in ff64.boot) implements double-load guarding:

```forth
: needed 2dup + dup c@ >r dup >r $60 swap c! 1+
  find 2r> c! 0= IF 2drop ;THEN 1-
  2dup openlib 0- 0< IF 2drop type !"_not_found" ;THEN
  openr 0- 0< IF type !"_not_found" ;THEN
  >r 2dup marker pvtmargin 2drop
  tp@ eob over- under r read r> close drop
  over w@ [ "#!" drop w@ ] lit = 2drop
  IF bounds BEGIN c@+ 10- 0= drop UNTIL swap over- THEN eval 0 noauto! ;
```

It temporarily writes a backtick at the end of the filename, looks for
that name in the dictionary. If found (a previous `marker` created it),
the file is already loaded — skip. Otherwise, resolve the path via
`openlib`, open it, create a marker with the filename, read the file
into `tib` at `tp`, skip any shebang (`#!`) line, and `eval` the
contents.

### The find word

`find` (`_find_forth` in assembly) is a Forth-callable wrapper around
the internal `_find` function:

```forth
"dup" find . .    \ → 0 <xt>  (found: xt and 0)
"xyzzy" find . .  \ → 5 <addr> (not found: original addr and len)
```

### Running total

~270 words/macros ported. 416 tests across 65 experiments, all passing.

---

## Phase 3d: Command-Line Arguments (Experiment 066)

With `needed`, `eval`, and `find` in place, the system could load
files from Forth. But it still couldn't process command-line arguments
the way the i386 FreeForth did — where `ff -f myfile.ff` would load
`myfile.ff` through the Forth layer rather than the assembly stub.

### doargv — the Forth argument loop

The i386 `doargv` walks the argv array and feeds each argument to
the compiler:

```forth
:^ doargv argc 1- 0; 1 _argv swap 2+ _argv over- tuck tib place swap _eval ;
```

This is dense. Unpacked:

1. `argc 1-` — number of args minus the program name.
2. `0;` — if zero args remain, return immediately.
3. `1 _argv swap 2+ _argv over-` — compute the address and length of
   the remaining argument string (from argv[1] to the end).
4. `tuck tib place` — copy the argument string into `tib` (the terminal
   input buffer) so the compiler can parse it.
5. `swap _eval` — evaluate the string. `_eval` calls `eval.` (which
   compiles and auto-executes) followed by `'` (tick, to capture any
   resulting xt).

The key insight is that arguments are Forth source. `-f myfile.ff`
works because `-f` is recognized by the compiler, which looks up
`-f`` (backtick-appended), finding the compile-time macro:

```forth
: -f` ;` wsparse needed ;
```

This semicolons (exits the current compilation), parses the next word
(the filename), and loads it via `needed`. The beauty is that any
Forth expression can appear on the command line — not just `-f`.

### The _argv helper

```forth
:. _argv 8* ff_argv@ + @ ;
```

Takes an index, multiplies by 8 (pointer size on x86-64), adds to the
argv base pointer, and dereferences. Returns the C string pointer for
`argv[n]`.

### The boot sequence

With `doargv`, the full boot sequence is:

```forth
:. _boot ossetup doargv _hidepvt _top ;
```

1. `ossetup` — a vector (currently a no-op) for OS-level initialization.
2. `doargv` — process command-line arguments as Forth source.
3. `_hidepvt` — compact private words from the dictionary (Exp 071).
4. `_top` — enter the interactive REPL (infinite loop).

`_boot` is defined with `:.` (colon-dot), which registers it as the
boot execution target. After the assembly loads `ff64.boot`, `_semi_exec`
calls `_boot` automatically.

### Running total

~280 words/macros ported. 421 tests across 66 experiments, all passing.

---

## Phase 3e: The Help System (Experiment 067)

### The needexec pattern — lazy loading

FreeForth's philosophy is to keep the boot file minimal. The help system
is large enough that it belongs in a separate file, loaded only on first
use. The `needexec` pattern achieves this:

```forth
:. needexec needed H@ @ execute ;
```

`needexec` loads a file (via `needed`, with double-load guarding), then
executes the last word defined in that file. The loaded file is expected
to redefine whatever word triggered the load. On the second call, the
compiler finds the new definition (more recent in the dictionary) and
calls it directly — `needexec` is never reached again.

The stub in ff64.boot:

```forth
: help` ;` "lib/help64.ff" needexec ;
```

On first call, this loads `lib/help64.ff`, which defines its own
`help\`` that replaces this stub. The loaded `help\`` calls `wsparse`
itself to grab the keyword argument — arguments cannot be passed on
the stack through `needexec` because file loading disrupts the stack.

This is the same lazy-loading pattern DG uses for `see\`` — keep the
core small by deferring rarely-used functionality to loadable files.

### The help file format

`ff.help` is a plain text file where each entry starts with a
non-indented header line and continues with space-indented body lines:

```
dup  duplicates TOS
  stack: ( a -- a a )
  generated code: ...
```

The parser (`_help` in lib/help64.ff) scans line-by-line, matching the
first whitespace-delimited token against the keyword. On match, it
prints the header and all continuation lines (lines starting with
a space). On no match, it skips to the next line.

### Variables instead of stack gymnastics

The help system uses three variables — `_hfd` (file descriptor),
`_hkey` (keyword address), `_hklen` (keyword length) — rather than
juggling six values on the data stack. This is a pragmatic choice:
the stack gymnastics for managing file descriptor, buffer position,
remaining bytes, keyword address, keyword length, and match state
simultaneously would be heroic but unmaintainable.

### The FLAGS dance

Every conditional in the help code follows the pattern established
throughout this port:

```forth
_hfd @ 0- 0< IF ."cannot_open_ff.help" cr ;THEN drop
```

Recall: `0-` emits `test rbx,rbx` (setting CPU FLAGS). `0<` stores a
condition code in `cond_jmp` — it emits no machine code. `IF` reads
`cond_jmp` and emits a conditional jump. The `drop` after `;THEN`
removes the tested value from the stack in the fall-through (success)
path.

This pattern appears five times in the 50-line help system. There is
no boolean — the CPU FLAGS carry the conditional state directly from
the `test` instruction through the `drop` (which uses LEA, preserving
FLAGS) to the conditional jump.

### Running total

~285 words/macros ported. 426 tests across 67 experiments, all passing.

---

## Phase 3f: Dynamic Library Linking (Experiment 068)

This is the bridge between FreeForth's self-contained world and the
vast ecosystem of C libraries. The i386 FreeForth (in `fflinio.asm`)
used `#lib`, `#fun`, and `#call` with an elegant `xchg eax, esp`
trick to switch between the Forth stack and C's `cdecl` calling
convention. On x86-64, the SysV ABI passes arguments in registers,
making `#call` fundamentally different.

### The three primitives

**`#lib` ( addr len -- libh )** — calls `dlopen(filename, RTLD_LAZY |
RTLD_GLOBAL)`. NUL-terminates the Forth string in-place at `addr+len`
before passing it to dlopen. Returns the opaque library handle.

**`#fun` ( addr len libh -- funh )** — calls `dlsym(handle, name)`.
Returns the resolved function pointer.

**`#call` ( argN ... arg1 N funh -- result )** — the heart of the
system. Takes N arguments from the Forth data stack, maps them to
SysV ABI registers (`rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`), aligns
the C stack to 16 bytes, and calls the function pointer. Up to 6
arguments are supported (the maximum for register-only SysV calls).
The result in `rax` becomes the new TOS.

### The SysV ABI mapping

The i386-to-x86-64 calling convention change is significant:

| i386 cdecl | x86-64 SysV |
|------------|-------------|
| All args on stack | First 6 in registers, rest on stack |
| `eax` = return | `rax` = return |
| Caller cleans stack | Caller cleans stack |
| No alignment req | 16-byte stack alignment required |

The `#call` implementation uses a cascade of compare-and-jump:

```asm
mov rdi, [r15]          ; arg1
cmp r13, 1
je dc_call
mov rsi, [r15+8]        ; arg2
cmp r13, 2
je dc_call
...
```

This reads exactly N arguments from the data stack into the correct
registers, then falls through to the call site.

### Register survival across C calls

A critical detail: in the SysV ABI, `rbx`, `rbp`, `r12`–`r15` are
callee-saved. These happen to be FreeForth's core registers:

| Register | FreeForth use | SysV status |
|----------|---------------|-------------|
| rbx | TOS | Callee-saved ✓ |
| rdx | NOS | **Caller-saved** ✗ |
| r15 | Data stack pointer | Callee-saved ✓ |
| rbp | Here (compilation pointer) | Callee-saved ✓ |

The one problem: `rdx` (NOS) is caller-saved and gets clobbered by
C calls. `_dlcall` saves and restores the full data stack state around
the call, so this is handled correctly.

### The dl_err crash — a cautionary tale

The error handling path initially caused a SEGV that took extensive
debugging to diagnose. The symptom: when `dlopen` failed, `_throw`
would crash trying to return through the catch frame.

The original code copied the `dlerror()` message string to `here`
(the compilation pointer, `rbp`). This seemed natural — `here` is
writable memory, and the string needed to be stored somewhere as a
counted string for `_throw`.

The problem: `here` points into the same memory region where the
compiler generates code. The catch frame's return address points to
compiled code **near** `here` — typically just a few bytes before it.
When dl_err wrote the 70+ byte error string to `here`, it overwrote
the compiled code that the catch frame's return address pointed to.

GDB showed the truth immediately. The `ret` in `_throw` jumped to
address `0x44b64c`, which was now in the middle of the string
`"nonexistent.so: cannot open shared object file..."`. Disassembly
showed instructions like `outsb` and `je` — the ASCII bytes
interpreted as x86 opcodes.

**The fix:** A dedicated `dl_errbuf` (256 bytes in the data section)
that is nowhere near generated code. This is a general rule: **never
write to `here` from error paths** — the catch frame's return address
may point to nearby generated code.

This echoes the cautionary tale of the `ct=1` bug (experiment 038):
the generated code is the ground truth, and GDB reveals it instantly.
Hours of manual reasoning about stack states and register values
paled before one look at the actual crash site.

### Convenience words in ff64.boot

```forth
variable libc
:. dlsetup libc@ 0<>; drop "libc.so.6" #lib libc! ;
dlsetup
: libc.` wsparse libc@ #fun lit` #call ' call, ;
: libc_ libc@ #fun #call ;
```

`dlsetup` runs at boot time, opening `libc.so.6` and caching the
handle. The `0<>;` pattern returns immediately if libc is already
loaded (guard against double-init).

`libc.`` is a compile-time macro: `libc. strlen` parses "strlen",
resolves it via `#fun`, compiles a literal push of the function
pointer, and emits a `#call`. The function pointer is resolved once
at compile time and baked into the generated code.

`libc_` is the runtime equivalent for interactive use.

### The linker change

The binary is now dynamically linked:

```
ld -m elf_x86_64 -lc -ldl --dynamic-linker=/lib64/ld-linux-x86-64.so.2
```

This adds a `.got.plt` section (at `0x402fe8`) containing GOT entries
for `dlopen`, `dlsym`, and `dlerror`. The PLT stubs handle lazy
resolution — the first call to each function goes through the dynamic
linker, which patches the GOT entry for subsequent direct calls.

Our `.flat` section starts at `0x403018`, immediately after the GOT.
The two sections are adjacent but non-overlapping — verified by
examining the ELF section headers.

### Running total

~290 words/macros ported. 428 tests across 72 experiments, all passing.

---

## Phase 3g: Self-Booting — The Assembly REPL Dies (Experiment 069)

This is a pivotal moment in the port. Until now, ff64 required an
external boot file: you ran `./ff64 -f ff64.boot` and the assembly
kernel's REPL processed the `-f` flag, loaded the boot file, then
presented a `> ` prompt. Christophe's original i386 `ff` never worked
this way — it embedded `ff.boot` directly in the binary via FASM's
`file` directive, compiled it at startup, and handed control to the
Forth-defined REPL.

DG's directive was clear: "ff64 shouldn't process argv directly, but
leave it for the Forth code to process." This reflects Lavarenne's
core philosophy — the assembly kernel does as little as possible; Forth
defines everything user-facing.

### What was removed

About 110 lines of assembly disappeared:

- **The `-f` argument loop** — assembly code that walked `argv[]`,
  checked for `-f`, opened files, and fed them to `_compiler`. This
  was a brute-force mechanism that duplicated what `doargv` does in
  Forth.
- **The interactive REPL** — a `> ` prompt, `sys_read` into `inbuf`,
  `_compiler` call, `ok\n` response loop. Simple but inflexible —
  no error handling, no stack display, no catch/throw.
- **Prompt strings** — `"> "` and `"ok\n"` literal data.

### What replaced it

The assembly `_start` became elegant in its minimality:

```
_start:
    init registers (r15, rbx, rdx, rbp)
    set H to heads64, anon to codebuf
    install SEGV handler
    save argc/argv
    set tin/tp to boot64/boot64_end     ← embedded boot source
    call _compiler                       ← compile the boot source
    call _semi_exec                      ← run the last anonymous block
    exit (never reached)
```

The last line of `ff64.boot` is `_boot ;` — an anonymous block that
calls `_boot`. The compiler processes this, and `_semi_exec` executes
it. `_boot` calls `ossetup`, `doargv`, `_hidepvt`, `_top` — and
`_top` (the Forth REPL) never returns.

### The filter gotcha

The boot source is filtered before embedding to remove comments and
blank lines:

```makefile
ff64.boot.min: ff64.boot
    grep '^[: _A-Za-z0-9]' $< > $@
```

The `_` in the character class is critical. Without it, `_boot ;`
(which starts with `_`) gets filtered out. The binary builds,
boots, compiles all definitions — but never calls `_boot`. There's
no error. The program just silently falls through to `exit`. This
cost hours of debugging until we traced it to the grep pattern.

### The accept rewrite

The old `_accept` did bulk reads: `sys_read(stdin, buf, 4096)`. With
piped input, this could read multiple lines at once, causing the REPL
to process them as one giant block. The new `_accept` reads
byte-by-byte until newline (LF=10) or buffer limit. This is slower
but correct — each `accept` returns exactly one line, which is what
the Forth REPL expects.

### The prompt change and the Makefile cascade

The assembly REPL printed `> ` before input and `ok\n` after. The
Forth REPL (`_top` via `ui`/`prompt`) prints ` N; ` where N is the
stack depth. This broke every test that parsed output.

All 45 experiment Makefiles needed updating:
- Remove `BOOT = ../../ff64.boot` and `-f $(BOOT)` from commands
- Change `sed 's/^> //'` to `sed 's/^ *[0-9-]*; *//'` (strip depth prompt)
- Remove ` ok` from expected output
- Double `$` for Make escaping in sed end-of-line anchors (`$$`)

This was tedious but necessary — and it proved the test infrastructure's
value. Without tests, this transition would have been far riskier.

### Running total

Same ~290 words. 414 tests across 69 experiments. The binary is now
truly self-contained.

---

## Phase 3h: Compatibility and Polish (Experiments 070–072)

With the self-booting binary in place, the next experiments focused on
compatibility with existing FreeForth code and filling in missing
utility words.

### TIMES...REPEAT auto-rdrop (Experiment 070)

Every Forth programmer who's used FreeForth writes:

```forth
10 TIMES r . REPEAT
```

The i386 version handles this correctly — `REPEAT` detects the RTIMES
signature in the compiled code and automatically emits `rdrop` to
clean the return stack. Our ff64 had a separate `LOOP` word for
counted loops, but this breaks compatibility with all existing
FreeForth libraries.

The i386 approach (reading machine code bytes to detect the signature)
is fragile on x86-64 where the instructions are longer. Instead, we
use a compile-time flag on the data stack:

- `BEGIN` pushes `0` (not counted) then `here`
- `RTIMES` pushes `-1` (counted) then addresses
- `REPEAT` consumes the addresses, tests the flag, and conditionally
  emits the 4-byte `add rsp, 8` sequence (equivalent to `rdrop`)
- `AGAIN`/`UNTIL` consume the flag with an extra `drop`

The flag travels naturally with loop nesting — each `TIMES` pushes
its own `-1`, each `REPEAT` consumes exactly one.

### hidepvt compaction (Experiment 071)

The initial `hidepvt` took a shortcut: zeroing the first byte of
private word names so `words` wouldn't display them. But the headers
still occupied memory, and tools like `cat -v` could see them as
`^@boot`-style ghosts. DG wanted true compaction — physically
removing private headers, as Lavarenne's original does.

**The algorithm:** Walk the dictionary chain from H@ (newest) toward
older headers. For each private header (bit 3 set in ct byte):
1. Compute its size from the size byte
2. Slide all newer headers UP by that amount using `cmove>` (backward
   copy for overlapping regions)
3. Advance H@ by the removed header's size
4. Continue scanning from the next position

This required adding `cmove>` as an assembly primitive — the reverse
of `cmove`, copying from high to low addresses so overlapping regions
don't corrupt. The x86 `std ; rep movsb ; cld` sequence handles this
in three instructions.

**Three bugs discovered:**
1. `r@` doesn't exist in ff64 — only `r` (as an inline macro). Using
   `r@` produced a mysterious `error: 0xFF` as the parser hit the
   dictionary sentinel.
2. Unicode em-dash `—` in comments. FreeForth's parser doesn't know
   about UTF-8 — the 3-byte sequence became garbage tokens.
3. The scan pointer was consumed by `_remove_hdr` with no return value,
   leaving the loop with nothing to iterate on. Fixed by returning the
   next scan position.

After compaction, ~485 bytes of header space were reclaimed — about 30
private definitions physically removed from the dictionary.

### Features buffer and utility words (Experiment 072)

The final polish experiment added several missing pieces:

**The features buffer** — a 100-byte counted string that tracks loaded
capabilities. Libraries append names at boot time via `_feat`:

```forth
_feat boot
_feat help
_feat dynlink
```

The `-v` word displays them: `\ features: boot help dynlink`.

**New words:** `count` (ANS name for `c@+`), `move` (smart overlapping
copy that delegates to `cmove` or `cmove>` depending on direction),
`pad` (scratch buffer 256 bytes above `here`), `zt` (zero-terminate
a Forth string for C interop), `append`/`appendc` (counted-string
buffer operations), `2swap` (inline 4-item stack rotation), `nop`
(do-nothing placeholder).

**Improved `dump`** now formats output in 16-byte lines with address
headers, matching Lavarenne's i386 style:

```
0044e6cd: 68 65 6c 6c 6f 20 77 6f 72 6c 64 00 e8 51 f5 ff
```

### Running total

~310 words/macros ported. 428 tests across 72 experiments, all passing.

---

## Phase 3i: The Turnkey Mechanism — From Compiler to Program

The turnkey is FreeForth's way of freezing a compiled system into a
standalone binary. The i386 version has had this since the beginning
(`fftk.asm` + `lib/mkimage.ff`). Understanding how it works reveals
a beautiful piece of engineering: vectors, image dumping, and one
clever `-f` handler that rewires the boot sequence.

### How the i386 turnkey works

The flow has three stages:

**Stage 1: Compile.** Run `./ff -f cat.ff -f mkimage.ff`. The compiler
loads `cat.ff`, which defines words like `cat` and `main`. Then it
loads `mkimage.ff`, which dumps two files:
- `cmpl` — the raw code image (variables + assembly runtime + compiled
  Forth definitions)
- `dict` — the dictionary headers (separate because i386 headers live
  in BSS, outside the code region)

**Stage 2: Assemble.** `fasm fftk.asm` embeds both files. The startup
code (`_start`) relocates the headers to their runtime location,
initializes variables, and jumps to `_bootxt` (offset 16 in the
image) — the execution token of `_boot`.

**Stage 3: Run.** The turnkey binary executes `_boot`, which calls
`ossetup → doargv → _top`. But here's the trick: by the time the
image was dumped, `doargv` and `_top` were **already rewritten**.
The binary runs `main` and exits, never entering the REPL.

### The `-f` handler and the mainxt trick

The magic lives in `fflin.boot` (the Linux boot overlay):

```forth
variable mainxt pvt
:. _main mainxt @ execute 0 exit
: -f` needs` "main" find 0- 0= drop
  IF mainxt ! _main ' _top !^ doargv n^ ELSE drop THEN ;
```

When `-f somefile.ff` is processed:

1. `needs` loads the file, compiling all its definitions.
2. `"main" find` looks up `main` in the dictionary.
3. **If `main` is found:** its xt goes into `mainxt`, then the boot
   vectors are rewritten:
   - `_main ' _top !^` — replaces `_top` (the REPL) with `_main`
   - `_postboot n^` — nops the `_postboot` vector, skipping both
     argument processing (`doargv`) and header compaction (`_hidepvt`)

   After this, the boot sequence `_boot → ossetup → _postboot → _top`
   becomes `_boot → ossetup → nop → _main`. And `_main` does:
   `mainxt @ execute 0 exit` — run main, exit with code 0.
4. **If `main` is not found:** the file was a library. Drop the
   leftover string and continue processing arguments normally.

### Why vectors make this work

`_top` and `_postboot` are vector words (defined with `:^`). A vector
is a word whose body is an indirect jump — it calls through a stored
address that can be changed at runtime with `!^`. This is the same
mechanism used for `ossetup` (platform init hook).

`doargv` itself is a private word (`:. doargv`), not a vector — it
doesn't need independent redirection. The `_postboot` vector wraps
`doargv _hidepvt` together, since the turnkey needs to skip both.

When the image is dumped, the vectors contain their **rewritten**
values. The turnkey binary's `_boot` follows the same path as the
interactive compiler, but the vectors point to different code:

| Vector | Interactive | Turnkey |
|--------|------------|---------|
| `ossetup` | platform init | platform init (same) |
| `_postboot` | doargv + hidepvt | nop (turnkey needs neither) |
| `_top` | REPL loop | `_main` → run main, exit |

### cat.ff — a sample turnkey program

```forth
needs mmap.ff
: ok?  dup $FF | 1+ drop 0= IF strerror rdrop ;THEN drop ;
: cat  m mmapr ok? m @ m mm.sz+ @ type m munmap 2drop ;
: main 0 argc 1- TIMES 1+ dup argv cat REPEAT ;
```

When compiled with `./ff -f cat.ff -f mkimage.ff`:
1. `needs mmap.ff` loads the memory-mapping library
2. `ok?`, `cat`, `main` are compiled
3. `-f cat.ff` detects `main` → rewrites vectors
4. `-f mkimage.ff` dumps the image with rewritten vectors
5. The resulting `fftk` binary runs `main`, which iterates over
   command-line arguments and memory-maps each file to stdout.

Note: `main` handles `argc`/`argv` itself. The turnkey's argument
processing vector (`doargv`) is a nop — all arguments belong to the
program now, not the Forth system.

### Why _hidepvt doesn't matter for turnkey

In interactive use, `_hidepvt` removes private word headers from the
dictionary to speed up lookups. But a turnkey binary never searches
the dictionary at runtime — it runs pre-compiled machine code.
Private headers waste a few hundred bytes of space but cause no
performance impact. The i386 `_boot` doesn't even call `_hidepvt`:

```forth
:. _boot ossetup doargv _top ;
```

The ff64 version groups `doargv` and `_hidepvt` into a single
`_postboot` vector:

```forth
:^ _postboot doargv _hidepvt ;
:. _boot ossetup _postboot _top ;
```

For turnkey builds, `_postboot` is nop'd — skipping both argument
processing and header compaction in one operation.

### The ff64 port — and a lurking bug

For ff64, the same turnkey mechanism applies with some differences:
- Headers live in `.flat` (not BSS), so no separate `dict` file —
  the `cmpl64` dump includes everything
- 64-bit variables at known offsets (8 bytes each instead of 4)
- The `-f` handler detects `main` and rewrites vectors (`_top`,
  `_postboot`)
- `DS0` (data stack top address) stored via `cmpl64.cfg` since
  `dstack_top` is an assembly label not exposed to Forth

**The offset table** lists the header variables at the start of the
`.flat` section (`cmpl64` file). The turnkey startup code references
these by numeric offset to initialise the system:

| Offset | Size | Name | fftk64 startup |
|--------|------|------|----------------|
| 0 | 8 | H | Already correct (header chain) |
| 8 | 8 | anon | Set to fftk64's codebuf |
| 16 | 8 | callmark | Cleared to 0 |
| 24 | 8 | tin | (not touched — no source to compile) |
| 32 | 8 | tp | (not touched) |
| 40 | 8 | xfp | Cleared to 0 |
| 48 | 8 | CS0 | Set to rsp (argc/argv/envp) |
| 56 | 8 | bootxt | Set to `_boot` xt by mkimage |
| 64 | 1 | SC | Cleared to 0 |
| 65 | 8 | cond_jmp | Cleared to 0 |

**This table was wrong for months.** The original `fftk64.asm`
(experiment 073) was written when the header layout had fewer fields.
Later experiments added `CS0` (exp 134/142), shifting `bootxt` from
offset 56 → where it already was, but the fftk64.asm code had been
written with incorrect offsets from the start. The specific errors:

- `xfp` was at offset 48 (should be 40)
- Offsets 56/64 were used to store `argc`/`argv` as separate variables
  — but ff64 derives them from `CS0` (initial stack pointer), not from
  stored copies
- `bootxt` was read from offset 72 (should be 56) — reading garbage
- `SC` was at offset 88 (should be 64)

The result: `fftk64` produced a binary that jumped to a garbage address
and crashed immediately. The fix (in the "put a bow on it" session)
was simply correcting every offset in `fftk64.asm` and changing the
`argc`/`argv` handling to store `rsp` into `CS0` — exactly what
`ff64.asm`'s own `_start` does.

**Lesson for the historian:** When an assembly file references another
file's layout by hardcoded numeric offsets, those offsets are a silent
contract. If either side changes, nothing warns you. The i386 version
is immune because `fftk.asm` embeds its image at the same address and
the compiler has already resolved all symbols. The x86-64 version,
with its explicit offset table, creates a maintenance hazard. A future
improvement would be to generate the offsets from the assembly source,
or to have mkimage write them into the config file.

### Building a Turnkey — Dynamic and Static

There are two x86-64 turnkey builders:

| | `fftk64` (dynamic) | `fftk64s` (static) |
|---|---|---|
| **Assembler** | `fftk64.asm` | `fftk64s.asm` |
| **Linker** | ld (links libc, libdl) | None (FASM outputs ELF directly) |
| **libc** | Yes (needed for `dlopen`/`dlsym`) | No |
| **FFI (`#lib`/`#fun`)** | Works | Stubbed out |
| **Build image with** | `./ff64` | `./ff64s` |
| **cat.ff size** | ~580K | ~108K |

**Why the build host matters for static turnkeys:**

This is subtle and important. The `cmpl64` image contains **absolute
addresses** — every compiled `call`, every variable reference, every
header pointer is a raw 64-bit address. There is no relocation table.
The image must be loaded at exactly the same virtual address where it
was compiled.

`ff64` (dynamic) places its `.flat` section at `0x403018` — the linker
assigns this address based on ELF section layout, PLT stubs, and GOT
entries for libc symbols.

`ff64s` (static) places its `.flat` section at `0x400078` — right
after the minimal ELF program header. There is no linker, no sections,
no PLT.

If you build `cmpl64` with `ff64` and load it into `fftk64s`, every
address in the image is wrong by `0x2FA0` (the difference between the
two base addresses). The code jumps to the wrong places, loads from
the wrong variables, and crashes immediately.

**Rule: dynamic images go in `fftk64`, static images go in `fftk64s`.**

The build workflow:

```bash
# Dynamic turnkey (links libc — needed if app uses #lib/#fun/#call)
./ff64  -f myapp.ff -f lib/x86-64/mkimage.ff
make fftk64
mv fftk64 myapp

# Static turnkey (no dependencies — smaller, faster startup)
./ff64s -f myapp.ff -f lib/x86-64/mkimage.ff
make fftk64s
mv fftk64s myapp
```

### Why the Static Turnkey Was 501KB — and How It Became 108KB

The first working `fftk64s` was 501KB. The i386 `fftk` was 35KB.
Both contained the same cat.ff program. What went wrong?

**The memory layout of ff64.asm:**

```
Address     What                    Size    Contents
─────────── ─────────────────────── ─────── ──────────────────────
0x400078    H (variables)           ~200B   Compiler state
0x400150    Assembly runtime        ~4KB    Forth primitives
0x401400    Headers                 ~80KB   Dictionary entries
0x415999    tib                     256KB   ← terminal input buffer
0x455999    eob                     1KB     ← end-of-buffer scratch
0x455D99    helpbuf                 128KB   ← help file buffer
0x475D99    dstack                  8KB     ← data stack
0x477D99    dstack_top              —       (DS0 points here)
0x477D99    codebuf                 64KB    ← compiled Forth code
0x487DA2    [here]                  —       (compilation pointer)
```

`mkimage.ff` dumps everything from `H` to `here` — that's the entire
address range, **including 393KB of zero-filled buffers** (tib,
helpbuf, dstack) sitting between the assembly runtime and the compiled
Forth code.

In the dynamic build (`ff64`), these buffers live in `.bss` — a
special ELF section that tells the OS "zero-fill this region in
memory; don't store it in the file." The linker sets `MemSiz > FileSiz`
in the program header, and the kernel zero-fills the extra pages at
load time.

In the static build (`ff64s`), FASM's `format elf64 executable` does
the same trick automatically: `rb` directives at the end of a segment
set `MemSiz > FileSiz` without occupying file space. **But the
buffers weren't at the end.** They were in the middle, with codebuf
(and thus all compiled Forth) after them. Since there was initialized
data (compiled code) after the buffers, FASM had to store the zeros.

**The fix:** reorder the `rb` declarations in ff64.asm:

```
Before: ... | tib 256K | eob 1K | helpbuf 128K | dstack 8K | codebuf 64K |
After:  ... | codebuf 64K | tib 256K | eob 1K | helpbuf 128K | dstack 8K |
```

Now `codebuf` (where compiled Forth code lives) is immediately after
the assembly runtime and headers. The large zero-filled buffers are
trailing `rb` declarations. When FASM writes the ELF, it sets
`MemSiz = 564KB` but only stores `FileSiz = 108KB` — the kernel
zero-fills the remaining 456KB at load time.

**The image shrinks from 499KB to 106KB.** The turnkey binary goes
from 501KB to 108KB. Comparable to the i386's 35KB, adjusted for
64-bit pointer sizes and a larger boot Forth library.

**Why this matters beyond size:** A 108KB static binary with zero
dependencies — no libc, no dynamic linker, no shared libraries —
loads in microseconds. On embedded or minimal systems, it's the
difference between "works everywhere" and "needs a runtime."

### Critical Bug: loadfile Overwrite (historical — removed in exp 141)

This was the most significant bug during turnkey development, now only
of historical interest. The old `loadfile` reset `rbp = hereatexec`
before each file's compilation, but `hereatexec` was never updated.
With multiple `-f` files, the second file's compilation overwrote the
first. The fix at the time was updating `hereatexec` after `_compiler`
returned. The entire mechanism was later removed when `_loadfile` was
replaced by Forth's `eval` (experiment 141).

### The `n^` Correction

The vector nop operation `n^` was corrected from `dup 6+ swap 1+ d!`
to `dup 5+ swap 1+ d!`. The push/ret preamble is:
```
xt+0: 68 <target32>  ; push imm32
xt+5: C3             ; ret
xt+6: ...            ; body code
```

With `6+`, n^ set the target to xt+6 (body start), **restoring** the
vector to its original behavior. With `5+`, n^ correctly sets the
target to xt+5 (the ret), creating a true nop: `push xt+5; ret` →
jumps to ret → returns to caller.

### OS/Architecture Separation (Experiment 074)

Lavarenne's original design cleanly separates OS-specific code from
the portable core:

```
Portable:           ff.asm + ff.boot
Linux-specific:     fflin.asm + fflinio.asm + fflin.boot
Windows-specific:   ffwin.asm + ffwinio.asm + ffwin.boot
```

The ff64 port initially put everything in `ff64.asm` + `ff64.boot`.
Experiment 074 begins restoring the separation by creating
`fflin64.boot` — extracting OS-specific Forth definitions:

```
Architecture (x86-64):  ff64.asm + ff64.boot
OS (Linux):             fflin64.boot
```

**ff64.boot** contains architecture-specific definitions: backtick
macros that emit x86-64 opcodes, stack operations, flow control,
the SWAPbit machinery, the REPL, and error recovery.

**fflin64.boot** contains OS-specific definitions: dynamic library
interface (dlsetup, libc.), file loading (needed, needexec), command-
line processing (doargv, -f handler), turnkey support (mainxt, _main,
_postboot), and the boot sequence (ossetup, _boot).

The Makefile concatenates both into `ff64.boot.min`:
```makefile
ff64.boot.min: ff64.boot fflin64.boot
grep -h '^[: _A-Za-z0-9]' $^ > $@
```

This establishes the pattern for future ports. An ARM64 port would
need `ff-arm64.asm` + `ff-arm64.boot` (new compiler and macros) but
could reuse much of `fflin64.boot` (the Linux Forth layer). A macOS
port would need `ffmac64.boot` (different library paths and signal
handling) but reuse `ff64.boot` (same architecture).

**Why fflin.boot can't be reused as-is:** It contains i386-specific
elements — the `^^` backtick macro emits x86 instructions, struct
sigaction is 140 bytes (vs 152 on x86-64), and `needed` has minor
differences in error handling (two-step openlib/openr vs single call).
However, ~80% of fflin.boot is pure Forth that works unchanged.

### Recoverable SEGV Handler (Experiment 075)

The assembly-level SEGV handler (installed by `_start`) is always
fatal — it prints a message and exits with code 139. Experiment 075
replaces it at Forth boot time with a recoverable handler that throws
to the REPL's catch frame.

The pattern comes from the i386 `fflin.boot`:

```forth
create SEGVact pvt 152 allot    \ struct sigaction (152 bytes on x86-64)
:. SEGVhndlr !"SEGV caught" ;  \ handler: inline error + throw
SEGVhndlr ' SEGVact!           \ store handler address in struct
$40000000 SEGVact 136 + !      \ SA_NODEFER flag at offset 136
:. SEGVthrow 0 SEGVact 11 3 "sigaction" libc_ drop ;
SEGVthrow                       \ install handler via libc sigaction(2)
```

**How it works:** When the kernel delivers SIGSEGV, it calls
`SEGVhndlr`. The `!"` word stores the error string and calls `_throw`.
`_throw` does a longjmp-style restore (`mov rsp, [xfp]`), abandoning
the signal frame entirely and landing in the REPL's `catch` frame.

**SA_NODEFER is critical:** Without it, SIGSEGV stays blocked after
the first throw (because `_throw` never returns through `sigreturn`).
SA_NODEFER prevents the kernel from blocking the signal during handler
execution, allowing subsequent SEGVs to also be caught.

**x86-64 struct differences:** The struct sigaction is 152 bytes (not
140) because handler and restorer are 8-byte pointers. The sa_flags
field is at offset 136 (not 132).

**The assembly handler remains** as an early-boot fallback — it's
installed by `_start` before Forth boots. Once `SEGVthrow` runs in
fflin64.boot, the Forth handler replaces it.

### The `_parse` Bug and ELSE Resolution (Experiment 077)

This was the most significant bug found in the ff64 port. It had been
masquerading as the "ELSE corruption bug" for months, causing
position-dependent failures when definitions were added to ff64.boot.

**The bug:** The x86-64 `_parse` entry did a full DROP1 — consuming
the separator from TOS and popping the next item from the memory
stack. The i386 original did DUP1 — saving NOS to memory. This made
every call to `parse` or `lnparse` consume one extra stack item.

```asm
; x86-64 (BUGGY — DROP1 at entry):
_parse:
  movzx eax, bl           ; separator
  mov rbx, rdx            ; NOS → TOS
  mov rdx, [r15]          ; EXTRA: pop memory → NOS
  add r15, 8              ; EXTRA: adjust memory stack

; i386 (CORRECT — DUP1 at entry):
_parse:
  mov [esi], edx          ; save NOS to memory
  sub esi, 4
  xchg eax, ebx           ; separator → eax
```

**The fix:** Remove the two memory-pop instructions. The `.start`
label later in `_parse` handles the NOS-to-memory save, so the entry
only needs to consume the separator from TOS.

**Why it looked like an ELSE bug:** Adding definitions to ff64.boot
changed which `parse` calls executed during file loading, shifting the
accumulated stack corruption. The failures appeared position-dependent
and correlated with ELSE usage — but only because ELSE definitions
tend to be longer, changing the position of subsequent `parse` calls.

With the fix applied, ELSE works correctly and all workarounds (pick`,
dump, etc.) are no longer necessary.

### Generic `syscall` Word (Experiment 076)

The `syscall` word provides the same interface as i386:
`( args... #args syscall# -- ior )`. On x86-64, it maps arguments to
rdi/rsi/rdx/r10/r8/r9 (instead of i386's ebx/ecx/edx/esi/edi/ebp)
and uses the `syscall` instruction (not `int $80`). Syscall numbers
differ between architectures — user code must use x86-64 numbers.

### Backslash Comment Word (Experiment 077)

The `\` word serves dual purpose in the REPL: end-of-line comment and
multiline input escape. It works through the backtick mechanism —
when the compiler encounters `\`, it appends a backtick, finds `\``,
and executes it at compile time:

```forth
: \` 2 >in -! lnparse 2drop 1 noauto! ;
```

Setting `noauto` prevents the REPL from auto-executing the current
line. The next REPL iteration resets `noauto` to 0 via `_top`. This
enables multiline definitions at the REPL — append `\` to continue
on the next line.

### FFPATH and Library Search (Experiment 078)

FreeForth keeps the boot image small by loading less-used words on
demand. Lavarenne's i386 had a simple path mechanism in `fflin.boot`
(using `open'`). DG created the `FFPATH` search-path system and
`openlib` for x86-64 (experiment 078).

#### How FFPATH Works

The search path is stored as NUL-separated directory entries with a
double-NUL terminator:

```
lib/x86-64\0lib\0.\0\0
```

Default order: `lib/x86-64` (x86-64-specific), `lib` (shared), `.` (CWD).
This means a file in `lib/x86-64/` always takes precedence over the same
filename in `lib/` — the mechanism for providing architecture-specific
implementations of cross-platform library words.

When `needed "somefile.ff"` is called:
1. The backtick guard is checked (is `somefile.ff\`` defined?)
2. If not found, `openlib` searches each FFPATH directory
3. For each directory, it builds `dir/somefile.ff` and tries to open it
4. The first successful open wins — `needed` opens it, reads into
   tib, and calls `eval`

Absolute paths (`/...`) and relative paths (`./...`) bypass the
FFPATH search entirely.

#### Buffer Allocation: The Anonymous Block Self-Overwrite

Allocating buffers in FreeForth requires understanding the Primer's
WARNING about anonymous definitions that overwrite themselves.
`allot` is a compile-time macro (`add rbp, TOS`). When at the top
level, this code is compiled into an anonymous block. `_semi_exec`
rewinds `rbp` to `[anon]` (the start of the anonymous block) before
executing — so the allotted N bytes start exactly where the anonymous
block code resides. After execution, the first ~25 bytes of the
allotted area happen to contain the dead anonymous block code.

Lavarenne's prescribed pattern separates allocation from initialization
with a semicolon:

```
create safe 40 allot ; safe 40 $FF fill ;
```

The `;` forces the allot block to execute first. The second block's
code is compiled PAST the allotted area, so `fill` can safely write
to the buffer without overwriting executing code.

`_ffpath_alloc` follows this pattern: the `variable ffpath pvt 248 allot`
at compile time allocates the buffer (via one anonymous block), and
`_ffpath_alloc` (called from `ossetup` — a completely separate execution
context) writes path data to it.

#### i386 vs x86-64 Differences

| Aspect | i386 (fflin.boot) | x86-64 (fflin64.boot) |
|--------|--------------------|-----------------------|
| Path storage | `eob` buffer | `variable ffpath pvt 248 allot` |
| Default path | Single `lib` dir | `lib/x86-64:lib:.` |
| File open | Direct open | `openr` (addr len -- fd) |
| Guard creation | `marker pvtmargin` | File creates own guard |
| Error handling | `!"Can't_open_file."` | `!"_not_found"` |

The x86-64 version is simpler: no `eob` (end-of-buffer) word, no
`marker` at compile time. The guard mechanism relies on loaded files
defining their own backtick-suffixed marker word, or on the `needexec`
pattern where the stub is overwritten on first load.

### Self-Patching libc Resolution: The fixup Mechanism (Experiment 079)

FreeForth provides access to C library functions (strerror, malloc, free,
getenv, etc.) through a clever self-patching mechanism called `fixup`.
Rather than resolving every libc symbol at boot time (wasteful if most
are never called), fixup defers resolution until first use, then patches
the calling code so subsequent calls go directly to the resolved function.

#### The Two-Layer Pattern

Every libc wrapper uses two definitions:

```forth
:. _xxx "symbol" fixup ;     ( hidden: resolve-on-first-call thunk )
:  xxx ... _xxx N #call ... ; ( public: calls _xxx, then C function )
```

**First call to `xxx`:**
1. `xxx` calls `_xxx` (the hidden thunk)
2. `_xxx` pushes the symbol name ("symbol") via inline string
3. `fixup` calls `libc@ #fun` (dlsym) to resolve the symbol
4. `fixup` allocates an 11-byte trampoline at `here`:
   ```
   48 BB <8-byte function handle>  C3
   (movabs rbx, funh)              (ret)
   ```
5. `fixup` patches `xxx`'s `call _xxx` instruction to redirect to the
   trampoline (overwrites the 4-byte rel32 offset in the E8 instruction)
6. Execution returns to `xxx`, which proceeds with `N #call`

**Subsequent calls to `xxx`:**
1. `xxx`'s patched `call` jumps to the trampoline
2. Trampoline loads `rbx` with the function handle and returns
3. `xxx` proceeds with `N #call` — no dlsym overhead

#### i386 vs x86-64: Why a Trampoline?

On i386, fixup replaces `call _xxx` (E8 rel32, 5 bytes) with
`mov ebx, imm32` (BB imm32, 5 bytes). Both are exactly 5 bytes — a
perfect in-place replacement. The callsite becomes a direct load
instruction.

On x86-64, function handles from `dlsym` are full 64-bit pointers
(e.g., 0x71a7d5ab43a0). `mov rbx, imm64` is 10 bytes (48 BB + 8 bytes
of immediate) — it doesn't fit in the 5-byte `call` slot. The
trampoline adds one level of indirection: the 5-byte call redirects to
an 11-byte code fragment that loads the 64-bit value and returns.

| Aspect | i386 | x86-64 |
|--------|------|--------|
| Patch target | 5-byte `call` | 5-byte `call` |
| Replacement | `mov ebx, imm32` (5 bytes) | redirect to trampoline |
| Trampoline | (none needed) | 11 bytes: `movabs rbx, imm64; ret` |
| After patch | Direct load, no call overhead | One extra call/ret pair |
| `rdrop` needed? | Yes (E8 call, not JMP) | No (tail-call: E9 jmp) |

#### The Tail-Call Requirement

The x86-64 fixup REQUIRES tail-call optimization on the hidden
definition. When `;` terminates `_xxx`, it converts the last `call fixup`
(E8) to `jmp fixup` (E9). This means when fixup executes, the return
stack contains only the wrapper's return address — exactly what fixup
needs to compute the patch site.

Without tail-call (as happens in file loading without explicit `;`):
```
R = [fixup_return, wrapper_return]
r> 5- → patches inside _xxx (WRONG!)
```

With tail-call (`;` applied):
```
R = [wrapper_return]
r> 5- → patches inside xxx (CORRECT!)
```

This is why the hidden definition pattern MUST include `;`:
```forth
:. _xxx "symbol" fixup ;   ← the ; is critical
```

This differs from the i386 version, which uses `rdrop` to skip over
fixup's return address. The x86-64 version eliminates `rdrop` because
tail-call ensures only the wrapper's return address is present.

#### Why `_colon` Matters

This bug was subtle because it worked in the REPL but crashed in file loading.
The key is that FreeForth's `_colon` (`:`) does NOT terminate the previous
named definition. In the REPL, `_auto` calls `;` at end of each line,
providing implicit termination. In file loading, definitions are only
terminated by explicit `;` or by `_auto` at EOF.

Without the `;`, the hidden definition _xxx has no `ret` or `jmp` at
the end — execution falls through into the next definition's body.

#### The First Consumers: strerror, ?ior, ?ior.

`lib/ior.ff` provides I/O error checking:

- **strerror** ( errno -- ): Prints error message for a given errno
  (negated, as FreeForth returns negative errnos from syscalls)
- **ior**: Variable storing the last I/O result
- **?ior**: ( n -- n ) Stores n in `ior`
- **?ior.**: ( n -- n ) Same, but also prints error if n looks like
  an errno (tests `dup $FF | -1 <>`)

These match Lavarenne's i386 `ff.ff` definitions exactly, including
the `?ior.` quirk where the `<>` comparison doesn't consume its
operands (by FreeForth's FLAGS-based conditional design).

### The Library System

Lavarenne kept less-used words in `ff.ff`, loaded on demand via
`needed`. DG organized the x86-64 equivalents in `lib/x86-64/` as
separate topic-based files rather than a monolithic `ff64.ff`.
Portable Forth files live in `lib/` (shared between architectures).

#### Directory Structure

```
lib/
├── pno.ff                  # Pictured numeric output (shared)
├── ior.ff                  # I/O error checking (shared)
├── malloc.ff               # Dynamic memory (shared)
├── shell.ff                # OS interface: getenv, system, cd (shared)
├── fileops.ff              # File operations: lseek, stat, ioctl (shared)
├── console.ff              # Terminal control: color, cursor, ekey (shared)
├── time.ff                 # Date/time: .now, ms@, ms (shared)
├── x86/                    # i386-specific library files
│   ├── fixup.ff            # Self-patching libc resolution (rdrop-free)
│   └── syscalls.ff         # i386 Linux syscall numbers
├── x86-64/                 # x86-64-specific library files
│   ├── fixup.ff            # Self-patching libc resolution (_fixbuf)
│   ├── syscalls.ff         # x86-64 Linux syscall numbers
│   ├── see.ff              # Disassembler
│   ├── help.ff             # Help system
│   └── mkimage.ff          # Turnkey image dumper
└── (i386 files in x86/)    # see.ff, compat.ff, debug.ff, etc.
```

Shared files use `needs syscalls.ff` to get arch-correct constants
(e.g., `_sys.lseek`, `_sys.stat`). FFPATH resolution ensures the
right `syscalls.ff` is loaded from the arch-specific directory.

#### FFPATH Resolution

`needed` searches directories in FFPATH order: `lib/x86-64:lib:.`
(configurable via `FFPATH` environment variable). Since `lib/x86-64`
precedes `lib`, x86-64-specific versions of a word automatically
take precedence.

#### Dependency Chain

```
syscalls.ff       ← arch-specific syscall number constants
fixup.ff          ← foundation (self-patching libc calls)
├── ior.ff        ← I/O error checking
│   ├── fileops.ff ← file operations (uses syscalls.ff)
│   │   └── console.ff ← terminal control
│   ├── shell.ff  ← OS interface (uses syscalls.ff)
│   └── malloc.ff ← dynamic memory
└── time.ff       ← date/time (uses syscalls.ff)
```

Most library files begin with `needs dependency.ff` to ensure
their prerequisites are loaded.

#### The _fixbuf Trampoline Allocation

A critical bug was discovered in the fixup mechanism: writing
trampolines at `here` (rbp) during anonymous block execution overwrites
the executing code, because `_semi_exec` resets rbp to the block start.

The fix uses a pre-allocated buffer (`_fixbuf`, 1024 bytes) in the
`.flat` section. Trampolines are written there via `c!` and `!`
instead of `c,` and `,`, with `_fixptr` tracking the next free slot.

#### Syscall Number Reference

| Operation | x86-64 | i386 | Notes |
|-----------|--------|------|-------|
| write | 1 | 4 | |
| stat | 4 | 106 | struct is 144 bytes (was 98) |
| lseek | 8 | 19 | |
| ioctl | 16 | 54 | |
| select | 23 | 142 | fd_set offset 8 (was 4) |
| nanosleep | 35 | 162 | |
| chdir | 80 | 12 | |
| time | 201 | 13 | |
| clock_gettime | 228 | — | replaces gettimeofday (78) |

### Feature Registration and the `needed` Guard (Experiments 086–087)

#### Moving PNO to a Library

Pictured Numeric Output (PNO: `<#`, `#`, `#s`, `hold`, `sign`, `#>`)
was originally in ff64.boot but is only used by the disassembler.
Experiment 086 moved it to `lib/64/pno.ff`, loaded on demand by
`see64.ff` via `"pno.ff" needed ;`.

This established the pattern for shrinking ff64.boot: identify words
used only by specific library files, extract them, and let `needed`
handle loading.

#### Feature Registration

Each lib/64 file appends its name to the `features` buffer when
loaded, making the `-v` command show all active capabilities:

```forth
" fixup" features append ;    \ at end of fixup.ff
" console" features append ;  \ at end of console.ff
```

The trailing `;` is essential. FreeForth's file loading feeds source
to the compiler, which only executes accumulated code at `;` or `:`.
Without `;`, the `features append` compiles but never runs.

#### FFHIDE Environment Variable

Setting `FFHIDE=0` disables `_hidepvt`, leaving all private (`:. pvt`)
words visible in the dictionary. This is useful for debugging library
internals. The check uses libc's `getenv` directly via `#fun/#call`:

```forth
:. _ffhide "getenv" libc@ #fun 1 swap #call
  0- 0; c@ $30- drop 0= IF hide off THEN ;
```

#### The `needed` Guard Fix

The most significant discovery in this batch: ff64's `needed` never
created the marker word its own guard depends on.

The guard mechanism works as follows:
1. `needed` temporarily appends `` ` `` to the filename
2. `find` searches for `filename``
3. If found, the file was already loaded — return immediately
4. If not found, create the marker word, then load the file

Step 4 was initially missing in ff64. The i386 version calls `marker
pvtmargin` before loading. The ff64 version originally went straight
to `loadfile` without creating the marker. The current `needed`
(experiment 141) includes `2dup marker pvtmargin` matching the i386.

### Walking Back Excess Assembly (Experiments 090–093)

FreeForth's design philosophy is that assembly should be minimal — most
functionality lives in Forth.  The ff64 port accumulated excess assembly
during development: runtime routines and WORD64 entries that duplicate
what backtick macros and Forth definitions already provide.

#### The WORD64 Shadowing Principle

The FreeForth compiler always tries the backtick form (`word``) before
the plain form.  If a backtick macro exists, the compiler uses it to
inline code directly.  The plain WORD64 entry is never reached — it's
dead code.

This means any WORD64 entry with a matching backtick macro in ff64.boot
can safely be removed, **provided** the backtick definition appears
before any use of the word.  Ordering matters: if `_m/mod` uses `w,`
on line 48, but `w,`` is defined on line 142, the compiler can't find
the backtick form and falls back to the WORD64.  Moving `w,`` before
line 48 eliminates the dependency.

#### What Was Removed

| Experiment | Category | WORD64 removed | Count |
|------------|----------|----------------|-------|
| 090 | Compiler fast-paths | `[`, `]`, `:`, `;`, `variable`, `constant`, `create`, `VECT`, `DATA`, `CSTE` | 10 |
| 091 | ct=2 inline entries | `swap`, `drop`, `nip`, `over`, `under`, `dup`, `+`, `-`, `and`, `or`, `xor`, `@`, `c@` | 13 |
| 092 | Comparison words | 17 backtick + 17 runtime comparison entries | 34 |
| 093 | Dead runtime words | `.`, `w,`, `,`, `d,`, `c,`, `allot`, `/`, `+!`, `d!`, `c!`, `!`, `cmove`, `>r`, `r>` | 14 |

**Total removed:** 71 WORD64 entries (from 135 to 64)

The target is approximately 61, matching ff.asm's original CODE/VECT
count.  The remaining 64 are close to this target.

#### The Comparison Factory (Experiment 092)

Rather than defining each comparison word individually in assembly,
ff64.boot uses a factory pattern matching ff.boot:

```forth
: 0-` $48, ,1 $DB85, s01 ;       \ test rbx,rbx (with REX prefix)
: _?1 cond d! drop` ;            \ unary: store Jcc, drop operand
: _?2 $48, ,1 $DA39, s09 _?1 ;   \ binary: cmp rdx,rbx + unary

$74 dup : 0=` lit _?1 ; : =` lit _?2 ;
$75 dup : 0<>` lit _?1 ; : <>` lit _?2 ;
\ ... (9 pairs total)
```

The factory takes a Jcc opcode byte (e.g., `$74` for JE) and defines
both the unary (`0=`) and binary (`=`) forms.  The `dup` before the
two `:` definitions feeds the same opcode to both.

#### The w, Ordering Lesson (Experiment 093)

The `_m/mod` helper uses `w,` to write parameterized 2-byte opcodes
(e.g., `F7 FB` for `idiv rbx` vs `F7 F3` for `div rbx`).  This is
a compile-time technique: `m/mod`` pushes `$FBF7` then calls `_m/mod`,
which emits `w,` to write those two bytes into the generated code.

On i386, `w,`` is defined at ff.boot line 17, well before `_m/mod` at
line 114.  On ff64, `w,`` was originally at line 142, after `_m/mod`
at line 48 — so the compiler fell back to the assembly WORD64.  Moving
`w,`` to line 45 eliminated this last assembly dependency.

The `idiv` instruction on x86-64 divides the 128-bit rdx:rax by the
operand.  The `m/mod` stack effect `( xl xh y -- x%y x/y )` maps to:
xl→rax (loaded from memory stack), xh→rdx (NOS), y→rbx (TOS).

### Locals: Compile-Time Return Stack Access (Experiment 095)

DG authored "locals" in `ff.ff` (the i386 standard library) as
compile-time macros — backtick definitions that emit hard-coded machine
code for direct return-stack cell access.  Rather than burning assembly
routines, he wrote them entirely in Forth using the compile-time
infrastructure: `$XX,` (write bytes at HERE), `,N` (advance HERE by N),
and the SWAPbit adjusters (`s01`, `s08`, `s09`) — very much in the
spirit of Lavarenne's minimalist design.

Copilot ported the locals to x86-64, translating each i386 machine
code encoding to its x86-64 equivalent.

#### The Words

| Word | Stack effect | What it does |
|------|-------------|-------------|
| `r0!`–`r5!` | `( x -- )` | Store TOS into call-stack cell 0–5 |
| `r0`–`r5` | `( -- x )` | Read call-stack cell 0–5 onto data stack |
| `>>r` | `( xn..x1 n -- \| == xn..x1 )` | Move n items from data to call stack |
| `>>rr` | `( xn..x1 n -- \| == x1..xn )` | Move n items, reversed order |
| `+r` | `( n -- )` | Drop n cells from call stack |
| `-r` | `( n -- )` | Reserve n uninitialized cells on call stack |

`>>r` preserves stack order: `10 20 30 3 >>r` puts 10 at [rsp] (top).
Individual `>r` reverses: `10 >r 20 >r 30 >r` puts 30 at [rsp].
`>>rr` is the opposite of `>>r`: it reverses during transfer.

#### x86-64 Encoding Challenges

**SIB byte requirement:** On x86-64, `[rsp]` addressing always needs
a SIB byte (24h) because rsp=100b in ModR/M is reserved for "SIB
follows."  Every return-stack access costs 1 extra byte vs i386's
`[eax]`.  For example, `mov [rsp],rbx` = `48 89 1C 24` (4 bytes)
vs i386's `mov [eax],ebx` = `89 18` (2 bytes).

**No pop-to-memory instruction:** The i386 `>>r` loop used `pop [eax]`
— one instruction transferring from ESP (data stack) to [EAX] (call
stack).  x86-64 needs two instructions: `push qword [r15]` (3 bytes) +
`lea r15,[r15+8]` (4 bytes), making the loop body 12 bytes vs 8.

**Cell size:** All offsets multiply by 8 instead of 4.  The `+r`/`-r`
words use `shl rbx,3` instead of `shl ebx,2`.

#### Boot-Time Alias Limitation

In `ff.ff` (loaded at runtime), Lavarenne used tick-alias syntax:
`` r` ' alias r0` ``.  During boot (ff64.boot), this fails because
`'` (tick) needs a compilation context that doesn't exist at top level.
The workaround is simple wrapper definitions: `: r0` r` ;`.

#### The Test Framework (lib/64/test.ff)

With locals available, we ported `lib/test.ff` to create
`lib/64/test.ff`.  This provides the standard `t{ ... -> ... }t`
testing pattern:

```forth
needs test.ff
32 plan
testing locals
t{ 42 r0! r0 -> 42 }t
t{ 10 20 2 >>r r1 r0 -> 20 10 }t
tally-exit
```

The framework uses `>>rr` to save expected values on the return stack,
then compares them one-by-one against actual results.  Output is
TAP-compatible with colored pass/fail via `console.ff`.

**BREAK incompatibility:** The original `chkvals` used `BREAK` with
`BEGIN/REPEAT`.  In i386, `REPEAT` internally calls `END`, resolving
BREAK addresses.  In ff64, `REPEAT` does NOT call `END`, so BREAK is
only for `START/ENTER/END` loops.  The rewrite uses `;THEN` for early
exit on mismatch.

#### Consolidated Regression Tests (test/test64.ff)

All validated functionality from experiments 001–095 was consolidated
into a single permanent test file: `test/test64.ff`.  This 175-test
suite covers stack operations, memory, arithmetic, comparisons, flow
control, strings, dictionary, return stack, locals, and more.

Run it with:

```bash
./ff64 ': prompt ;' -f test/test64.ff
```

The `: prompt ;` suppresses the interactive prompt.  The file loads
`lib/64/test.ff` via `needs test.ff` and exits with code 0 on success,
1 on failure.

**Key insight from consolidation:** FreeForth comparisons (`=`, `<`,
`>`, `0=`, etc.) do NOT consume stack operands — they only set FLAGS.
After `a b =`, both `a` and `b` remain.  Every test involving
comparisons needs explicit cleanup (`2drop`, `nip`, `drop`).

**chkvals bug fix:** The original `chkvals` in `lib/64/test.ff` used
`depth TIMES rdrop LOOP` to clean the return stack on mismatch.  But
`rdrop` inside `TIMES/LOOP` dropped the loop counter, not the expected
values.  Fixed to `depth +r` (the locals word adjusts rsp directly).

**All previously broken words are now fixed (exp 097–105):**
- `++`/`--` — not broken; tests used wrong syntax (need `@` suffix)
- `within` — not broken; needs `0<> IF` pattern (FLAGS-based)
- `2over`/`pick` — fixed: `_pick_detect` comparison leak + i386 code
  in x86-64 path + SWAPbit masking
- Vector `!^`/`n^` — fixed: implemented as backtick macros (exp 097)
- `BEGIN/CASE/BREAK/END` — fixed: END no longer emits backward jump,
  unified flow control via shared `_begin` + mrk + cstack (exp 105)

---

## Part 34: Static Binary and Syscall Architecture

### The Problem: Why Dynamic Linking?

FreeForth2's ff64 binary is dynamically linked -- but only because of
three functions: `dlopen`, `dlsym`, and `dlerror`.  These power the
FFI (Foreign Function Interface) words `#lib`, `#fun`, and `#call`,
which let Forth code call into shared libraries at runtime.

Everything else -- file I/O, process control, memory management, the
REPL, the compiler -- already uses raw Linux syscalls via the `syscall`
word.  The dynamic linker adds startup overhead and a libc dependency
for just three functions.

### The Solution: Two Build Targets

Following Lavarenne's fflin.asm pattern, ff64 now supports two builds
from the **same assembly source**:

| Target | File | Format | Linker | FFI | Size |
|--------|------|--------|--------|-----|------|
| ff64   | fflin64.asm  | elf64 (object) | ld | Yes (dlopen) | ~377KB |
| ff64s  | fflin64s.asm | ELF64 executable 3 | None | Stubs (return 0) | ~89KB |

Both wrappers `include "ff64.asm"` -- they differ only in a single flag:

```fasm
; fflin64.asm (dynamic)        ; fflin64s.asm (static)
ffdl=1                         ; ffdl=1  <-- commented out
macro OSFORMAT {               ; macro OSFORMAT {
  if defined ffdl              ;   if defined ffdl
    format elf64               ;     ...
    ...                        ;   else
  else                         ;     format ELF64 executable 3
    format ELF64 executable 3  ;     entry _start
    entry _start               ;   end if
  end if                       ; }
}                              ; include "ff64.asm"
include "ff64.asm"
```

In ff64.asm, `extrn dlopen/dlsym/dlerror` and the FFI implementation
are wrapped in `if defined ffdl`.  The `else` branch provides stubs
that return 0 silently -- `dlsetup` stores 0 in `libc`, and all
libc-dependent guards (`libc@ 0- 0<> drop IF`) see 0 and skip.

### Syscall Word Migration (exp 108)

Four words migrated from assembly WORD64 entries to Forth in
fflin64.boot:

```forth
: read  ( addr # fd -- n ) >r swap r> 3 0 syscall ;
: openr ( addr # -- fd ) zt $1A4  0 rot 3 2 syscall ;
: openw ( addr # -- fd ) zt $1A4 $241 rot 3 2 syscall ;
: close ( fd -- n )  1 3 syscall ;
```

These match the i386 patterns from ff.help exactly.  The `>r swap r>`
in `read` reorders from Forth-natural `( addr # fd )` to the kernel's
`(rdi=fd, rsi=addr, rdx=count)`.

Three words **must** stay in assembly: `exit`, `write`, and `accept`
are used by ff64.boot which compiles before fflin64.boot.  The generic
`syscall` dispatcher stays in assembly; file loading is now pure Forth.

### Syscall Word Library (exp 109)

fflin64.boot now provides ~30 additional syscall wrappers:

```
File I/O:  lseek fstat stat access dup2 fcntl2 pipe ioctl3
Memory:    mmap munmap mprotect brk  + PROT_*/MAP_* constants
Process:   getpid fork execve wait4 exit_group
Dir/FS:    getcwd chdir mkdir rmdir unlink rename
Misc:      uname gettimeofday getrandom
```

All follow the convention: `( argN ... arg2 arg1 N sysnum syscall )`.
Arg1 (first C parameter) is on TOS.  For example, `getcwd(buf, size)`
becomes `size buf getcwd` -- the buffer address on top, closest to the
syscall dispatcher.

### OS/Architecture Separation (updated)

```
ff64.asm + ff64.boot      Architecture-specific (x86-64)
                           Compiler, macros, stack ops, flow control
                           SWAPbit, REPL, data stack, backtick words

fflin64io.asm              OS-specific assembly (Linux x86-64)
                           syscall, sigrestorer, dlopen/dlsym/dlcall

ff2lin.boot                OS-specific Forth (Linux)
                           Syscall wrappers, FFI, file loading,
                           SEGV handler, command-line, boot sequence

fflin64.asm / fflin64s.asm Build wrappers (dynamic / static)
                           OSFORMAT + OSINCLUDE macros, include ff64.asm
```

Future ports: ARM64 would replace ff64.asm/ff64.boot/fflin64io.asm but
reuse ff2lin.boot.  macOS would replace ff2lin.boot/fflin64io.asm but
reuse ff64.boot.

### Cross-Platform Library Unification (exp 145)

Experiment 145 closed the gap between i386 and x86-64 boot environments
so that `lib/` files work identically on both platforms without
`needs syscalls.ff`.

**`cell*` alias:**  `ff.boot` defines `4*' alias cell*'`, `ff64.boot`
defines `8*' alias cell*'`.  Library code uses `cell*` to compute
struct offsets portably: `3 cell*` gives 12 on i386 or 24 on x86-64.

**i386 syscall wrappers:**  `fflin.boot` gained 15 thin wrappers
matching `fflin64.boot` signatures: `_lseek`, `_stat`, `_fstat`,
`_lstat`, `ioctl3`, `select`, `nanosleep`, `time`, `gettimeofday`,
`chdir`, `ftruncate`, `tell`, `mmap`, `munmap`, plus struct constants
`_stat.sz` (98) and `st.size` (44).  Library files now call these
named words instead of `N _sys.foo syscall`.

**Cross-platform `lib/mmap.ff`:**  Replaces platform-specific
`lib/x86/mmap.ff` and `lib/x86-64/mmap.ff`.  Uses `cell*` for struct
field offsets and boot words for syscalls.  The `munmap` redefinition
uses the private-name-plus-alias pattern (`:. _mm_unmap ... munmap ... ;
_mm_unmap ' alias munmap`) because FreeForth headers are visible
immediately during compilation — `: munmap ... munmap ;` would
infinite-recurse.

**Metadata stays in the library:**  PROT_READ, MAP_SHARED, and other
mmap constants live in `mmap.ff`, not in boot.  Boot provides only the
thin syscall wrappers; the library owns its own protocol constants.

### Perl-Parity Expansion (exp 110)

DG observed that Perl provides a rich set of OS builtins (man perlfunc)
and directed a comparison.  Of ~76 Perl syscall builtins, ff64 covered
32 (42%) after exp 109.  The expansion strategy:

**Boot words (fflin64.boot):** Universal words that any program might
use — process control, filesystem metadata, time, locking.  22 new
words added:

```
Process:    getppid alarm setpgid getpgrp getpriority setpriority
Filesystem: lstat truncate flock link symlink readlink fchmod fchown
            chroot umask getdents64
Time:       time times nanosleep
Compound:   tell (lseek wrapper), wait (wait4 wrapper)
```

**Loadable library (lib/64/net.ff):** Domain-specific networking words.
DG's directive: "networking goes in a library, not boot."

```
Syscalls:     socket connect bind listen accept4 shutdown
              sendto recvfrom socketpair setsockopt getsockopt
              getsockname getpeername pselect6
Convenience:  send recv (sendto/recvfrom with NULL address args)
Byte-order:   htons (16-bit network byte swap)
Constants:    AF_UNIX AF_INET AF_INET6 SOCK_STREAM SOCK_DGRAM
              SOL_SOCKET INADDR_LOOPBACK etc.
```

**Key discovery — inline strings are NUL-terminated:**

DG spotted a note in ff.ff: "literal strings are already
zero-terminated."  Confirmed in ff64.asm line 1291: the string compiler
explicitly writes `mov byte [rbp], 0` after every inline string.  This
means `zt` is unnecessary for inline string literals — it exists for
dynamically-constructed strings in buffers.  The `openr`/`openw`
definitions use `zt drop` but could use plain `drop`.

**The `place` gotcha:** FreeForth's `place ( @src # @dst -- @dst )` is
raw memcpy.  It does NOT store a count prefix like standard Forth's
PLACE.  It returns `@dst`, not `@dst+len`.  Code that does
`"str" buf place 0 swap c!` writes NUL at buf[0], not at buf[len].
Correct: `"str" buf place N + 0 swap c!` with known length N.

After this experiment, 52 of 76 Perl syscall builtins are covered (68%).

## Part 35: Cross-Architecture Constants and Test Porting

### The `cell` and `[64]` Constants

As the test suite porting effort progressed, we needed a way to write
Forth source files that work on both i386 and x86-64.  The solution:

```
\ In ff64.boot:
8 constant cell
cell 4 - constant [64]`

\ In ff.boot:
4 constant cell
cell 4 - constant [64]`
```

`cell` is a **plain constant** (not backtick) — the cell size in bytes
(8 on x86-64, 4 on i386).  It's useful for portable arithmetic:

```
cell allot       \ allocate one cell
addr cell + @    \ fetch next cell
n cell *         \ convert count to bytes
```

**Why `cell` is NOT backtick:** backtick constants push their value
onto the compile-time data stack (for other macros to consume at
compile time).  Nothing consumes `cell` at compile time — it's a
runtime value.  Defining it as `constant cell\`` caused a compile-time
stack leak: every definition using `cell` left an extra 8 on the
stack.  Plain `constant cell` hits the normal lookup path (ct=1 →
`_lit_compile`), which emits the value into the generated code with
no compile-time residue.

`[64]` is derived from `cell` for conditional compilation: `cell 4 -`
gives 4 (truthy) on 64-bit and 0 (falsy) on 32-bit.  `[64]` IS a
backtick constant because `[IF]` consumes it at compile time:

```
[64] [IF]
  \ 64-bit specific code
[ELSE]
  \ 32-bit specific code
[THEN]
```

### Porting test/common1.ff

The i386 test suite test/common1.ff has 122 tests.  Eight of them
depend on cell size or stack layout:

| Test | i386 | ff64 | Reason |
|------|-------|------|--------|
| xxr alias | xt equality | wrapper compiles | boot.min strips `+` lines |
| rp@ @ | return address = anon:' | nonzero check | call structure differs |
| sp@ @ = NOS | memory stack | nonzero check | register-based stack |
| bswap | 32-bit value | 64-bit value | cell-sized operation |
| 2@/dup@ | 4-byte allot/offset | 8-byte allot/offset | cell size |
| @+ | x 4+ | x 8+ | cell-sized advance |
| 2! | aa 4+ @ | aa 8+ @ | cell-sized offset |

Each uses `[64] [IF]` / `[ELSE]` / `[THEN]` with the **same number of
tests** in each branch.  Both architectures run exactly 122 tests —
different implementations, same count, same rigor.

### rp@ and sp@ Macros

Added to ff64.boot for return/data stack pointer access:

- `rp@` pushes RSP (the x86-64 call/return stack pointer)
- `sp@` pushes R15 (the memory stack base pointer)

Note: ff64's register-based stack means `sp@` does NOT give NOS like
i386's `sp@` does.  The top 9 items live in registers (rbx, r8–r15
minus r15), and R15 points to the overflow area.  This is why the sp@
test uses a nonzero check instead of the i386's `sp@ @ → NOS` test.

---

## Part 36: Library Unification (Experiments 117–123)

With the x86-64 port functionally complete and a growing library of
Forth files, the next challenge was structural: the same logical
library (file I/O, console control, time) existed in two copies — one
in `lib/` (originally i386-only) and one in `lib/x86-64/`.  Most of
the code was identical Forth.  The differences were syscall numbers
and a few struct layout constants.

### The problem

Before unification, the directory layout was:

```
lib/           ← i386-only library files
lib/x86-64/   ← x86-64-only library files (formerly lib/64/)
```

Files like `fileops.ff`, `console.ff`, `shell.ff`, and `time.ff`
existed in both directories with 90%+ identical Forth code.  Bug fixes
had to be applied twice.  New features diverged silently.

### Phase 1: Directory restructuring (Exp 117)

Reorganized into three tiers:

```
lib/           ← shared (portable Forth, works on both arches)
lib/x86/       ← i386-specific files
lib/x86-64/    ← x86-64-specific files
```

Moved files that were already pure Forth — `pno.ff`, `ior.ff`,
`malloc.ff` — into shared `lib/`.  Updated FFPATH on both arches so
the search order is:

- **x86-64:** `lib/x86-64` → `lib` → `.`
- **i386:** `.` → `lib/x86` → `lib`

Architecture-specific files shadow shared ones: if `lib/x86-64/foo.ff`
and `lib/foo.ff` both exist, the arch-specific one wins.

### Phase 2: fixup unification (Exp 119–120)

The `fixup` word (runtime relocation for forward references) had an
architecture difference: i386 used `rdrop` before `r> 5-` (expecting
CALL), x86-64 relied on tail-call optimization (JMP, no extra return
address).  Unified both to use tail-call convention — remove `rdrop`,
require `;` after fixup in hidden definitions.  Both arches already had
tail-call optimization (`_semisemi` in ff.asm, `_semisemi` in ff64.asm).

### Phase 3: Syscall number tables (Exp 122)

The key innovation.  Instead of `[64] [IF]` conditionals scattered
through library files, we created arch-specific syscall tables:

**lib/x86/syscalls.ff:**
```forth
 12 constant _sys.chdir     54 constant _sys.ioctl
 19 constant _sys.lseek    142 constant _sys.select
195 constant _sys.stat       78 constant _sys.gettimeofday
 13 constant _sys.time      162 constant _sys.nanosleep
 98 constant _stat.sz        44 constant st.size
```

**lib/x86-64/syscalls.ff:**
```forth
 80 constant _sys.chdir     16 constant _sys.ioctl
  8 constant _sys.lseek     23 constant _sys.select
  4 constant _sys.stat      96 constant _sys.gettimeofday
201 constant _sys.time       35 constant _sys.nanosleep
144 constant _stat.sz        48 constant st.size
```

Shared library files just do `needs syscalls.ff` and use symbolic
names.  FFPATH ensures the correct arch-specific file is loaded.

**Example: shared fileops.ff** (works on both architectures):
```forth
needs syscalls.ff
: lseek _sys.lseek sys3 ?ior ;
: fstat _sys.stat _stat.sz erase _sys.stat sys2 ?ior ;
: fsize fstat _stat.sz + st.size + @ ;
```

The `_stat.sz erase` ensures stat buffers start zeroed — important for
system interop where stale buffer data could cause subtle bugs.

### Phase 3 result: ff.ff trimmed

The i386 library file `ff.ff` went from ~188 lines to 98.  Inline
definitions of fileops, console, shell, time, colors, and stack-show
were replaced with `needs` calls to shared files.  What remains:
callback (i386 machine code), locals (i386 machine code), and
FFHIDE/hidepvt.

### The `cell` backtick constant bug (Exp 123)

During unification, a compile-time stack leak was traced to `cell`
being defined as `8 constant cell\`` (backtick constant).

**How the compiler's two-phase lookup works:**

1. **Backtick lookup** (first): append `` ` `` to the token, search.
   - ct bit 0 set → push xt onto **compile-time data stack**
   - ct bit 0 clear → **execute immediately** (macro)

2. **Normal lookup** (fallback):
   - ct=0 → compile a CALL
   - ct=1 → compile literal via `_lit_compile`
   - ct≥2 → execute immediately

Backtick constants with ct bit 0 push their value onto the compile-time
stack for **other macros to consume**.  `[1]\``, `[0]\``, and `[64]\``
work this way — `[IF]\`` consumes them.  But `cell` is a runtime value.
Nothing consumes the compile-time 8.

**Fix:** `8 constant cell` (plain constant, no backtick).  Now the
compiler's backtick lookup fails, normal lookup finds ct=1, and
`_lit_compile` emits the value into generated code.  No compile-time
residue.

### Directory layout after unification

```
lib/
  console.ff      ← shared: terminal control, key?, colors
  fileops.ff      ← shared: lseek, stat, fsize, fexist
  ior.ff          ← shared: error reporting
  malloc.ff       ← shared: heap allocation
  pno.ff          ← shared: pictured numeric output
  shell.ff        ← shared: chdir, system, getenv, getpid
  time.ff         ← shared: ms@, ms, .now, .elapsed
  x86/
    fixup.ff      ← i386: runtime relocation
    syscalls.ff   ← i386: Linux syscall numbers
  x86-64/
    dis.ff        ← x86-64: disassembler support
    fixup.ff      ← x86-64: runtime relocation with trampolines
    see64.ff      ← x86-64: decompiler
    syscalls.ff   ← x86-64: Linux syscall numbers
```

---

## Part 37: File Loading and Memory Layout (Experiments 139–142)

### The eval-based file loading design

FreeForth loads files entirely in Forth — there is no assembly file loader.
This matches Christophe Lavarenne's i386 design exactly. The mechanism:

1. **`eval` ( addr len -- )**: Saves `>in` and `tp` on the return stack,
   sets them to span the given buffer, calls `compiler`, then restores
   the saved values. This makes `eval` re-entrant: nested `eval` calls
   (from nested `needs`) simply push another frame.

   ```forth
   : eval >in@ tp@ 2>r over+ tp! >in! compiler 2r> tp! >in! ;
   ```

2. **`needed` ( addr len -- )**: The file-loading word in `fflin64.boot`.
   Checks whether the file is already loaded (via `find` on the filename
   with a backtick appended). If not, resolves the path via `openlib`,
   opens the file, creates a `marker` + `pvtmargin`, reads the file into
   `tib` at `tp`, skips any shebang line, and calls `eval`.

3. **`needs`** (backtick macro): The user-facing word. Defined as
   `` ; wsparse needed ;` ``. The critical detail: the leading `;`
   flushes anonymous code before `needed` runs. After the flush,
   `[anon]` = `rbp` (fresh), so `needed`'s inner compilation at `[anon]`
   can't overwrite anything. This is the safety mechanism that prevents
   the code-overwrite problem.

### The code-overwrite problem

When `_semi` executes anonymous code, it resets `rbp` to `[anon]` and
calls. If `needed` → `eval` → `compiler` runs inside that anonymous code,
the compiler writes at `rbp` = `[anon]` — overwriting the executing code.
For small inner files (< ~10 bytes of output), the return address in the
anonymous code isn't reached yet, so it works. For larger files, SEGV.

Both i386 and ff64 have this vulnerability when `needed` is called
directly from anonymous code. It's by design — `needed` is an internal
word. The user-facing `needs` prevents it via the `;` flush.

### tib as a file stack

The `tib` buffer (256KB, from the i386 design) serves as an implicit file
stack. The source being compiled lives at `[>in]` through `[tp]`. When
`eval` is called (during `needs`), it:

1. Saves `>in`/`tp` on the return stack
2. Sets `>in`/`tp` to span the new source (just read from file, at `tp`)
3. Calls `compiler`, which consumes the inner source
4. Restores `>in`/`tp`, resuming the outer source

The file's content is read at `tp` (end of current source), so multiple
nested `needs` stack upward in the tib buffer. The i386 comment
(ff.asm:246–247): "tib is a file stack."

### Memory map

The ff64 memory layout, in order of address:

```
[ELF headers + PLT + GOT]        ← dynamic linker structures
[.flat section: code + data]      ← PROGBITS, in file
  code and data
  dl_errbuf (256B)                ← dlerror buffer
  numbuf (21B)                    ← number output scratch
  cstack (128B) + csp             ← compile-time stack
  headbuf (64KB)                  ← headers grow down from heads64
  heads64: GENWORDS64             ← initial dictionary entries
  boot64: "ff64.boot.min"        ← embedded boot source
[.bss section: buffers]           ← NOBITS, NOT in file
  tib (256KB)                     ← source buffer / file stack
  eob (1KB)                       ← end-of-buffer scratch
  helpbuf (128KB)                 ← help file reading
  dstack (8KB)                    ← data stack (r15 points here)
  codebuf (64KB)                  ← compiled code goes here (rbp)
```

### BSS: on-disk zeros vs demand paging

ELF distinguishes PROGBITS (data in the file) from NOBITS (not in file,
zero-filled at runtime). In the LOAD program header, `FileSiz` is bytes
on disk and `MemSiz` is bytes in memory. When `MemSiz > FileSiz`, the
kernel maps the extra as anonymous zero pages, allocated on demand.

The i386 always had this: `section '.bss'` (ff.asm:1335) puts the
512KB heap, 256KB tib, and 1KB eob in NOBITS. Binary size: 28KB on
disk, 784KB at runtime.

ff64 initially lacked a `.bss` section — all `rb` buffers lived in
`.flat` (PROGBITS), storing ~457KB of zeros on disk. Adding
`section '.bss'` (guarded by `if defined ffdl` for the dynamic build)
reduced the binary from 572KB to 104KB.

**Rule:** New uninitialized buffers go after the `section '.bss'`
directive in ff64.asm. Never put `rb` in `.flat` — it bloats the binary.
`headbuf` is the exception: it stays in `.flat` because `heads64:
GENWORDS64` (initialized data) immediately follows it.

### Historical note: the _loadfile era (experiments 063–140)

ff64 originally had a ~107-line assembly `_loadfile` with its own
`filebuf` (64KB), `namebuf` (256B), and `hereatexec` variable. This was
an ff64 invention — the i386 never had it. It caused three distinct bugs
during development (rbp preservation, hereatexec overwrite, hereatexec
advancement). All were symptoms of the same root cause: file loading
belonged in Forth, not assembly.

Experiments 139 (eval proof-of-concept), 140 (tib/eob buffer
unification), and 141 (removal of `_loadfile`) progressively replaced
the assembly mechanism with the i386 Forth pattern. Experiment 142
added the `.bss` section to recover the binary size.

## Part 38: The x86-64 Prefix Trap (Experiment 146)

### The bug class

x86-64 inherited x86's prefix system but added a new player: the REX
prefix. The REX.W bit (bit 3 of the REX byte, value `$48`) promotes
operand size to 64 bits. This interacts badly with the older `$66`
prefix (operand-size override to 16 bits): **when both are present,
REX.W wins.**

This is documented in the Intel manual but easy to miss during porting.
On i386, there is no REX prefix, so fall-through patterns that prepend
`$66` to a store macro work correctly. On x86-64, the same fall-through
picks up a REX.W byte and silently becomes a 64-bit operation.

### How it manifested

FreeForth's backtick macros use elegant fall-through patterns. The i386
`2dupw!` falls through to `2dup!`, prepending only the `$66` prefix:

```forth
\ i386 — works: 66 89 13 = mov word [ebx], dx
: 2dupw!` $66, ,1
: 2dup!`  $8913, s09 ;
```

The x86-64 port added REX.W to `2dup!` for 64-bit stores:

```forth
\ x86-64 — broken: 66 48 89 13 = mov qword [rbx], rdx (REX.W wins)
: 2dupw!` $66, ,1
: 2dup!`  $48, ,1 $1389, s09 ;
```

The fix breaks the fall-through:

```forth
\ x86-64 — fixed: separate bodies
: 2dupw!` $66, ,1 $1389, s09 ;   \ 66 89 13 = mov word [rbx], dx
: 2dup!`  $48, ,1 $1389, s09 ;   \ 48 89 13 = mov qword [rbx], rdx
```

### The x86-64 prefix precedence rules

For the future historian, these are the rules that matter for FreeForth:

| Prefixes present    | Effective operand size | Notes                    |
|---------------------|----------------------|--------------------------|
| (none)              | 32 bits              | Default on x86-64        |
| `$66` alone         | 16 bits              | Operand-size override    |
| `$48` (REX.W) alone | 64 bits             | 64-bit promotion         |
| `$66` + `$48`       | **64 bits**          | REX.W overrides `$66`    |

The `$66` prefix is only effective when no REX.W is present. Any
fall-through from a `$66`-emitting macro into a REX.W-emitting macro
will silently produce 64-bit operations.

### Affected operations

Only `2dupw!` was affected. The other 16-bit operation, `dupw@`
(16-bit fetch with address preservation), was already correct because
it uses `movzx` (`0F B7`), which doesn't need REX.W:

```forth
: dupw@` over` $0F, ,1 $1AB7, s09 ;   \ 0F B7 1A = movzx ebx, word [rdx]
```

The `movzx` instruction always zero-extends into the full register
without needing a REX.W prefix. The store instruction `mov [reg], reg`
needs explicit size control via prefixes, which is where the conflict
arose.

### The pattern of one-line port bugs

This is the third one-line bug with outsized impact in the ff64 port:

1. **`_parse` DUP1 vs DROP1** (exp 038): The x86-64 entry sequence
   consumed an extra stack item on every call to `parse`. Caused
   cumulative compile-time stack corruption visible only in large
   files. One instruction change fixed it.

2. **`_pick_detect` encoding** (exp 104): The literal-detection code
   checked for i386-specific byte sequences. The x86-64 compiler
   emits different sequences. One comparison mask fixed it.

3. **`2dupw!` REX.W override** (exp 146): A fall-through pattern that
   worked on i386 produced conflicting prefixes on x86-64. Breaking
   one fall-through fixed it.

Each was discovered by comparing behavior between architectures — not
by reading the compiler source. The generated machine code is always
the ground truth.

## Part 39: Anonymous Code at HERE — An Instruction-Level Walkthrough

FreeForth's compiler has no interpreter. Every token — even at the
REPL — is compiled to machine code and then executed. This has a
subtle consequence: **anonymous top-level code and the data you
`create` inside it share the same address.** Writing to that address
overwrites the code that is currently executing.

This section walks through the bug instruction-by-instruction.

### The compilation model

When FreeForth encounters tokens between `;` boundaries, it compiles
them into an anonymous block at HERE (the register `rbp`, the
compilation pointer). When `;` is reached, it appends a `ret`,
**resets HERE back to the block's start address** (de-allocating
the compiled code), then calls the block. After the block returns,
HERE stays wherever the block left it — if `allot` ran during
execution, HERE has advanced and the allotted space is preserved.

`create foo` is a compile-time operation: it makes a dictionary header
and records `foo = HERE` at that moment. It emits no code into the
block. So `foo`'s address equals the address where the anonymous
block's code begins.

### Proof: `create` and `here` return the same address

```forth
create _t
."_t__=_" _t . cr
."here=_" here . cr
."diff=_" _t here - . cr
0 exit ;
```

Output:
```
_t  = 4343838
here= 4343838
diff= 0
```

Wait — `here` at runtime returns the *current* rbp. Shouldn't rbp
have advanced past the compiled code? No: `_semi` resets rbp to
`[anon]` (the block's start address) before calling the block — the
i386 comment says "de-allocate." The compiled code bytes are treated
as temporary; HERE rewinds to reclaim them. So at runtime, both `_t`
and `here` return the block's start. They are the same address. And
the compiled machine code *lives at that address* (still executable
even though HERE has rewound past it).

### The safe version — annotated machine code

Here is the `see` output for a version that doesn't crash (using
`2drop drop` instead of `cmove`). The source:

```forth
create _t 64 dup allot _t swap 2drop drop ;
```

The compiled machine code, annotated with Forth-level operations:

```
          ┌─ _t points here (= start of anonymous block)
          │
 ADDRESS  │  BYTES           INSTRUCTION         FORTH
 ──────── ▼  ──────────────  ──────────────────── ──────────────
 42481e:     4d 8d 7f f8     lea r15,[r15-8]    ┐
 424822:     49 89 17        mov [r15],rdx      ┤ push 64
 424825:     48 89 da        mov rdx,rbx        ┤ (literal: NOS→mem,
 424828:     bb 40000000     mov ebx,0x40       ┘  TOS=64)

 42482d:     4d 8d 7f f8     lea r15,[r15-8]    ┐
 424831:     49 89 17        mov [r15],rdx      ┤ dup
 424834:     48 89 da        mov rdx,rbx        ┘ (NOS=TOS, copy 64)

 424837:     48 01 dd        add rbp,rbx        ← allot: HERE += 64
 42483a:     49 8b 1f        mov rbx,[r15]      ┐ drop
 42483d:     4d 8d 7f 08     lea r15,[r15+8]    ┘ (consume dup'd 64)

 424841:     48 87 da        xchg rbx,rdx       ← swap

 424844:     4d 8d 7f f8     lea r15,[r15-8]    ┐
 424848:     49 89 17        mov [r15],rdx      ┤ push _t
 42484b:     48 89 da        mov rdx,rbx        ┤ (literal: loads
 42484e:     bb 1e484200     mov ebx,0x42481e   ┘  address 0x42481e)
                                 ▲
                                 └─ THIS IS THE SAME ADDRESS
                                    as the first instruction!

 424853:     49 8b 17        mov rdx,[r15]      ┐
 424856:     4d 8d 7f 08     lea r15,[r15+8]    ┤ 2drop drop
 42485a:     49 8b 1f        mov rbx,[r15]      ┤ (discard 3 items:
 42485d:     4d 8d 7f 08     lea r15,[r15+8]    ┤  _t, 64, src)
 424861:     49 8b 17        mov rdx,[r15]      ┤
 424864:     4d 8d 7f 08     lea r15,[r15+8]    ┘
 424868:     c3              ret                ← return to REPL
```

The critical detail is at offset `42484e`: `mov ebx, 0x42481e`.
That instruction loads the address `0x42481e` — the value of `_t` —
which is *the address of the first instruction in this very block*.

### The crash version — what cmove does

Now consider the real pattern — a source buffer on the stack, then
`create` + `allot` + `cmove`:

```forth
\ Assume (src-addr) is on the stack from an earlier computation.
\ In exp/147, this was tp@ pointing at tib data (111 bytes).

src-addr 111
create _t dup allot _t swap cmove ;
```

Stack trace through the Forth words (stack grows to the right,
TOS on the right, matching standard `( -- )` notation):

```
                                3rd        NOS         TOS
 src-addr 111             →             src-addr       111
 create _t                →             src-addr       111   (compile-time: _t = HERE)
 dup                      →  src-addr     111          111
 allot                    →             src-addr       111   (HERE += 111)
 _t                       →  src-addr     111       0x42481e
 swap                     →  src-addr   0x42481e      111
 cmove ( src dest count ) →                                  (copies 111 bytes
                                                              from src-addr
                                                              to 0x42481e)
```

The compiled machine code is the same prefix as the safe version
(offsets `42481e` through `424841`) but with `cmove` instead of
`2drop drop`:

```
          ┌─ _t points here (= start of block)
          │
 ADDRESS  │  BYTES           INSTRUCTION        FORTH
 ──────── ▼  ──────────────  ────────────────── ──────
 42481e:     4d 8d 7f f8     lea r15,[r15-8]   ┐ push 111
    ...      (same as above through allot)      ┘
 424841:     48 87 da        xchg rbx,rdx      ← swap
 424844:     4d 8d 7f f8     lea r15,[r15-8]   ┐
    ...                                        ┤ push _t
 42484e:     bb 1e484200     mov ebx,0x42481e  ┘

 424853:     48 89 df        mov rdi,rbx       ┐ cmove setup:
 424856:     48 89 d1        mov rcx,rdx       ┤  rdi = dest = _t = 0x42481e
 424859:     49 8b 37        mov rsi,[r15]     ┤  rcx = count = 111
 42485c:     49 8b 57 08     mov rdx,[r15+8]   ┤  rsi = source = src-addr
 424860:     49 83 c7 10     add r15,0x10      ┤  (pop 2 items from mem stack)
 424864:     f3 a4           rep movsb          ┘ THE COPY: 111 bytes → 0x42481e

 424866:     49 8b 1f        mov rbx,[r15]     ┐ post-cmove
 424869:     4d 8d 7f 08     lea r15,[r15+8]   ┤ cleanup +
 42486d:     48 87 da        xchg rbx,rdx      ┤ swap +
 424870:     c3              ret                ┘ return
```

`rep movsb` at `424864` copies bytes one at a time, from `rsi`
(source) to `rdi` (destination = `_t` = `0x42481e`), `rcx` times.

**It writes directly over the machine code starting at `42481e`.**

The `rep movsb` instruction is at offset 70 (`424864 − 42481e`).
The post-cmove cleanup starts at offset 72 (`424866`).

With a **small** count (say 64): the overwrite covers offsets 0–63.
The cleanup at offset 72 is untouched. The CPU finishes `rep movsb`,
fetches the intact instruction at `424866`, and continues.
*This barely doesn't crash.*

With **111 bytes** (the real exp/147 case): the overwrite covers
offsets 0–110 — well past offset 72. After `rep movsb` finishes,
the CPU fetches the byte at `424866`, which is now whatever data
was in the source buffer. It tries to decode this as an instruction
and crashes.

### A picture of the damage

```
Memory address:  42481e                424864  424866  424870
                 │                      │       │       │
Before cmove:    [  machine code ...    │ rep   │cleanup│ ret ]
                 │                      │movsb  │       │
                 ▼ _t points here       │       │       │
After cmove:     [ source data ........ │ rep   │ data  │ data]
                 │◄── 64 bytes ────────►│movsb  │       │
                                               ▲
                 Safe: 64 < 70                 │
                                               │
After cmove:     [ source data .................................]
                 │◄────────── 111 bytes ───────────────────────►│
                                               ▲
                 CRASH: 111 > 70 ──────────────┘
                 CPU fetches garbage at 424866
```

### Why small allots survive (the see.ff pattern)

Lavarenne's code and DG's `see.ff` use patterns like:

```forth
create regs64 pvt 32 allot "rax_rcx_rdx_rbx..." regs64 swap move
```

This works because 32 bytes is much smaller than the anonymous code
that follows it. The `move` instruction (at some offset like 80+)
is far past the 32-byte blast radius. The overwritten bytes are all
*before* the currently-executing instruction — already fetched and
decoded by the CPU. No crash.

The exp/147 FFPATH prototype allotted 111 bytes — the full segment
structure — which exceeded the anonymous code size and destroyed
the instructions after `cmove`.

### The fix: split with `;`

Separate the allot and the write into two anonymous blocks:

```forth
\ Block 1: measure and claim space
here _dst ! _sz @ allot ;

\ Block 2: copy data into the claimed space
tp@ c@+ + 1+ _dst @ _sz @ cmove ;
```

Why this works — the `_semi` mechanism in detail:

1. Block 1 compiles at HERE (rbp). The compiled code includes the
   inlined `allot` (`add rbp,TOS`). When `;` fires, `_semi` does
   four things:
   - Appends `ret` (0xC3) and advances rbp past it.
   - **Rewinds rbp to `[anon]`** — the block's start address.
     The compiled code is still in memory but HERE no longer
     points past it.
   - **Calls the block.** During execution, `allot` runs
     `add rbp, _sz`, advancing rbp past the allotted data.
     Now rbp = `[anon]` + `_sz`.
   - **Saves rbp to `[anon]`** — `mov [anon], rbp`. The new
     `[anon]` is past the allotted space. This is how `allot`'s
     effect survives: `_semi` captures whatever rbp the block
     left behind.

2. Block 2 compiles at the *new* `[anon]` — past the allotted space.
   `cmove` writes to `_dst` (= old `[anon]` = start of allotted
   space), which is *before* block 2's code. No overlap. No crash.

```
 Block 1's code  │  Allotted data   │  Block 2's code
 ────────────────│──────────────────│─────────────────
                 │◄── _sz bytes ──►│
                 ▲                  ▲
                 _dst               HERE when block 2 compiles
                                    (cmove writes ← not here →)
```

### The lesson

`create` in an anonymous block records *the address of the code you
are currently writing*. Writing to that address is writing over
yourself. The compiler, the data, and the executing code all share
the same address space — there is no separation. This is not a bug;
it is the consequence of a system with no interpreter, no separate
data segment, and no memory protection. Everything is HERE.

---

## Part 40: The REPL Coroutine — An Annotated Walkthrough (Experiment 150)

This part traces the complete lifecycle of a FreeForth session — from
the moment the binary starts to the moment you type `bye`. It is both
the culmination of the x86-64 port and a window into Lavarenne's most
elegant design: a Read-Eval-Print Loop built from three Forth words
that share a single machine-code loop across definition boundaries.

### Background: from self-contained to coroutine

The early x86-64 port (Part 32) used a self-contained `_top` with a
`BEGIN`/`AGAIN` loop — all REPL logic in one word. This worked but
diverged from Lavarenne's i386 design, where `_exec` and `_top` form
a *cross-word* loop: `_exec` ends with `START _eval ENTER`, `_top`
ends with `0- 0= UNTIL`. The `START`...`UNTIL` pair compiles a single
machine-code loop whose backward jump crosses the boundary between
`_exec` and `_top`.

Experiment 150 aligned the x86-64 boot with this i386 pattern exactly.
The result is six words totaling 21 lines of Forth source that
implement the entire REPL, error recovery, dictionary cleanup, and
graceful exit.

### The source (ff2.boot lines 804–818)

```forth
( REPL coroutine — _exec/_top form cross-word START...UNTIL loop )
( bye must follow _top: UNTIL falls through to bye on EOF )
:. _back >in@ 1- dup BEGIN tib <> drop WHILE 1- dupc@ 10- drop 0= TILL 1+ END
   swap over- type ;
:. _eval eval. '
:. _exec catch 0;  _back ."_<-error:_" c@+ type cr  2drop
  anon@ 0- 0= IF drop H@ dup@ swap h.sz+ c@+ + 1+ H! THEN
  here - allot  0 SC c! anon:` 0<>`  START _eval ENTER
:^ _top pvt ui 0 noauto! tib 4096 under accept 0- 0= UNTIL
: bye` ;` cr 0 exit ;
:^ doargv argc 1- 0; 1 _argv swap 2+ _argv over- tuck tib place swap _eval ;
[64] [IF] fflin64.boot [ELSE] fflin.boot [THEN]
:. _boot ossetup _postboot _top ;
_boot ' _bootxt! _boot ' >r ;
```

Every word explained:

**`eval.`** (defined earlier, line 800) — the evaluator.
Saves `>in` and `tp` on the return stack, sets up the text pointers
to cover the input buffer, calls `compiler` (the heart of FreeForth —
parse, look up, compile, repeat), calls `_auto` (auto-execute the
anonymous block if `noauto` is clear), restores `>in`/`tp`. This is
identical to the i386's `eval`.

**`_back`** — error context printer.
Walks backward from the current parse position (`>in`) to find the
start of the current line (scanning for LF=10), then prints from
there to `>in`. This shows the user *where* in the input the error
occurred.

**`_eval`** — a one-liner: `eval. '`. The `'` (tick) is a postfix
macro that uncompiles the preceding `call eval.` and replaces it
with `push <eval.'s XT>`. So `_eval` pushes eval.'s execution
token onto the data stack. It then falls through to `_exec`.

**`_exec`** — the error-handling wrapper. Calls `catch(eval.)`.
On success (0 returned), returns immediately (`0;`). On error:
prints context (`_back`), prints the error message, cleans up
the dictionary if a named definition was interrupted, resets `here`
and `SC`, then falls through to the `START _eval ENTER` loop
re-entry.

**`_top`** — the input loop. Defined with `:^` (vector), making
it callable through a trampoline. Calls `ui` (prompt), clears
`noauto`, calls `accept` to read a line from stdin. Tests the
return value: nonzero means input received, UNTIL loops back;
zero means EOF, UNTIL falls through to `bye\``.

**`bye\``** — graceful exit. Calls `;\`` (flush pending code),
prints a final newline, calls `exit(0)`. Must be defined
*immediately after* `_top` because UNTIL's fall-through lands here.

**`_boot`** — entry point. Calls `ossetup` (Linux initialization),
`_postboot` (SEGV handler, file loading, `doargv`), then tail-calls
`_top` to enter the REPL. The `_boot ' >r ;` trampoline on the
last line stashes `_boot`'s XT on the return stack so the anonymous
block's `;` "returns" to `_boot`.

### The cross-word loop in machine code

Here is the compiled x86-64 code for the REPL, annotated with
the Forth source that generated each instruction. Addresses are
from a live ff64 session (your build will differ).

**_eval** (0x41bd71) — push eval.'s XT, fall through to _exec:
```asm
_eval:
  lea    r15,[r15-8]          ; \
  mov    [r15],rdx            ;  | dup  (push NOS to memory stack)
  mov    edx, 0x41bc6a        ;  eval. '  (NOS = eval.'s XT as literal)
                              ;  fall through to _exec
```

**_exec** (0x41bd7d) — catch, early return on success:
```asm
_exec:
  xchg   rbx,rdx              ; swap eval. XT into TOS for catch
  call   catch                 ; catch( eval. ) → 0 on success, err on throw
  test   rbx,rbx              ; \  0;  — test result
  jnz    _exec_error           ;  |     if nonzero → error handler
  mov    rbx,[r15]             ;  |     success: drop the 0
  lea    r15,[r15+8]           ;  |
  xchg   rbx,rdx              ;  /
  ret                          ; return to caller (→ _top trampoline)
```

**_exec error handler** (0x41bd99) — recover and re-enter loop:
```asm
_exec_error:
  call   _back                 ; print input context up to error point
  call   _litstr               ; ."_<-error:_" (inline string follows)
  ... 10 bytes of string data: " <-error: " ...
  movzx  rdx,byte[rbx]        ; \  c@+ type cr — print counted error string
  inc    rbx                   ;  |
  xchg   rbx,rdx              ;  |
  call   type                  ;  |
  call   cr                    ;  /
  ; 2drop — discard catch's two return values
  mov    rbx,[r15]             ; \
  lea    r15,[r15+8]           ;  | 2drop
  mov    rdx,[r15]             ;  |
  lea    r15,[r15+8]           ;  /
  ; anon@ 0- 0= IF ... THEN — unlink partial definition from dictionary
  mov    rbx,[anon]            ; anon@
  test   rbx,rbx              ; 0-
  jne    _skip_unlink          ; 0= IF (skip if anon is nonzero)
  ; ... dictionary cleanup: H@ dup@ swap h.sz+ c@+ + 1+ H!
  ; (walks the header chain to unlink the partial entry)
_skip_unlink:
  ; here - allot — reset HERE to pre-error position
  mov    rdx,rbp               ; here
  sub    rbx,rdx               ; -  (anon - here = negative offset)
  add    rbp,rbx               ; allot (rbp += offset, restoring old HERE)
  ; 0 SC c! — clear SWAPbit state
  mov    ebx, 0                ; 0
  mov    [SC],dl               ; SC c!
  ; anon:` — reset anonymous block to HERE
  call   anon:`                ; mov [anon],rbp; clear flags
  ; 0<>` — preload nonzero condition for UNTIL
  call   0<>`                  ; store JNZ opcode in cond_jmp
  ; START — emit forward jump (skip past call _eval on first recovery)
  jmp    _top                  ; forward jump resolved by ENTER → _top entry
  ; _eval — the UNTIL backward-jump target
loop_start:
  call   _eval                 ; START marks here; UNTIL jumps back here
  ; ENTER — resolved _top's forward reference
```

**_top** (0x41beb0) — prompt, read, loop:
```asm
_top:                            ; :^ creates vector trampoline
  push   _top_body              ;   push body address
  ret                           ;   jump to body (ret pops and goes there)
_top_body:
  call   ui                     ; ui — call prompt vector (prints "> ")
  mov    ebx, 0                 ; \  0 noauto!
  mov    [noauto],rbx           ; /
  mov    ebx, tib               ; \
  mov    edx, 0x1000            ;  | tib 4096 under accept
  ; ... under swaps TOS/NOS ...
  call   accept                 ; /  accept( buf count -- nbytes )
  test   rbx,rbx               ; 0-  (or rbx,rbx — sets ZF if zero)
                                ; 0=  (compile-time only: stores JZ in cond_jmp)
                                ; UNTIL inverts: JZ → JNZ
  jne    loop_start             ; UNTIL: loop back if nbytes ≠ 0
  ; fall through on EOF (nbytes = 0) → bye`
```

**bye\`** (0x41bf0e) — flush and exit:
```asm
bye`:
  call   ;`                     ; ;`  — flush any pending anonymous code
  call   cr                     ; cr  — final newline
  mov    ebx, 0                 ; 0   — exit code
  jmp    exit                   ; exit — sys_exit(0), game over
```

**_boot** (0x41d17e) — the entry point:
```asm
_boot:
  call   ossetup                ; Linux-specific init (sigaction, etc.)
  call   _postboot              ; SEGV handler, doargv, hide privates
  jmp    _top                   ; tail-call into REPL (never returns normally)
```

### The lifecycle, step by step

**Startup.** The assembly `_start` sets up registers (rbp=HERE,
r15=dstack, rsp=return stack), compiles the embedded boot source,
then calls `_semi_exec` to execute the final anonymous block.
That block (`_boot ' >r ;`) stashes `_boot`'s XT on the return
stack and returns to it — a one-shot trampoline.

**First REPL iteration.** `_boot` calls `ossetup`, `_postboot`,
then jumps to `_top`. The `:^` trampoline (`push body; ret`) enters
the body. `ui` prints the prompt. `accept` blocks on stdin. The user
types `5 3 + . cr` and presses Enter. `accept` returns 13 (the byte
count). `0- 0=` tests: ZF=0 (nonzero). UNTIL's `jne` fires → jumps
backward to `call _eval`.

**Evaluation.** `_eval` pushes `eval.`'s XT, falls into `_exec`.
`_exec` calls `catch(eval.)`. Inside `eval.`: save parse state,
set `>in` and `tp` to cover the input, call `compiler`. The compiler
parses `5` → compiles literal 5. Parses `3` → literal 3. Parses `+`
→ compiles `add`. Parses `.` → compiles call to `.` (print TOS).
Parses `cr` → compiles call to `cr`. Hits end of input → returns.
`_auto` sees `noauto=0`, calls `;\`` which executes the compiled
anonymous block: pushes 5, pushes 3, adds (=8), prints `8`, prints
newline. `eval.` restores parse state and returns. `catch` returns 0.

**Return to prompt.** `_exec`'s `0;` fires: TOS is 0, so return.
`ret` pops the return address — which is 0x41beb0, the address
after `call _eval`. That's `_top`'s trampoline (`push body; ret`),
which jumps to the body. `ui` prints the prompt. `accept` blocks
again. The loop continues.

**Error.** The user types `foo` (undefined word). `compiler` calls
`_error` → `_throw`. `catch` returns the error pointer (nonzero).
`0;` does NOT fire. `_back` prints ` foo`, `." <-error: "` prints
the marker, `c@+ type` prints `"???"`, `cr` ends the line.
Output: `foo <-error: ???`. The cleanup code resets HERE and the
dictionary. `START`'s forward jump skips `call _eval` and goes
directly to `_top`'s body for a fresh prompt.

**EOF.** The user types Ctrl-D (or stdin is a pipe that ends).
`accept` returns 0. `0-` sets ZF=1. UNTIL's `jne` does NOT fire.
Execution falls through to `bye\``: flush, newline, `exit(0)`.

### Why the cross-word loop?

A natural question: why not put everything in one word? Lavarenne's
design separates *concerns* across *definitions*:

- **`_eval`** — knows only how to prepare `eval.`'s XT for `catch`.
  Two instructions.
- **`_exec`** — knows error handling and recovery. Does not know
  about I/O or prompts.
- **`_top`** — knows I/O: prompt, accept. Does not know about
  error handling.

The `START...UNTIL` loop binds them: `_exec` ends with `START _eval
ENTER`, `_top` ends with `UNTIL`. In machine code this compiles to a
single `jne` instruction that jumps from `_top` into the middle of
`_exec`'s code — no call overhead, no extra return-stack frames, no
loop counter. The REPL "loop" is literally one conditional jump.

The `:^` trampoline on `_top` serves double duty: it's the ENTER
landing pad (where `_exec`'s `START` forward-jumps after error
recovery) AND the normal return point (where `_exec`'s `ret` goes
after successful evaluation). One machine-code sequence serves both
the error path and the happy path.

### The `_back` algorithm

`_back` finds and prints the source context around an error — the
line being compiled when things went wrong. It uses the
`BEGIN/WHILE/TILL/END` pattern (the pattern that prompted experiment
150's loop fixes):

```forth
:. _back >in@ 1- dup
  BEGIN tib <> drop WHILE
    1- dupc@ 10- drop 0= TILL
    1+ END
  swap over- type ;
```

In English: start at `>in - 1` (one before the current parse position).
Walk backward byte by byte. WHILE guards against going past `tib`
(start of buffer). TILL exits when a newline (LF=10) is found.
After the loop, `1+` skips past the newline, `swap over- type` prints
from the line start to the original `>in` position.

The machine code (annotated):

```asm
_back:
  ; >in@ 1- dup — get parse position, back up one, duplicate
  push NOS                       ; save NOS
  mov  rdx, rbx                  ; dup: NOS = TOS
  mov  rbx, [>in]                ; >in@ — current parse position
  dec  rbx                       ; 1-
  push NOS                       ; \  dup
  mov  rdx, rbx                  ;  |

.loop_test:                      ; BEGIN
  ; tib <> drop — compare against tib start
  push NOS                       ; push for comparison
  mov  ebx, tib                  ; tib literal
  cmp  rdx, rbx                  ; <> (non-consuming comparison, sets FLAGS)
  drop                           ; drop tib (flags preserved!)
  xchg rbx, rdx                  ; restore register state
  jz   .done                     ; WHILE: exit if at tib start (ZF=1 → equal)

  ; 1- dupc@ 10- drop — back up, read byte, test for LF
  dec  rbx                       ; 1-
  push NOS                       ; \  dupc@
  movzx rdx, byte[rbx]          ;  |  (read byte at current position)
  xchg rbx, rdx                 ;  /
  sub  rbx, 10                   ; 10- (subtract LF value, sets ZF if was LF)
  drop                           ; 0= — drop byte (flags preserved)
  xchg rbx, rdx                 ; restore register state
  jnz  .loop_test                ; TILL: jump back if NOT LF (ZF=0)

  inc  rbx                       ; 1+ (skip past the LF we found)

.done:                           ; END resolves WHILE's forward ref
  sub  rdx, rbx                  ; swap over- (length = end - start)
  xchg rbx, rdx                 ; ( addr length )
  jmp  type                      ; type — print the line and return
```

This demonstrates every distinctive feature of FreeForth's flow
control: WHILE guards the loop (forward jump on failure), TILL
provides the backward jump (loop back when NOT done), END resolves
WHILE's forward reference (no backward jump from END itself), and
`drop` between the flag-setter (`10-`) and TILL is flags-preserving.

## Part 41: OS/Architecture Separation — The ff2lin.boot Unification (Experiment 151)

FreeForth's cross-platform architecture separates three layers:

1. **Assembly** (`ff64.asm`, `fflin64.asm`) — register allocation,
   compiler core, ELF binary layout, syscall ABI
2. **Architecture-specific Forth** (`ff64.boot` via `ff2.boot`) —
   compiler macros, stack ops, flow control, SWAPbit
3. **OS-specific Forth** (`ff2lin.boot`) — dlopen, SEGV handler,
   file loading, environment, command-line processing

Previously, the OS layer was duplicated: `fflin.boot` for i386 and
`fflin64.boot` for x86-64. These files were 90% identical. Experiment
151 unified them into `ff2lin.boot`, loaded via `^V` from `ff2.boot`.

### What's architecture-specific

Only three things differ between i386 and x86-64 at the OS layer:

**Syscall numbers.** Linux assigns different numbers to the same
operations on i386 vs x86-64 (e.g., `write` is 4 vs 1, `open` is
5 vs 2, `rt_sigaction` is 174 vs 13). These are extracted into
`lib/x86/syscalls.ff` and `lib/x86-64/syscalls.ff`, loaded via a
conditional `^V` include:

```forth
[64] [IF] lib/x86-64/syscalls.ff
[ELSE] lib/x86/syscalls.ff
[THEN]
```

**The `libc` variable.** On i386, `ff.asm` defines `DATA "libc"` —
an assembly-level variable that `#fun` in `fflinio.asm` hardcodes
for `dlsym` lookups. On x86-64, there's no assembly equivalent, so
Forth defines `variable libc`. Adding a Forth `variable libc` on
i386 would shadow the assembly one — `find` returns the most
recently defined, but `#fun` still reads the assembly address.
This caused a SEGV in turnkey (fftk) builds where `dlsetup` stored
the handle in the wrong variable.

```forth
[64] [IF] variable libc [THEN]
```

**SEGV handler struct layout.** The `kernel_sigaction` struct has
different field sizes (4-byte vs 8-byte) and the `rt_sigaction`
syscall number differs (174 vs 13).

### What's shared

Everything else is identical: `dlsetup` (with its `0<>;` guard for
static builds and turnkey re-entry), `libc.`/`libc_` (compile-time
vs runtime dlsym wrappers), environment access (`envp`/`getenv`),
ffpath construction, `openlib` (search-path file opener),
`needed`/`needs` (file loading via `eval`), `-f\`` (turnkey support),
`quit`, and `linsetup` (boot hook wired to the `ossetup` vector).

### The dlsetup pattern

```forth
:. dlsetup libc@ 0<>; drop "libc.so.6" #lib libc! ;
dlsetup                        \ eager init at boot load time
```

`dlsetup` runs twice: once immediately when ff2lin.boot loads (eager
init), and again via `linsetup` → `ossetup` at `_boot` time. The
second call is for turnkey re-entry — a baked image starts fresh with
`_boot`, which calls `ossetup`, which calls `linsetup`, which calls
`dlsetup`. The `libc@ 0<>;` guard makes the second call a no-op
when libc is already loaded.

On static builds (`ff64s`), `#lib` doesn't exist — `dlsetup` returns
early and libc stays 0. All `libc.` calls then get a null handle,
which is harmless (dlsym returns null, `#call` does nothing).

### Future ports

The separation makes future ports straightforward:

- **ARM64 Linux**: replace `ff64.asm`/`ff64.boot`, add
  `lib/aarch64/syscalls.ff`, reuse `ff2lin.boot` unchanged
- **macOS x86-64**: replace `ff2lin.boot` with `ffmac2.boot`,
  reuse `ff64.asm`/`ff64.boot` unchanged
- **macOS ARM64**: replace both layers, reuse `ff2.boot` core


## Part 42: Assembly OS Extraction — fflin64io.asm (Experiment 159)

Lavarenne's i386 design separates the assembly kernel from the OS
interface:

```
fflin.asm          Build wrapper: OSFORMAT + OSINCLUDE macros
  → includes ff.asm     Language kernel
    → calls OSINCLUDE → fflinio.asm  OS interface (syscall, dlopen)
```

The x86-64 port originally had everything in `ff64.asm` — a monolith.
Experiment 159 restored the clean separation:

```
fflin64.asm        Build wrapper: OSFORMAT + OSINCLUDE macros
  → includes ff64.asm    Language kernel
    → calls OSINCLUDE → fflin64io.asm  OS interface (syscall, dlopen)
```

### What moved to fflin64io.asm

| Symbol | Lines | Purpose |
|--------|-------|---------|
| `_syscall` | ~55 | Generic Linux syscall dispatcher |
| `_segv_restorer` | 3 | `rt_sigreturn` trampoline for signal handling |
| `_dllib` | ~15 | `#lib` — `dlopen(filename, RTLD_LAZY\|RTLD_GLOBAL)` |
| `_dlfun` | ~15 | `#fun` — `dlsym(handle, symbol)` |
| `dl_err` | ~25 | Shared dlerror handler |
| `_dlcall` | ~35 | `#call` — C function call via SysV ABI |
| Static stubs | ~20 | `_dllib`/`_dlfun`/`_dlcall` returning 0 (no FFI) |

The `extrn dlopen/dlsym/dlerror` declarations also moved into
`fflin64io.asm`, guarded by `if defined ffdl`.

### Dead code found and removed

`_segv_handler` (17 lines) — an assembly SEGV handler that printed
"*** SEGV ***" to stderr and exited.  This was dead code: the Forth
`SEGVhndlr` in `ff2lin.boot` installs itself via `rt_sigaction` at
boot time, completely replacing any assembly handler.  Only
`_segv_restorer` (the `rt_sigreturn` trampoline) is live — the
kernel requires it as `SA_RESTORER` for signal frame cleanup.

Also removed: `segv_msg` and `segv_msg_len` data strings from
ff64.asm's data section.

### What stays in ff64.asm

The `GENWORDS64` dictionary entries (`WORD64 "syscall"`, `"#lib"`,
`"#fun"`, `"#call"`, `"sigrestorer"`) remain in ff64.asm's dictionary
table.  Only the code implementations moved.  This matches the i386
pattern where `CODE`/`WORD` macros define dictionary entries alongside
the kernel.

### Build wrapper pattern

Both `fflin64.asm` (dynamic) and `fflin64s.asm` (static) define the
same macro:

```asm
macro OSINCLUDE { include "fflin64io.asm" }
```

`ff64.asm` calls `OSINCLUDE` at the point between the dictionary
lookup code (`_find_forth`) and the header generation macros. The
Makefile dependencies include `fflin64io.asm`.

### The four-layer architecture (final)

```
Layer 1  ff64.asm          x86-64 language kernel
         fflin64io.asm     x86-64 Linux syscall/FFI (included by ff64.asm)

Layer 2  ff2.boot          Shared compiler, stack ops, flow control
         ff64.boot         [64]-conditional architecture specifics

Layer 3  ff2lin.boot       Linux boot: dlopen, SEGV, needed, turnkey
         syscalls.ff       Syscall number constants (lib/x86/ or lib/x86-64/)

Build    fflin64.asm       Dynamic build wrapper (OSFORMAT + OSINCLUDE)
         fflin64s.asm      Static build wrapper (same macros)
```

Future ports replace exactly the right files:
- ARM64 Linux: new Layer 1 assembly, new syscalls.ff, reuse Layers 2–3
- macOS x86-64: new fflin64io.asm + ff2lin.boot, reuse ff64.asm + ff2.boot


## Debugging: fas2gdb and the symbol gap

### The problem

FreeForth compiles to machine code at runtime. GDB sees the binary's
`.flat` section as one large block — every address shows as `_start +
offset` or `?? ()`. FASM knows about assembly labels (`_compiler`,
`_dup`, `_parse`, etc.) but its `.fas` symbol dump is a proprietary
format that no Linux debugger reads.

### The solution: two-tier symbol generation

The `fas2gdb` tool bridges this gap. It has two modes:

**Assembly labels** (`make ff64.sym`): Reads FASM's `.fas` format
(the assembler's symbol dump) and emits a minimal ELF with a
`.symtab` section. This gives GDB ~250 assembly-level names. Works
even when the binary can't boot — the `.fas` is produced by the
assembler, not at runtime.

**Full dictionary** (`make ff64-full.sym`): Boots FreeForth and runs
`.hdrs bye` — the `.hdrs` word walks the dictionary and prints every
entry. fas2gdb parses this output (format: `$header: $XT ct name`)
and emits the same ELF format. This gives ~490 symbols — every
Forth-defined word plus assembly primitives. Requires a working
binary.

The Makefile rule for full symbols is simply:
```make
ff64-full.sym: ff64 fas2gdb
	./$< .hdrs bye 2>/dev/null | perl fas2gdb --hdrs -b $<
```

### Why this matters for the historian

Christophe's original system had `see` — a Forth-level disassembler
that could annotate generated code with word names. The x86-64 port
has `see` too, but it works on one word at a time. GDB with fas2gdb
provides the missing *global* view: every address in the system
resolves to a name. When the port crashes during development, `info
symbol $rip` immediately says where you are, and a backtrace shows
the call chain through named primitives instead of anonymous hex.

This is a novel tool — no existing converter from FASM symbols to
GDB-loadable ELF existed before this project.

