# Debugging FreeForth2 Generated Code with GDB

FreeForth compiles machine code at runtime. When something crashes or
behaves wrong, there are no symbols for the generated code — GDB sees
it all as offsets within `_start`. This document describes techniques
for examining and annotating generated code on both the i386 (`ff`)
and x86-64 (`ff64`) platforms.

## Quick Reference

| Platform | Disassemble a word | Annotate generated code | Debug build |
|----------|-------------------|------------------------|-------------|
| i386     | `see wordname`    | Not needed (see shows labels) | `ld -m elf_i386 -lc --dynamic-linker=/lib/ld-linux.so.2 -o ff_dbg ff.o` |
| x86-64   | GDB + `int3`      | `mov r10d, <ID>` markers | `ld -m elf_x86_64 -o ff64_dbg ff64.o` (omit `-s`) |

## Building Debug Binaries

The production binaries are stripped (`-s` in the linker flags). Build
unstripped versions for GDB:

```bash
# i386 debug build (keep symbols from ff.asm)
fasm fflin.asm ff.o
ld -m elf_i386 -lc --dynamic-linker=/lib/ld-linux.so.2 -o ff_dbg ff.o

# x86-64 debug build (keep symbols from ff64.asm)
fasm ff64.asm ff64.o
ld -m elf_x86_64 -o ff64_dbg ff64.o
```

## i386: Using `see`

The i386 `ff` has a built-in disassembler. Define a word and immediately
`see` it:

```
: t 5 BEGIN 0- 0<> WHILE dup . space 1- REPEAT drop cr ;
see t
```

Output (annotated):

```
t
   $0804e4c8:  94          xchg   esp,eax       ; switch to data stack
   $0804e4c9:  52          push   edx           ; push NOS
   $0804e4ca:  6a 05       push   $5            ; literal 5
   $0804e4cc:  5a          pop    edx
   $0804e4cd:  90          nop                   ; align (from BEGIN)
   $0804e4ce:  90          nop
   $0804e4cf:  90          nop
   $0804e4d0:  09 d2       or     edx,edx       ; 0- 0<>: test NOS
   $0804e4d2:  74 16       jz     $804e4ea       ; WHILE: exit if zero
   $0804e4d4:  53          push   ebx           ; dup (push TOS copy)
   $0804e4d5:  89 d3       mov    ebx,edx
   $0804e4d7:  87 da       xchg   ebx,edx
   $0804e4d9:  94          xchg   esp,eax       ; switch to call stack
   $0804e4da:  e8 ...      call   .             ; call .
   $0804e4df:  e8 ...      call   space         ; call space
   $0804e4e4:  4b          dec    ebx           ; 1-
   $0804e4e5:  87 da       xchg   ebx,edx
   $0804e4e7:  94          xchg   esp,eax       ; switch to data stack
   $0804e4e8:  eb e6       jmp    $804e4d0      ; REPEAT: loop back
   $0804e4ea:  5a          pop    edx           ; drop
   $0804e4eb:  94          xchg   esp,eax
   $0804e4ec:  e9 ...      jmp    cr            ; tail-call cr
```

Key observations:
- `see` shows symbolic call targets (`. `, `space`, `cr`)
- Stack switching (`xchg esp,eax`) is the i386 data/call stack trick
- SHORT jumps (`$EB`, `$74`) — 1-byte relative offsets
- `align` emits NOPs before `BEGIN`

## x86-64: Using GDB with `int3`

The x86-64 `ff64` does not have `see`. Instead, define an `int3` macro
that emits a software breakpoint (`$CC`) into generated code, then run
under GDB:

### Step 1: Define the `int3` macro

```forth
: int3` >S0 $CC c, ;
```

This is a compile-time macro (backtick name) that emits a single `$CC`
byte (x86 INT 3 instruction) into the word being compiled.

### Step 2: Place `int3` at the start of the word under test

```forth
: t int3 5 BEGIN 0- 0<> WHILE dup . space 1- REPEAT drop cr ;
t ;
```

### Step 3: Run under GDB

```bash
printf ': int3` >S0 $CC c, ;\n: t int3 5 BEGIN 0- 0<> WHILE dup . space 1- REPEAT drop cr ;\nt ;\n' \
  > /tmp/test.ff

gdb -batch \
  -ex "run -f ff64.boot < /tmp/test.ff" \
  -ex "x/30i \$rip" \
  ./ff64_dbg
