# Lavarenne's Hanoi: A Tour for the Curious

Christophe Lavarenne (1956–2011) created FreeForth — a Forth with an
interactive REPL where everything is compiled (even at the prompt),
CPU flags replace booleans, and the compiler fits in a few kilobytes
of handwritten assembly. His `hanoi` is a non-recursive animated Towers of Hanoi
solver in pure Forth. It is a small masterpiece, and the best
introduction to what makes FreeForth different.

This walkthrough explains the fully animated graphical version — the
default compilation. It assumes you know a little Forth (stacks,
postfix) and want to understand why someone would design a language
this way.

The source carries a CVS datestamp: `$Id: hanoi,v 1.2 2006-12-15`.

---

## The shebang and conditional compilation

```forth
#!ff needs
\ Hanoi Tours (with four conditionally compilable display variations)
```

The first line is a Unix shebang: `#!ff needs`. When you run
`./hanoi` from the shell, Linux invokes `ff needs hanoi` — the
`needs` word loads the file. Inside `needed`, there is an explicit
check: if the first two bytes are `#!`, skip to the first newline
before compiling. Without this, `#!ff` would be an unknown word
and halt compilation.

The file contains **four display variants** selected by `[0] [IF]`
/ `[ELSE]` / `[THEN]` conditional compilation — a 2×2 matrix:

- **Static vs animated:** the outer `[0] [IF]` selects between a
  simple disk-stack model (static redraw) and the animated version
  with `up`/`dn` frame-by-frame movement.
- **Numeric vs graphical:** an inner `[0] [IF]` selects between a
  bare number display and the graphical `--------` line drawing.

The defaults (both `[0] [IF]` — false) select the animated graphical
variant. This tour covers that version. The static variant uses a
different data structure (a flat 8-byte `ds` array instead of the
30-byte `st` array) and a different `top`/move algorithm without
animation.

---

## The embedded help text

