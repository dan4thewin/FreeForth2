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

### The `\` comment fix

The `\` comment word originally set the input pointer to the end of
the buffer. This broke when input was piped (multiple lines read in
one sys_read call). Fixed to scan forward to the next newline only.

---

## Part 10: The Macro Library Grows (Experiments 024–029)

With the backtick mechanism stable, the work shifts from building
infrastructure to porting ff.boot's inline code generators. Each
macro teaches something about x86 encoding, the SWAPbit mechanism,
or FreeForth's design philosophy.

### Store operations and fall-through definitions (exp 024)

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

The store operations follow a layered pattern:

```forth
: 2dup!`  $48, ,1 $1389, s09 ;      ( addr val -- addr val )
: tuck!`  2dup!` nip` ;              ( addr val -- addr )
: !`      tuck!` drop` ;             ( addr val -- )
: over!`  swap` tuck!` ;             ( val addr -- val )
```

Each layer adds one operation — `nip`` to consume an argument,
`drop`` to consume another, `swap`` to reorder. This is pure
composition with zero redundancy.

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
: 0;` 0-` 0=` IF` drop` ;THEN` ;
```

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

The i386 FreeForth uses REPEAT for both patterns, with END` detecting the
loop type. Our x86-64 uses a dedicated LOOP` that includes rdrop:

| Pattern | When to use | Terminator |
|---------|-------------|------------|
| `BEGIN ... WHILE ... REPEAT` | Conditional loops | REPEAT` |
| `N TIMES ... LOOP` | Counted loops | LOOP` |

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

## Part 25: Structured Loops — START/ENTER/BREAK/END (Exp 044)

FreeForth provides a second loop family alongside BEGIN/WHILE/REPEAT:
the **START/ENTER/BREAK/END** structured loop. Where BEGIN loops test
at the top or bottom, START loops provide arbitrary exit points via
BREAK and optional first-entry skip via ENTER.

### The i386 Design

On i386, all loop constructs share the `mrk` variable (2 cells):

- `mrk[0]`: backward target address (with SC bits packed in low 2 bits)
- `mrk[4]`: linked list of forward jumps (WHILE/BREAK chain)

START saves old mrk, records the body start. ENTER patches START's
forward SHORT jump (`$EB`) to skip to the test. BREAK compiles a
forward SHORT jump and links its offset into mrk[4]. END walks the
chain resolving all forward jumps, then restores mrk. Critically,
i386 END does NOT compile the backward jump — that's done by UNTIL
(= TILL + END) or REPEAT (= backward jmp + END).

### The x86-64 Design

Our port differs in three ways:

**1. NEAR jumps instead of SHORT.** x86-64 code uses 4-byte relative
offsets (`$E9`) instead of 1-byte (`$EB`). This is necessary because
x86-64 code is larger (REX prefixes, 64-bit immediates).

**2. Stack-based break tracking instead of linked list.** The i386
linked list stores 1-byte relative offsets between break addresses in
the compiled code. On x86-64, storing 32-bit relative offsets between
64-bit addresses causes sign-extension mismatches — the sentinel value
never compares to zero. Instead, we push break addresses directly onto
FreeForth's compilation data stack:

```
START: push old-mrk, push 0 (sentinel), compile E9 forward, save body addr
BREAK: compile E9 forward, push rel32-addr, resolve preceding IF
END:   compile E9 backward, pop-and-resolve until 0 sentinel, restore mrk
```

**3. END includes the backward jump.** On i386, END only resolves
forward jumps. On x86-64, END compiles the backward E9 to the body
start. This means our `START...IF BREAK...END` is equivalent to i386's
`START...IF BREAK...REPEAT` or `START...ENTER...UNTIL`.

### Code Structure

```forth
variable mrk 0 mrk 8 + !
: START` mrk 2@ >S0 0 $E9 c, 0 d, here mrk ! ;
: ENTER` >S0 mrk @ 4 - _then ;
: BREAK` >S0 $E9 c, 0 d, here 4 - swap _then ;
: END`   >S0 $E9 c, mrk @ here 4 + - d,
         BEGIN 0- 0<> WHILE _then REPEAT drop mrk 2! ;
```

**START** saves old mrk with `mrk 2@` (pushes 2 cells), then pushes 0
as a sentinel. Compiles a forward E9 (initially jumping to the next
instruction — a no-op unless ENTER patches it). Stores `here` (the
body start) in `mrk[0]`.

**ENTER** patches START's E9 to jump to here. `mrk @ 4 -` gives the
address of START's rel32 field; `_then` patches it.

**BREAK** compiles a forward E9, pushes the rel32 address (`here 4 -`),
then swaps it under the IF address and calls `_then` to resolve IF.
Stack effect: `( if-addr -- break-addr )`.

**END** compiles backward E9 to `mrk[0]`. Then loops: test TOS for
nonzero (a break address), call `_then` to resolve it, repeat until
hitting the 0 sentinel. The `drop` removes the sentinel, and `mrk 2!`
restores the saved mrk.

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

## Part 20: Dictionary State Save/Restore — mark/marker

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