```

GDB stops at the `int3` (SIGTRAP), and `$rip` points to the instruction
immediately after it — the start of `t`'s compiled body:

```
Program received signal SIGTRAP, Trace/breakpoint trap.
0x0000000000427339 in _start ()
=> 0x427339:  lea    -0x8(%r15),%r15      ; push NOS onto data stack
   0x42733d:  mov    %rdx,(%r15)
   0x427340:  mov    %rbx,%rdx
   0x427343:  mov    $0x5,%ebx            ; literal 5
   0x427348:  test   %rbx,%rbx            ; 0- 0<>: test TOS
   0x42734b:  je     0x42736d             ; WHILE: exit if zero
   0x427351:  lea    -0x8(%r15),%r15      ; dup
   0x427355:  mov    %rdx,(%r15)
   0x427358:  mov    %rbx,%rdx
   0x42735b:  call   0x426e69             ; call .
   0x427360:  call   0x426511             ; call space
   0x427365:  dec    %rbx                 ; 1-
   0x427368:  jmp    0x427348             ; REPEAT: loop back
   0x42736d:  mov    (%r15),%rbx          ; drop
   0x427370:  lea    0x8(%r15),%r15
   0x427374:  xchg   %rbx,%rdx
   0x427377:  jmp    0x401190             ; tail-call cr
```

### Step 4: Look up call targets

GDB shows raw addresses for calls. To identify them, look at the
assembly source or check what word lives at that address:

```bash
gdb -batch -ex "x/3i 0x426e69" ./ff64_dbg
# Shows the entry point of the . (dot) word
```

## Marker Technique: Annotating Generated Code

When multiple macros emit similar-looking code (all E9 jumps look the
same), it's hard to tell which macro produced which section. The
**marker technique** uses `mov r10d, <ID>` to tag each section.

### Why r10?

Register `r10` is completely unused by the FreeForth2 x86-64 kernel.
`mov r10d, imm32` is a 6-byte no-op that's harmless at runtime but
clearly visible in disassembly.

### Define marker macros

```forth
: M1` >S0 $41 c, $BA c, 1 d, ;   \ emits: mov r10d, 1
: M2` >S0 $41 c, $BA c, 2 d, ;   \ emits: mov r10d, 2
: M3` >S0 $41 c, $BA c, 3 d, ;   \ emits: mov r10d, 3
: M4` >S0 $41 c, $BA c, 4 d, ;   \ emits: mov r10d, 4
: int3` >S0 $CC c, ;
```

The byte encoding is:
- `$41` — REX.B prefix (access r10)
- `$BA` — `mov r10d, imm32` opcode (r10 = register 2 + REX.B)
- 4-byte little-endian ID (via `d,`)

### Example: Debugging START/BREAK/END

```forth
: t int3 5
    M1 START
      1- dup . space
      dup 3 - 0- 0= IF drop M2 BREAK
      drop 0- 0= IF M3 BREAK
    M4 END
    drop cr ;
t ;
```

GDB output (annotated):

```
=> 0x427519:  lea    -0x8(%r15),%r15      ; push NOS
   0x42751d:  mov    %rdx,(%r15)
   0x427520:  mov    %rbx,%rdx
   0x427523:  mov    $0x5,%ebx            ; literal 5

   0x427528:  mov    $0x1,%r10d           ; ◀ MARKER 1: START
   0x42752e:  jmp    0x427533             ;   START's forward E9

   0x427533:  dec    %rbx                 ;   1- (loop body)
   ...                                    ;   dup . space
   ...                                    ;   dup 3 -
   0x42756d:  test   %rdx,%rdx            ;   0- 0=
   0x427573:  jne    0x42758e             ;   IF (skip BREAK if nonzero)
   0x427579:  ...                         ;   drop
   0x427583:  mov    $0x2,%r10d           ; ◀ MARKER 2: BREAK (first)
   0x427589:  jmp    0x4275b7             ;   BREAK's forward E9

   0x42758e:  ...                         ;   drop
   0x427595:  test   %rdx,%rdx            ;   0- 0=
   0x42759b:  jne    0x4275ac             ;   IF (skip BREAK if nonzero)
   0x4275a1:  mov    $0x3,%r10d           ; ◀ MARKER 3: BREAK (second)
   0x4275a7:  jmp    0x4275b7             ;   BREAK's forward E9

   0x4275ac:  mov    $0x4,%r10d           ; ◀ MARKER 4: END
   0x4275b2:  jmp    0x427533             ;   END's backward E9 (to body)

   0x4275b7:  ...                         ;   drop (BREAK target)
   ...                                    ;   tail-call cr
```

Each `mov r10d, <N>` immediately identifies the macro that generated
the surrounding code, even without symbolic names.

## Debugging Crashes in Generated Code

When ff64 crashes (SIGSEGV, SIGILL), GDB shows the crash location:

```bash
printf '<test code>\n' > /tmp/crash.ff
gdb -batch \
  -ex "run -f ff64.boot < /tmp/crash.ff" \
  -ex "bt" \
  -ex "info reg rip rbx rdx r15 rbp rsp" \
  -ex "x/10i \$rip" \
  ./ff64_dbg
```

### Common crash patterns

**`movslq (%rbx),%rbx` with rbx = small/negative number:**
This is `d@` (32-bit fetch). It means TOS contains garbage instead of
a valid address. Check what pushed the bad value — often a compile-time
stack corruption (e.g., a constant value leaking onto the runtime stack).