```forth
'$' parse ( -- @ # ) dup>r here rot over r> ( -- # h @ h # ) dup allot ;
  "Hanoi Tours"  is  a classical mathematical problem ...
  ...
$ cmove  : .intro` lit lit type ;  \ --
```

The file opens not with code but with a block of explanatory prose,
compiled into the dictionary as raw bytes. This is a FreeForth idiom
for embedding long text:

`'$' parse` reads everything up to the next bare `$`, returning an
address and length. The stack shuffle `dup>r here rot over r>` sets
up for `cmove` — the stack comment `( -- # h @ h # )` documents the
result. `dup allot` reserves dictionary space. `cmove` copies the
text in. `: .intro`` defines a word (with backtick — callable at
runtime) that pushes the address and length as compiled literals
and calls `type`.

No file I/O, no string constants, no heap. The help text lives in
compiled memory, indistinguishable from code. The `'$' parse` idiom
lets any character be the block delimiter, so the text can contain
quotes, parentheses, anything.

---

## Data structures

```forth
variable #m              \ number of moves
create st 30 allot       \ 3 stacks
: >st  10* st+ ;         \ s -- @
```

The entire puzzle state is 30 bytes. `st` is a flat buffer: three
pegs of 10 bytes each at offsets 0, 10, and 20. Each byte holds
either a space (0x20, empty) or a digit character ('1'–'8',
representing disk sizes). Position 9 of each peg holds '9' as a
sentinel — no real disk is that large.

`>st` converts a peg number (0, 1, 2) to a byte address. `10*` is a
number with the compiler suffix `*` — "multiply TOS by this
immediate." `st+` is the variable address with suffix `+` — "add
this immediate." Together: `addr = peg × 10 + st`. One word, zero
temporaries.

In FreeForth, suffixes like `*`, `+`, `@`, `!` are handled by the
compiler on number tokens. `10*` is not "push 10, then multiply" —
it compiles a single multiply-by-immediate instruction. `st+`
compiles a single add-immediate. The compiler does the work so the
runtime doesn't have to.

---

## The display template

```forth
: dd "________--------________" drop ;
```

`dd` compiles a 24-character inline string and drops the count,
leaving just the address. In FreeForth strings, `_` represents a
space. The string has three zones: 8 spaces, 8 dashes, 8 spaces.
By indexing into it at different offsets, a single string serves
as the template for every row of every peg.

```forth
: .-  \ w c
  swap dd 2dup+ 8 type swap - swap emit 16+ 8 type ;
```

`.-` draws one row given a disk width `w` and a character `c`.
Trace with w=3, c='3':

1. `swap` → `('3', 3)`
2. `dd` → `('3', 3, dd_addr)` — the template address
3. `2dup +` → `('3', 3, dd_addr, dd_addr+3)` — offset into template
4. `8 type` — prints 8 chars from offset 3: `"     ---"` (5 spaces,
   3 dashes)
5. `swap -` → `('3', dd_addr-3)` — arithmetic setup
6. `swap emit` — prints `'3'` (the center character)
7. `16+ 8 type` — prints 8 chars from offset 13: `"---     "` (3
   dashes, 5 spaces)

Result: `     ---3---     ` — a disk of width 3 centered on the peg.
For an empty slot (w=0, c='|'): `        |        ` — just the peg
post. The `dd` string is reused for every row of every peg.

---

## The screen painter

```forth
: ._  \ --
  50 ms cls` 3 TIMES r >st  r 17*
  9 TIMES 2dup  r atxy  r + c@ $F&  r 0- 0<> 32_ IF '|'_ THEN  .- REPEAT
  2drop REPEAT  0 9 atxy  0 'a' 2dup .- 1+ 2dup .- 1+ .-
  cr #m@ .
  ."(a:b<->c__b:c<->a__c:a<->b__i(n--):init__s(n--):solution__h:help)^J" ;
```

`._` redraws the entire terminal — three pegs, labels, move counter,
help text. It is called after every single animation frame.

`50 ms` pauses 50 milliseconds (animation speed). `cls`` clears the
screen. The backtick in the name matters: `cls`` (with backtick)
compiles a CALL, so `."^[[2J"` inside runs at **runtime** — clearing
the screen on every frame. Writing `cls` (without backtick) would
inline the body, causing `."` to run at **compile time** — clearing
the screen once during compilation and emitting no runtime code.
This is why Lavarenne defines it as `: cls`` — the backtick preserves
the choice, and hanoi uses the callable form.

The **outer loop** `3 TIMES ... REPEAT` iterates the three pegs.
The TIMES counter counts down: 2, 1, 0.

- `r >st` — push the loop counter, convert to peg base address
  (10× + st)
- `r 17*` — push the counter again, multiply by 17 for the screen
  column (columns 34, 17, 0 — three pegs spaced 17 characters apart)
- Stack: `( peg_addr column )`

The **inner loop** `9 TIMES ... REPEAT` draws 9 rows per peg
(counter 8 down to 0):

- `2dup` — duplicate `( peg_addr column )` so they survive each
  iteration
- `r atxy` — push the row counter, then `atxy ( col row -- )`
  positions the cursor using the column from the outer loop (via
  `2dup`) and the row from the inner counter
- `r + c@` — push the row counter, add to peg_addr, fetch the byte
  at that peg position
- `$F&` — mask the low nibble: space (0x20) gives 0, digit characters
  '1'–'8' give 1–8. This extracts the disk width.

Now: **`r 0- 0<> 32_ IF '|'_ THEN`**

This chooses the display character for empty slots. `r` pushes
the row number. `0-` tests TOS (`or reg,reg`) — it sets CPU FLAGS
without changing the value. `0<>` stores a "jump if not equal"
condition. `32_` replaces TOS with 32 (space). `IF` checks the
condition: if NOT row 0, `'|'_` replaces TOS with the pipe character
(the peg post). `THEN` closes.

Stack is now `( peg_addr column width char )`. `.-` consumes
`( width char )`, drawing one row. `REPEAT` loops the inner 9 rows.
After the inner loop, `2drop` discards `( peg_addr column )`.
`REPEAT` loops the outer 3 pegs.

The result: row 0 of each peg shows blank above the post. All other
empty slots show `|`. Disks show as `---N---` centered dashes. The
condition flows through CPU flags, the replacement uses `_` suffix —
no booleans, no stack juggling.

---

## Finding the top disk

```forth
: top  \ @ -- @'
  BEGIN c@+ $F& 0<> drop UNTIL 1- ;
```

Given a peg's base address, `top` returns the address of the topmost
disk. It walks forward through bytes with `c@+` (fetch byte, advance
address), masks the low nibble, and stops when it finds a nonzero
value (a disk, not a space).

The `0<>` does not push a boolean. It stores a jump opcode in a
compiler variable called `cond_jmp`. `UNTIL` reads `cond_jmp` and
emits a conditional jump directly. The condition lives in the CPU's
FLAGS register. The `drop` after `0<>` removes the nibble value from
the data stack — but `drop` is flags-preserving¹. The condition
survives across the drop.

This is FreeForth's most distinctive feature: **FLAGS-based
conditionals.** Every comparison word (`=`, `<`, `0<>`, etc.) sets
CPU flags. Every flow control word (`IF`, `WHILE`, `UNTIL`) emits a
conditional jump based on those flags. No booleans are manufactured,
tested, and discarded. The machine does what the machine does best —
compare and branch.

For a deeper explanation of how this works at the machine level, see
[GUIDE.md Part 5: FLAGS-Based Conditionals](GUIDE.md).

---

## Lifting a disk: `up`

```forth
: up  \ @ -- n
  dup>r top dupc@ 32$00+ swap BEGIN 1- 2dupw! ._ r = drop UNTIL
  32 swap c! rdrop ;
```

`up` lifts a disk off a peg with frame-by-frame animation.

`dup>r` saves the peg base on the return stack — it will be the loop
bound. `top` finds the topmost disk. `dupc@` fetches the disk's
character value while keeping the address. Stack: `( byte addr )`.

`32$00+` adds 0x2000 to the byte value. The number `32$00` is a
FreeForth literal: `32` in decimal (= 32), then `$` switches to hex,
then `00`. Combined: 32 × 256 + 0 = 0x2000. The `+` suffix adds it
to TOS. For disk '1' (0x31): `0x31 + 0x2000 = 0x2031`. This packs a
two-byte animation frame: the disk character in the high byte, a space
(0x20) in the low byte. When written to memory as a 16-bit word
(little-endian), it places the disk character at the address and a
space one byte before — the disk appears to move up one position.

`swap` puts the address on top. Then the animation loop:

`BEGIN 1-` moves one position up. `2dupw!` writes the 16-bit frame —
non-consuming, so both the frame value and the address survive for
the next iteration. `._` redraws the screen. `r = drop` compares the
current address against the peg base (from the return stack). `=`
sets FLAGS without consuming its operands; `drop` removes the extra
copy that `r` pushed. `UNTIL` exits when we reach the top.

After the loop: `32 swap c!` blanks position 0. `rdrop` discards the
saved base.

**The `2dupw!` store.** Standard Forth's `w!` consumes both the value
and the address. In a tight animation loop, you'd need to `2dup`
before every store and manage the copies. FreeForth provides
`2dupw!` — store a 16-bit word, keep both operands. The loop body
is `1- 2dupw!` — decrement, store. No copies, no juggling.

---

## Dropping a disk: `dn`

```forth
: dn  \ n @ --
  2dupc! swap 8 << 32+ swap  \ -- n<<8+32 @
  BEGIN ._ dupw@ $F00& drop 0= WHILE 2dupw! 1+ REPEAT 2drop ;
```

`dn` drops a disk onto a peg, animating downward.

`2dupc!` stores the disk character at the top position (position 0)
while keeping both values. Then `swap 8 << 32+` builds the downward
animation frame: shift the character left 8 bits and add 0x20. For
'1': `0x31 << 8 + 0x20 = 0x3120`. In little-endian: byte[addr] =
0x20 (space above), byte[addr+1] = 0x31 (disk below). This is the
mirror of `up`'s frame.

The loop: `dupw@` fetches 16 bits at the current address (preserving
the address — another `dup`-variant). `$F00&` masks the high byte's
low nibble — this peeks at the slot below to see if it contains a
disk. `0= WHILE` continues while the slot below is empty. `2dupw!`
writes the frame. `1+` moves down. `REPEAT` loops.

The disk slides down until it hits another disk or the sentinel '9'.
`2drop` cleans up.

---

## The three-way dispatch: `a``, `b``, `c``

```forth
: a` 1 2 0      SKIP
: b` 2 0 1 SKIP
: c` 0 1 2 THEN THEN
  >st dup top 1- = 2drop IF 2drop ;THEN  >st swap >st  1 #m +!
  over top c@ over top c@ < 2drop IF swap THEN  up swap dn ;
```

This is the most unusual construct in the program. Three separate
dictionary entries — `a``, `b``, `c`` — share a single body.

Each word pushes three peg numbers and jumps forward:
- `a`` pushes `1 2 0` then `SKIP` (forward unconditional jump)
- `b`` pushes `2 0 1` then `SKIP`
- `c`` pushes `0 1 2` and falls through
- `THEN THEN` resolves both SKIPs — all three paths converge

The backtick names mean these are callable words. The solver `s``
calls them with `b`` `c`` `a``.

In Hanoi, typing `a` means "move between the other two pegs (b and
c)." The three numbers encode the two candidate pegs and the
bystander. `SKIP` compiles a forward jump; `THEN` resolves it. The
result is three named entry points into one body — a dispatch table
with zero overhead. No function pointers, no CASE statement. The
code IS the dispatch.

The shared body:

`>st` converts the first peg number to an address. `dup top 1- =
2drop IF 2drop ;THEN` checks whether this peg has only the sentinel
— if so, there's nothing to move; clean up and return. `;THEN`
compiles a return AND resolves the forward reference from `IF`, in
one word.

`>st swap >st` converts the remaining two peg numbers to addresses.
`1 #m +!` increments the move counter.

`over top c@ over top c@ < 2drop IF swap THEN` — the Hanoi rule.
Fetch the top disk from each peg, compare sizes. `<` sets FLAGS.
`2drop` cleans up both operands (since `<` doesn't consume them).
`IF swap THEN` ensures the smaller disk's peg is on top. No boolean
variable, no local, no temporary — the comparison result flows from
FLAGS through `IF` to `swap`.

`up swap dn` — three words to make the move. Lift a disk off one
peg, swap to get the other peg on top, drop the disk onto it. Done.

---

## Initialization: `i``

```forth
: i`  \ n -- ; init
  ;` 1- 7& 1+  0 #m!  st 30 32 fill  '9' st 9+ 2dupc! 10+ 2dupc! 10+ c!
  0 >st swap TIMES r '1'+ over dn REPEAT drop ;
```

The `;`` at the start is significant. `i`` is a backtick macro — when
the compiler encounters `i` (without backtick), it inlines the body.
The leading `;`` flushes any anonymous code being compiled before
inlining begins, preventing code-overwrite problems.

`1- 7& 1+` clamps the disk count to 1–8. `0 #m!` resets the move
counter. `st 30 32 fill` fills all 30 bytes with spaces.

`'9' st 9+ 2dupc! 10+ 2dupc! 10+ c!` plants the sentinel at the
base of each peg: store '9' at st+9 (keeping both values with
`2dupc!`), add 10, store at st+19 (keeping again), add 10, store at
st+29 (consuming with `c!`). Three stores, one character value, one
chain of non-consuming stores. No reload, no local variable.

`0 >st swap TIMES r '1'+ over dn REPEAT drop` — for each disk, get
the loop counter, make it a digit character, and call `dn` to drop it
onto peg 0. The initial stack is built using the same animation
routine used during play. The disks appear to fall into place one by
one.

---

## The solver: `s``

```forth
: s`  \ n -- ; solution
  ;` 1- 7& 1+  dup i`  500 ms
  1 swap << BEGIN 1- 0<> WHILE b` 1- 0<> WHILE c` 1- 0<> WHILE a` REPEAT drop ;
```

Two lines. Non-recursive.

`1- 7& 1+ dup i`` clamps and initializes. `500 ms` pauses to show
the starting position. `1 swap <<` computes 2^N — the total number
of moves plus one.

The solving loop: `BEGIN 1- 0<> WHILE b` 1- 0<> WHILE c` 1- 0<>
WHILE a` REPEAT drop`. This exploits the mathematical structure of
the optimal Hanoi solution: the moves cycle through a fixed three-peg
pattern. The loop counts down from 2^N, calling `b``, `c``, `a`` in
rotation — three moves per pass.

The three `WHILE` clauses are elegant. Each `WHILE` is an
independent exit point — if the counter hits zero after `b`` but
before `c``, the loop terminates cleanly. For 2^N − 1 total moves
(which may not be divisible by 3), this is essential. (Standard Forth
also allows multiple `WHILE` per loop, but requires a `THEN` after
`REPEAT` for each extra `WHILE`. FreeForth's `REPEAT` resolves all
pending `WHILE`s at once.)

When any `WHILE` exits, `drop` discards the zero counter.

---

## The tail: interactive mode

```forth
$ cmove ;  : h` ._ lit lit type ;
3 s .intro EOF enjoy!
```

A second `'$' parse` block (not shown) embeds the usage instructions.
`: h`` defines the help word — callable at runtime, it redraws the
screen and prints the usage text.

`3 s` runs the solver for 3 disks immediately on load. `.intro`
(without backtick — inlined) prints the introductory help text.
`EOF` stops reading input. `enjoy!` is never parsed — everything
after `EOF` is ignored.

After `EOF`, the REPL is live. Type `a`, `b`, or `c` to move
manually. Type `4 i` to reset with 4 disks. Type `3 s` to watch the
solution. Type `h` for help. The entire game runs from single-letter
commands at the Forth prompt — because in FreeForth, the REPL is the
compiler, and everything compiles.

---

## What this teaches

Reading `hanoi` reveals the design philosophy that Lavarenne built
FreeForth to embody:

**FLAGS, not booleans.** Not once does this program push a true/false
value. Conditions set CPU flags; flow-control words read them. `drop`
preserves flags. The comparison, the cleanup, and the branch are three
separate concerns that compose without interference.

**Non-consuming stores.** `2dupc!` and `2dupw!` eliminate the
store-and-reload pattern. In the animation loops, the frame value and
address survive every store, requiring no copies, no locals, no
reloads. The code says "store" and keeps going.

**The `_` suffix.** `32_` and `'|'_` replace TOS with an immediate
— no push, no drop, no stack depth change. Combined with `IF...THEN`,
it gives conditional assignment without touching the stack.

**Multi-entry words via `SKIP`/`THEN`.** Three named words, one body,
zero dispatch overhead. This has no equivalent in standard Forth.

**The compiler does the work.** `10*` is one instruction. `st+` is
one instruction. Backtick macros like `dup` inline register operations
directly — writing `dup`` (with backtick) compiles a call to the
runtime version instead. `cls`` uses the backtick form because `."` is
a compile-time word: inlining would print the escape sequence during
compilation, not at runtime. The runtime never parses a number, never
looks up a string, never resolves an address. Everything is resolved
by the compiler, even at the REPL.

**Conditional compilation.** Four display variants, one source file,
selected by `[0] [IF]` / `[ELSE]` / `[THEN]`. No preprocessor, no
build system flags — the compiler evaluates the conditions and
compiles only the active branch.

---

*For the architecture behind all this — how SWAPbit works, how the
compiler emits machine code, how FLAGS cross word boundaries — see
[exp/GUIDE.md](../exp/GUIDE.md).*

*For the story of how this program was ported from i386 to x86-64,
including the one-line `w!` bug that blocked it, see experiment
146 in [exp/JOURNAL.md](../exp/JOURNAL.md).*

---

**Notes**

¹ On i386, `drop` compiles as `pop` + `xchg` (with `esp`/`eax`
swapping for the separate data stack). On x86-64 (FreeForth2), it
compiles as `mov` + `lea`. Neither sequence modifies arithmetic
flags — the design is intentional.

² Lavarenne's original strings use `_` for spaces (e.g.,
`"________--------________"`). FreeForth2 also accepts literal
spaces in string literals.
