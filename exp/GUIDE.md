# FreeForth2 x86-64 Port — A Historian's Guide

*For anyone continuing Christophe Lavarenne's work.*

This document explains how FreeForth2 works, how the x86-64 port works,
and why they differ. It is written for someone with only a rudimentary
grasp of assembly language.

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

---

## Part 4: Flow Control — Branches and Loops

### IF / THEN

`IF` compiles a conditional forward jump. At compile time:

1. Emit `test rbx, rbx` (is TOS zero?)
2. Emit DROP1 (remove the flag from the stack) using flag-preserving
   `lea r15, [r15+8]` instead of `add r15, 8`
3. Emit `jz <placeholder>` (jump if zero — skip the IF body)
4. Push the placeholder's address onto the compile-time data stack

`THEN` patches the placeholder:

1. Pop the placeholder address
2. Calculate: offset = current_position - placeholder - 4
3. Write the offset into the placeholder

**Critical encoding detail (the REX prefix bug):** The flag-preserving
DROP1 uses `lea r15, [r15+8]`, encoded as `4D 8D 7F 08`. The REX
prefix must be `4D` (REX.W=1, REX.R=1, REX.B=1) because r15 appears
in both the destination (reg field, needs REX.R) and source (r/m field,
needs REX.B). Using `49` (REX.R=0) would silently encode
`lea rdi, [r15+8]` — writing to the wrong register. This single-bit
error caused days of debugging during phase 1.

### BEGIN / UNTIL

`BEGIN` pushes the current compilation address onto the data stack.
`UNTIL` compiles a conditional backward jump to that address.

### WHILE / REPEAT

`WHILE` is like IF (forward jump). `REPEAT` compiles an unconditional
backward jump to BEGIN, then patches WHILE's forward jump.

---

## Part 5: The Boot File (ff64.boot)

The boot file defines higher-level Forth words using the built-in
primitives. Each definition is explained below.

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
`rot` brings `a` to the top, `>r` hides it on the return stack,
`rot` brings `b` to the top (now under c d), `r>` restores `a`.

```forth
: ?dup dup 0<> IF dup THEN ;
```
**?dup** ( x -- x x | 0 ) — Duplicates TOS only if it's nonzero.
Used before `IF` to avoid consuming the value when testing it.

### Arithmetic

```forth
: abs dup 0< IF negate THEN ;
```
**abs** ( n -- |n| ) — Absolute value. If negative, negate it.

```forth
: max 2dup < IF swap THEN drop ;
```
**max** ( a b -- max ) — Keeps the larger of two values.
`2dup` preserves both values, `<` compares copies. If a < b, `swap`
puts b on top. `drop` removes the smaller value.

```forth
: min 2dup > IF swap THEN drop ;
```
**min** ( a b -- min ) — Same logic, opposite comparison.

```forth
: within over - >r - r> < ;
```
**within** ( x lo hi -- flag ) — Tests if lo ≤ x < hi.
Transforms to `(x-lo) < (hi-lo)` using unsigned comparison.

### Comparison

```forth
: >= < not ;
```
**>=** ( a b -- flag ) — Greater than or equal. Equivalent to NOT less-than.

```forth
: <= > not ;
```
**<=** ( a b -- flag ) — Less than or equal.

```forth
: <> = not ;
```
**<>** ( a b -- flag ) — Not equal.

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
: spaces BEGIN dup 0 > WHILE space 1 - REPEAT drop ;
```
**spaces** ( n -- ) — Print n spaces. Loops: while n > 0, print space,
decrement. `drop` removes the zero counter at the end.

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

*This section describes the original i386 mechanism. The x86-64 port has
the infrastructure but not yet the deep integration.*

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

### Current inline primitives (23 total)

| Category | Words | Pattern |
|----------|-------|---------|
| Arithmetic | `+ - * negate` | Binary op + DROP_NOS, or unary |
| Stack | `dup drop swap over nip rot tuck` | DUP_NOS/DROP_NOS combinations |
| Bitwise | `and or xor not` | Same as arithmetic |
| Memory | `@ c@` | Unary: `mov rbx,[rbx]` |
| Comparison | `= < > 0< 0= 0<>` | cmp/test + setcc + movzx + neg |

### Words that remain as runtime calls (15)

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
: min 2dup > IF swap THEN drop ;
```

The `swap` toggles the SWAPbit at compile time (unconditionally), but
at runtime the IF body may be skipped. This creates a mismatch: code
after THEN would use the wrong register assignment for the not-taken path.

The solution: **sync at join points.** Every flow control word that
creates a join point (THEN, ELSE, BEGIN, AGAIN, REPEAT) calls `_rst`
before emitting code. This inserts `xchg rbx,rdx` on the taken path
if the SWAPbit was toggled, ensuring both paths arrive at the join
point with the same register assignment (SWAPbit=0).

---