**`jmp 0x9` or `call 0x2a` (jump to small number):**
The compiler generated a call/jump to a literal value instead of an
address. This indicates a ct=1 (DATA) word's value was used where an
execution token was expected — likely a compile-time stack ordering bug.

**`mov %edx,(%rbx)` with rbx = 0:**
This is `d!` (32-bit store) to address zero. Usually means a stack
underflow left zero in TOS.

### Reading the return stack

The call/return stack shows where execution came from:

```
(gdb) x/4gx $rsp
0x7fffffffe898:   0x0000000000426adb   0x0000000000401234
```

Each 8-byte value is a return address. Cross-reference with the
disassembly to find which word called into the crash site.

### Stepping through generated code

For interactive debugging (not `-batch`), set a breakpoint at the word's
entry using `int3`:

```bash
printf ': int3` >S0 $CC c, ;\n: t int3 <code> ;\nt ;\n' > /tmp/step.ff
gdb -ex "handle SIGTRAP stop" -ex "run -f ff64.boot < /tmp/step.ff" ./ff64_dbg
```

Then use GDB's `si` (step instruction) and `ni` (next instruction) to
trace execution one instruction at a time. Use `info reg` to check
register values at each step.

## Register Reference

When reading x86-64 generated code:

| Register | Role | Notes |
|----------|------|-------|
| `rbx`    | TOS (top of stack) | Or NOS when SWAPbit is set |
| `rdx`    | NOS (second on stack) | Or TOS when SWAPbit is set |
| `r15`    | Data stack pointer | Grows downward; `[r15]` = third item |
| `rbp`    | Compilation pointer (`here`) | Only meaningful at compile time |
| `rsp`    | Return stack pointer | Standard call/ret usage |
| `rax`    | Scratch | Used by compiler, syscalls |
| `rcx`    | Scratch | `ch` used by SWAPbit macros (_s01/_s08/_s09) |
| `r10`    | **Unused** | Safe for debug markers |

## Common Code Patterns

Recognizing these patterns in disassembly helps identify what Forth code
generated them:

```
; push NOS, mov NOS←TOS (first half of DUP)
lea    -0x8(%r15),%r15
mov    %rdx,(%r15)
mov    %rbx,%rdx

; literal N
mov    $0xN,%ebx              ; 32-bit (zero-extends)
; or for large values:
movabs $0xNNNN,%rbx           ; 64-bit

; drop
mov    (%r15),%rbx
lea    0x8(%r15),%r15

; swap (when compiler emits it)
xchg   %rbx,%rdx

; FLAGS test: 0- 0= (is TOS zero?)
test   %rbx,%rbx              ; or: test %rdx,%rdx
je     <target>                ; IF (enter block when zero)
; or:
jne    <target>                ; IF with inverted sense

; FLAGS test: 0- 0<> (is TOS nonzero?)
test   %rbx,%rbx
jne    <target>

; comparison: = (TOS == NOS?)
cmp    %rbx,%rdx              ; or: cmp %rdx,%rbx
je     <target>                ; IF
; Note: both values remain on stack after cmp

; tail-call optimization (last call in a definition)
jmp    <target>                ; instead of call + ret

; subroutine call
call   <target>

; BEGIN...REPEAT loop
<begin>:  ...                  ; loop body
          jmp    <begin>       ; REPEAT (unconditional backward jump)

; BEGIN...WHILE...REPEAT loop
<begin>:  test   ...           ; condition
          je     <exit>        ; WHILE (conditional forward jump)
          ...                  ; loop body
          jmp    <begin>       ; REPEAT (backward jump)
<exit>:   ...

; START...IF BREAK...END loop
          jmp    <body>        ; START's forward E9 (patched by ENTER, or no-op)
<body>:   ...                  ; loop body
          test   ...           ; condition
          jne    <skip>        ; IF (skip BREAK when condition false)
          jmp    <after>       ; BREAK (forward exit)
<skip>:   ...
          jmp    <body>        ; END (backward to body start)
<after>:  ...                  ; after loop (BREAK target)
```

## Tips

1. **Check generated code first.** Don't theorize about what the
   compiler should have emitted — look at what it actually did.

2. **Use i386 `see` as a reference.** When porting a word, disassemble
   the i386 version with `see` to understand the expected code structure,
   then compare with the x86-64 GDB output.

3. **Markers are removable.** They add 6 bytes per marker and slightly
   change code layout. For final testing, remove them and re-verify.

4. **The `add %al,(%rax)` pattern is zeros.** GDB disassembles `00 00`
   as `add %al,(%rax)`. This means you've scrolled past the end of the
   compiled word into uninitialized memory.

5. **Addresses change between runs.** The exact addresses of generated
   code depend on how much was compiled before. Don't hardcode breakpoint
   addresses — use `int3` in the Forth source instead.
