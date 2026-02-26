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

---

## Part 21: -call, Postfix Tick, and Vector Manipulation

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

### Runtime Vector Operations

With `-call` and `'` working, the full vector lifecycle is:

```forth
:^ greet ." hello" cr ;     \ define vector with default body
greet                        \ → "hello"
: hi ." hi" cr ;
hi ' greet ' !^              \ redirect greet to hi
greet                        \ → "hi"
greet ' x^                   \ call original body → "hello"
greet ' n^                   \ disable vector (returns immediately)
greet                        \ → (nothing)
```

**Running total:** ~225 words/macros ported. 234 tests across 46
experiments, all passing.

---

## Part 22: System Words and the _semi_exec Bug

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

The I/O words wrap Linux syscalls. A critical implementation detail: the
`syscall` instruction on x86-64 **clobbers rcx and r11**. All I/O words
must save/restore rax, rdi, rsi, and rcx around the syscall to prevent
corrupting FreeForth's internal state.

**write ( addr count fd -- written )**

Maps to Linux `sys_write` (rax=1). Stack layout: TOS=fd, NOS=count,
third=addr. Note the stack order — addr is pushed first, then count,
then fd. The implementation saves count from NOS (rdx) into rcx before
overwriting rdx with the syscall argument.

**type ( addr count -- )**

Defined in Forth as `stdout write drop`. Pushes fd=1, calls write,
drops the return value (bytes written).

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

## Part 23: The Suffix Mechanism — Inline Optimization (Exp 048)

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

## Part 24: Compile-time Stack and REPL Infrastructure

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
`accept` primitive reads byte-by-byte until newline, EOF, or count
limit (4096). On EOF, `_top` calls `exit`.

Errors are caught by `catch`. If a throw occurs, `_recover` prints the
error and resumes the loop.

**Running total:** ~240 words/macros ported. 304 tests across 50
experiments, all passing.

---

## Part 25: REPL Auto-Execute and Compile-Time Macros (Exp 051)

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

## Part 26: Forth-based REPL (_top) (Experiment 052)

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

### Line-by-line accept

The `accept` primitive reads byte-by-byte until it encounters a newline
(LF=10), EOF (sys_read returns ≤0), or reaches the count limit. This
replaced the original bulk-read `sys_read(0, addr, count)` which on
piped input would read all available data at once, making multi-line
interaction impossible.

With line-by-line accept, test inputs use simple `printf '%s\n'` to
send multiple lines. Each `accept` call returns one line:

```makefile
result=$$(printf '%s\n' 'line one ;' 'line two ;' | $(FF) 2>/dev/null)
```

The earlier experiments used an 80-byte padding trick (`printf '%-80s'`)
to force each "line" to consume exactly one accept call. That trick is
no longer necessary but some experiments still use it.

### `-f` file `anon` reset (historical)

A subtle bug from the era when ff64 had an assembly REPL: after boot
(processing the first `-f ff64.boot`), `anon` was left at 0 because the
last definition (`_top`) used `:^` which calls `_colon`, which sets
`anon = 0`. This was fixed by resetting `anon = rbp` before compiling
each `-f` file. With the self-booting architecture (Exp 069), `-f` is
handled by Forth's `doargv` → `-f`` → `needed` → `loadfile`, which
manages anon/callmark/SC itself via `hereatexec`.

**Running total:** ~245 words/macros ported. 322 tests across 52
experiments, all passing.

---

## Part 27: Boot Sequence and Command-Line Access (Experiment 053)

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

**`loadfile` ( addr len -- )**: The workhorse. Opens a file, reads it
into the filebuf area, sets up `tin`/`tp` for the compiler, and calls
`_compiler` to process the file content. Saves and restores the input
state so the calling code's parsing position is preserved.

### The hereatexec mechanism

When `loadfile` is called from the REPL, it runs inside anonymous code
via `_semi_exec`. The problem: `_semi_exec` resets `rbp` to the start
of anonymous code before executing it. If `loadfile` compiles new
definitions at this `rbp`, they overwrite the executing anonymous code.

**Solution:** `_semi_exec` saves `rbp` (the position past the anonymous
code) in a new variable `hereatexec` before resetting it. `_loadfile`
uses `hereatexec` as the safe starting position for compilation.

### The loadfile rbp preservation rule

A deeper bug: after `_compiler` returns in `_loadfile`, the original
code restored `rbp` to the anonymous code start. This caused `_semi_exec`
(which does `mov [anon], rbp` after the call) to reset `[anon]` to the
anonymous code start. The NEXT REPL line would compile new anonymous
code there, OVERWRITING the loaded definitions.

**Rule:** `_loadfile` must NOT restore `rbp` after `_compiler` returns.
Leave rbp past all loaded definitions. When control returns to
`_semi_exec`, it preserves the space via `mov [anon], rbp`.

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
  2dup marker swap loadfile ;
```

It temporarily writes a backtick at the end of the filename, looks for
that name in the dictionary. If found (a previous `marker` created it),
the file is already loaded — skip. Otherwise, create a marker with the
filename+backtick as its name, then load the file.

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

With `loadfile`, `needed`, and `find` in place, the system could load
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
the stack through `needexec` because `loadfile` disrupts the stack.

This is the same pattern used by `see\`` in the i386 FreeForth
(`fflin.boot`). Lavarenne clearly valued this lazy-loading approach
for keeping the core small.

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

### The ff64 port

For ff64, the same mechanism applies with minor differences:
- Headers live in `.flat` (not BSS), so no separate `dict` file —
  the `cmpl64` dump includes everything
- 64-bit variables at known offsets (8 bytes each instead of 4)
- `_bootxt` at offset 72 (was offset 16 on i386)
- The `-f` handler detects `main` and rewrites vectors (`_top`, `_postboot`)
- `DS0` (data stack top address) stored via a config file since
  `dstack_top` is a label not exposed to Forth

### Building a Turnkey (Experiment 073)

The 64-bit turnkey builder is now implemented and tested.

**Build a turnkey from a program file:**
```bash
./ff64 -f program.ff -f lib/mkimage64.ff    # produces cmpl64, cmpl64.cfg
fasm fftk64.asm fftk64.o                     # assemble turnkey loader
ld -m elf_x86_64 -lc -ldl \
   --dynamic-linker=/lib64/ld-linux-x86-64.so.2 \
   -o fftk64 fftk64.o                        # link turnkey binary
./fftk64                                      # run standalone program
```

Or use `make fftk64` after generating cmpl64.

**Build a pre-compiled REPL:**
```bash
./ff64 -f lib/mkimage64.ff && make fftk64
./fftk64                     # instant REPL (no boot compilation)
```

**The three files:**

| File | Purpose | Size |
|------|---------|------|
| `lib/mkimage64.ff` | Dump script — captures running system state | ~25 lines |
| `cmpl64` | Raw code image (H to here) | ~310KB |
| `cmpl64.cfg` | DS0 + segvsetup address (16 bytes) | 16B |
| `fftk64.asm` | Turnkey loader — embeds cmpl64, boots | ~60 lines |

**Variable offset table in cmpl64:**

| Offset | Size | Name | fftk64 startup |
|--------|------|------|----------------|
| 0 | 8 | H | Already correct (header chain) |
| 8 | 8 | anon | Set to saved_here by mkimage64 |
| 16 | 8 | callmark | Cleared to 0 |
| 48 | 8 | xfp | Cleared to 0 |
| 56 | 8 | ff_argc | Set from rsp |
| 64 | 8 | ff_argv | Set from rsp+8 |
| 72 | 8 | bootxt | Set to _boot xt by mkimage64 |
| 88 | 1 | SC | Cleared to 0 |
| 89 | 1 | cond_jmp | Cleared to 0 |

### Critical Bug: loadfile Overwrite

The most significant bug found during turnkey development:
`loadfile` reset `rbp = hereatexec` before each file's compilation.
But `hereatexec` was never updated. With multiple `-f` files, the
second file's compilation started at the **same address** as the
first — overwriting the first file's compiled definitions.

The fix: update `hereatexec` after `_compiler` returns in `loadfile`.
This bug was invisible for single `-f` usage and for `needed`-based
loading, only manifesting with multiple `-f` arguments.

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
