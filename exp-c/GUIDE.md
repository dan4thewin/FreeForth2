# Portable FreeForth2 — Guide

_A tour of the proof-of-concept code for a future historian._

This document explains how the portable FreeForth2 experiments work
and why they're structured the way they are.  It covers the key ideas,
the bugs, and the design decisions — walking through the code in the
order you'd need to understand it.

If you want the chronological narrative (what we tried, what failed,
what we learned), read `JOURNAL.md`.  This guide is the conceptual
map.

## Who did what

Christophe Lavarenne (1956–2011) created FreeForth.  DG maintains it
and directs the x86-64 port (166+ experiments on the `static-elf64`
branch).  The portable-C exploration was DG's idea: can the assembly
core be replaced by C, making FreeForth2 run on any architecture GCC
supports?

DG made the key design decisions:
- Abandon SWAPbit (too wired to x86 ModR/M encoding)
- Decompose primitives: C does the ALU, FreeForth does the plumbing
- Use FLAGS-based conditionals (not stack booleans)

An AI implemented the experiments under DG's direction.


## Part 1: The Core Idea

FreeForth compiles Forth words into machine code.  A backtick macro
like `` + `` copies the machine-code bytes of the `add` primitive
into whatever definition is being compiled.  No interpreter loop, no
bytecode — the compiled Forth IS native code.

The original FreeForth is hand-written x86 assembly.  The question:
can a C compiler generate those primitive bytes for us?

The answer is yes, with two requirements:
1. GCC's global register variables pin TOS, NOS, and DSP to specific
   CPU registers, so primitives compile to pure register operations
   with no prologue or epilogue.
2. All pinned registers must be callee-saved, so C library calls
   (printf, strcmp, strtol) don't corrupt the Forth stack.

| Role | x86-64 | ARM64 | Why callee-saved? |
|------|--------|-------|-------------------|
| TOS  | rbx    | x19   | Survives C calls |
| NOS  | r13    | x20   | Survives C calls |
| DSP  | r15    | x21   | Survives C calls |

This is NOT the same as ff64's register assignment (which uses rdx
for NOS).  ff64 never interleaves C code between primitives.  The
portable version's compiler engine IS C code, so every register must
survive C function calls.


## Part 2: Primitive Byte Extraction

A C function like:

```c
register long tos asm("rbx");
register long nos asm("r13");

void __attribute__((noinline)) alu_add(void) { tos += nos; }
```

compiled with `-O2 -fomit-frame-pointer` produces on x86-64:

```
alu_add:
    add %r13, %rbx    ; 3 bytes
    ret                ; 1 byte
```

No prologue, no frame pointer, no register saves — just the
operation and a return.  On ARM64:

```
alu_add:
    add x19, x19, x20   ; 4 bytes
    ret                  ; 4 bytes
```

We extract the body bytes at runtime by scanning forward from the
function's address until we find the RET instruction.  On x86-64,
RET is the byte `0xC3`.  On ARM64, RET is the 4-byte pattern
`0xD65F03C0`.  Everything before the RET is the body we copy into
compiled Forth definitions.

**The false RET bug (exp 008):** On x86-64, the byte `0xC3` also
appears as the ModRM encoding for `rbx` in `mov %rax, %rbx`
(`48 89 C3`).  A forward scan finds this false match before the
real RET.  The fix: scan backward from the end of the function
range.  The last `0xC3` is always the real RET.

**See:** `exp-c/001-naked-prims/` (byte generation), `exp-c/002-byte-extract/`
(extraction), `exp-c/008-flags-flow/minicompiler.c` lines 111–123
(backward scan).


## Part 3: Copy, Compose, Execute

Once we have the bytes of a primitive, we can copy them into an
executable buffer and run them.  Experiment 003 proved this by
composing `dup` + `add` into an mmap'd buffer:

```
[dup bytes][add bytes][RET]
```

Call it as a function pointer.  Input TOS=21, output TOS=42.  The
composed code is position-independent — no absolute addresses, no
relative jumps, just register operations.

**See:** `exp-c/003-copy-execute/`


## Part 4: The Mini-Compiler

Experiment 004 built the first real compiler: a C program that
parses Forth source, looks up words in a dictionary, and emits
machine code into a buffer.

### How it compiles

For each word in the source:
- **Primitive** → copy its bytes inline (the backtick mechanism)
- **Colon definition** → emit a CALL to its entry point
- **Number** → emit `dup` bytes + a load-immediate sequence

Colon definitions start with a prologue and end with an epilogue
(explained below).  The dictionary stores each word's name, code
pointer, body length, and whether it's a primitive (inline) or a
colon definition (call).

### The NOS bug (exp 004)

The first version used `rdx` for NOS — a caller-saved register.
Every C function call (strcmp, dict_find, the eval loop itself)
silently corrupted NOS.  The fix: switch to `r13` (callee-saved).
GCC warned about it: `call-clobbered register used for global
register variable`.  Lesson: ALL pinned registers must be
callee-saved.

**See:** `exp-c/004-mini-compiler/`


## Part 5: Cross-Architecture Portability

Experiment 005 proved the same C source compiles correctly on both
x86-64 and ARM64.  The only per-architecture code is the register
declarations:

```c
#if defined(__aarch64__)
register long tos asm("x19");
#elif defined(__x86_64__)
register long tos asm("rbx");
#endif
```

ARM64 sometimes produces better code than hand-written assembly.
GCC used `ldp x19, x20, [x21], #16` for `store` — a single
instruction that loads two registers and advances the stack pointer.

**See:** `exp-c/005-cross-arch/`


## Part 6: Platform Differences

Experiment 006 brought the mini-compiler to macOS ARM64, revealing
two platform-specific problems.

### W^X: Writable XOR Executable

Modern OSes don't allow memory to be both writable and executable
at the same time.  The compiler needs to write code, then execute it.

**Linux** solves this with dual mapping: `memfd_create` + two
`mmap` calls give you two virtual addresses over the same physical
memory.  `codebuf_w` (RW) is where the compiler writes.
`codebuf_x` (RX) is where the CPU runs.  Changes to one appear
instantly in the other.

**macOS** rejects `PROT_EXEC` on shared mappings entirely.  Instead,
Apple provides `MAP_JIT`: a single mapping that toggles between
write mode and execute mode:

```c
pthread_jit_write_protect_np(0);  // write mode
// ... compile code ...
pthread_jit_write_protect_np(1);  // execute mode
sys_icache_invalidate(buf, size); // flush icache
// ... run code ...
```

On Linux, the toggle functions are no-ops.

### ARM64 Nested Calls: The Nonleaf Frame Problem

x86-64's `CALL` pushes the return address onto the stack
automatically.  ARM64's `BL` (branch-with-link) writes the return
address to register x30 — it doesn't push.  If function A calls B
calls C, B's `BL C` overwrites x30, and B can never return to A.

In hand-written assembly, the fix is explicit: save x30 to the
stack at function entry, restore it before returning.  In C,
the compiler does this automatically for any non-leaf function.

We exploit this: write a C "template" function that calls another
function, forcing GCC to emit the save/restore:

```c
void __attribute__((noinline)) template_nonleaf(void)
{
    alu_add();
    asm volatile("");  // prevent tail-call optimization
}
```

We extract the bytes before the first CALL (= prologue) and after
it through RET (= epilogue).  The compiler decides what's needed:

| Architecture | Prologue | Epilogue |
|-------------|----------|----------|
| x86-64 | 0 bytes | 1 byte (just RET) |
| x86-64 + CET | 4 bytes (ENDBR64) | 1 byte |
| ARM64 | 4 bytes (STR x30) | 8 bytes (LDR x30 + RET) |

Every colon definition is wrapped: `prologue + body + epilogue`.

CET (Control-flow Enforcement Technology) is an Intel security
feature.  When enabled, GCC inserts `ENDBR64` at the start of every
function — a "valid branch target" marker.  It's a NOP on older
CPUs.  Our extraction picks it up as prologue bytes automatically.

**See:** `exp-c/006-mac-arm64/minicompiler.c`


## Part 7: Flow Control — First Attempt (Stack Booleans)

Experiment 007 added IF/THEN and BEGIN/UNTIL using stack booleans:
`0=` pushes -1 (true) or 0 (false), and IF tests that value.

It worked.  But it's not how FreeForth works.

**The problem:** GCC compiles `dsp++` (used in `drop`, `+`, `-`,
every consuming primitive) as `ADD $8, %r15` on x86-64.  ADD
clobbers CPU FLAGS.  If you test a value, then drop it, the flags
from the test are destroyed by the ADD inside drop.

ARM64 doesn't have this problem — `ADD` without the `S` suffix
preserves condition flags.

The workaround in exp 007: save the boolean to a scratch register
(RAX) before drop, test the scratch after drop.  It's portable but
foreign to FreeForth's design.

**See:** `exp-c/007-flow-control/minicompiler.c`


## Part 8: Flow Control — FLAGS Restored

DG asked the key question: "If FreeForth controls the stack ops
and uses LEA instead of ADD, flags survive through drop — yes?"

Yes.

### The Decomposition

The insight is that GCC should NOT compile the full primitive.  If
we write `void prim_add(void) { tos += nos; nos = *dsp; dsp++; }`,
GCC picks ADD for `dsp++` and we lose flag control.  Instead:

| Layer | Who picks instructions | Example |
|-------|----------------------|---------|
| C ALU primitives | GCC | `tos += nos` → `add r13, rbx` |
| Inline asm macros | Us | `lea 8(%r15), %r15` (not ADD!) |
| Composed Forth words | Init code | `+` = alu_add + drop_nos |

C ALU primitives are pure register-to-register operations.  GCC
picks the optimal instruction (ADD, SUB, etc.) and we extract the
bytes.  These are the `over+` variants — they modify TOS and/or NOS
but never touch the memory stack.

Inline asm macros are `__attribute__((noinline))` functions with
`asm volatile(...)` inside.  WE choose the instructions.  On
x86-64, `drop_nos` uses LEA (flags-preserving).  On ARM64, it uses
post-indexed LDR (`ldr x20, [x21], #8`), which is also
flags-preserving.

Both are extracted at runtime using the same find_ret scanning.
From the outside, they look identical to C ALU prims — just
functions with byte bodies.  The difference is who chose the
instructions.

### Composed Words

During initialization, the compiler combines fragments into full
Forth words stored in the code buffer:

```c
// + = alu_add + drop_nos
start = here;
emit_bytes(alu[ALU_ADD].code, alu[ALU_ADD].len);
emit_bytes(mac[MAC_DROP_NOS].code, mac[MAC_DROP_NOS].len);
dict_add("+", codebuf_x + start, here - start, /*is_prim=*/1);
```

The resulting `+` is 10 bytes on x86-64 (3 add + 7 drop_nos) and
8 bytes on ARM64 (4 add + 4 ldr).  These are competitive with
hand-written assembly.  They're marked as primitives (inline) in
the dictionary.

### FLAGS Through Drop

The FreeForth pattern:

```
value 0- 0= drop IF ... THEN
```

1. **`0-`** = `test rbx, rbx` (x86-64) or `tst x19, x19` (ARM64).
   Sets ZF based on TOS.  No stack change.  This is a per-arch
   inline asm macro.

2. **`0=`** = compile-time only.  Stores "JZ" in the `cond_jmp`
   variable.  Emits zero runtime bytes.

3. **`drop`** = `mov r13, rbx; mov [r15], r13; lea 8(%r15), %r15`.
   All MOV + LEA — every instruction is flags-preserving on x86-64.
   On ARM64: `mov x19, x20; ldr x20, [x21], #8` — also
   flags-preserving.

4. **`IF`** = reads `cond_jmp`, inverts it (XOR 1), emits a
   conditional forward branch.  `cond_jmp=JZ` → emit JNZ forward
   (skip body when condition is false).

The flags from step 1 survive through step 3 because drop never
uses ADD.  This is the same mechanism as the original FreeForth —
Lavarenne used LEA for the same reason.

### ARM64 ALU Ops Don't Set Flags

On x86-64, `ADD` and `SUB` always set flags.  On ARM64, they don't
— only `ADDS` and `SUBS` do.  GCC emits the non-flag-setting form
from C code because nothing in C reads the flags.

This means that any word FreeForth relies on for flag-setting must
emit a flag-setting instruction on every architecture.  On x86-64
this is automatic — all ALU ops set flags.  On ARM64, it requires
choosing `SUBS`/`ADDS` over `SUB`/`ADD`.

The inline asm mechanism solves this.  Words like `-`, `+`, `1-`,
`1+`, `&`, `|`, `^`, and `0-` need to be inline asm macros (not
pure C ALU prims) so we can pick `SUBS` on ARM64 while x86-64
gets flag-setting ADD/SUB for free.  `0-` is just one example —
the non-destructive test case.  The full palette of flag-setting
words all need the same treatment.

In the current proof-of-concept (exp 008), only `0-` is
implemented as a flag-setting macro.  A production system would
need to promote all flag-setting ALU ops from C prims to inline
asm macros on ARM64.  This is the same ~20-line-per-arch cost,
just applied to more words.

**See:** `exp-c/008-flags-flow/minicompiler.c` — the final form of
the proof-of-concept.


## Part 9: Per-Architecture Cost

Adding a new architecture requires:

1. **Three register names** — callee-saved, for TOS/NOS/DSP.

2. **RET pattern** — for primitive byte extraction.  One byte on
   x86-64 (`0xC3`), four bytes on ARM64 (`0xD65F03C0`).

3. **CALL/BL pattern** — for nonleaf frame extraction.  `0xE8` on
   x86-64, `0x94xxxxxx` on ARM64.

4. **~6 inline asm macros** — `drop_tos`, `drop_nos`, `push_nos`,
   `dup`, `swap`, `test_tos`.  These are the flags-preserving stack
   operations specific to each architecture.

5. **~5 branch emission functions** — `emit_call`, `emit_load_imm`,
   `emit_cond_forward`, `emit_cond_backward`, `patch_forward_branch`.
   These write architecture-specific instruction encodings.

Everything else — the compiler engine, dictionary, eval loop,
init/compose logic — is portable C.

For reference, the x86-64 specific code in exp 008 is about 120
lines.  A new architecture port would be roughly the same.

The C reference functions (`ref_flags_through_drop`, etc.) exist
as a porting aid: `objdump -d` them on the new target to see what
instructions GCC emits, then write the inline asm macros to match.


## Part 10: What Remains

The experiments prove viability for:
- Primitive byte extraction from C ✓
- Runtime composition into executable buffers ✓
- Colon definitions with nested calls ✓
- Cross-architecture portability (x86-64 + ARM64) ✓
- W^X code buffers on both Linux and macOS ✓
- FLAGS-based conditionals with IF/THEN/BEGIN/UNTIL ✓

What hasn't been built yet:
- Full flow control (ELSE, WHILE/REPEAT, BREAK, CASE)
- The dictionary structure in Forth (headers, `find`, `create`)
- Backtick macros and suffix handling
- Boot file loading (ff2.boot equivalent)
- String handling and I/O
- The REPL
- Return stack operations (`>r`, `r>`, `r`)
- More comparison words (`<`, `>`, `=`, `0<`)
- Interaction between global register variables and libc edge cases

The proof-of-concept is solid.  The open question is whether the
full FreeForth system can be rebuilt on this foundation — or whether
some corner of the design will resist the C-based approach.


## File Map

```
exp-c/
├── PLAN.md              Project plan (original 5-experiment scope)
├── TODO.md              Active / deferred / done tracking
├── JOURNAL.md           Chronological narrative of all experiments
├── GUIDE.md             This file — conceptual tour
├── Makefile             Runs all experiment tests
│
├── 001-naked-prims/     GCC produces clean primitive functions
│   ├── Makefile
│   └── prims.c
│
├── 002-byte-extract/    Runtime byte extraction via pointer arithmetic
│   ├── Makefile
│   └── extract.c
│
├── 003-copy-execute/    Compose dup+add, execute → 42
│   ├── Makefile
│   └── copyexec.c
│
├── 004-mini-compiler/   First Forth compiler: literals, colon defs
│   ├── Makefile
│   └── minicompiler.c
│
├── 005-cross-arch/      Same source → correct x86-64 and ARM64
│   ├── Makefile
│   └── prims_portable.c
│
├── 006-mac-arm64/       Portable compiler: Linux + macOS, W^X, nonleaf
│   ├── Makefile
│   └── minicompiler.c
│
├── 007-flow-control/    IF/THEN, BEGIN/UNTIL (stack booleans)
│   ├── Makefile
│   └── minicompiler.c
│
└── 008-flags-flow/      FLAGS-based flow (C ALU + asm stack macros)
    ├── Makefile
    └── minicompiler.c   ← The definitive proof-of-concept
```

Each experiment is self-contained with its own Makefile.  `make test`
in any experiment directory runs its tests.  `make test` in `exp-c/`
runs all of them.


## Reading the Code

The best entry point is `exp-c/008-flags-flow/minicompiler.c`.  It's
~600 lines of code (plus comments) and contains every technique
developed across all 8 experiments.  Read it in this order:

1. **Lines 28–170**: Per-arch section.  Register declarations,
   `find_ret`, `emit_call`, `emit_load_imm`, branch emission.
   This is the "~20 macros" per architecture.

2. **Lines 172–192**: C ALU primitives.  Five one-line functions.
   GCC picks the instructions.  Compare `alu_add` (3 bytes x86-64)
   with the ARM64 version (4 bytes) using `objdump -d`.

3. **Lines 194–262**: Inline asm macros.  Six functions.  WE pick
   the instructions.  Notice `lea` on x86-64 vs `ldr` post-indexed
   on ARM64 — both flags-preserving.

4. **Lines 264–320**: Nonleaf template extraction.  How prologue and
   epilogue bytes are discovered from a C function that calls another.

5. **Lines 390–430**: Initialization.  Byte discovery for both ALU
   and macro tables, then word composition (`+` = alu_add + drop_nos).

6. **Lines 470–540**: `process_word`.  The compiler/interpreter.
   Note `0=` and `0<>` — compile-time only, zero runtime bytes.
   Note `IF` and `UNTIL` — invert the condition, emit a branch.

7. **Lines 580–620**: Tests.  12 tests covering arithmetic, colon
   definitions, nested calls, FLAGS-based IF/THEN, and BEGIN/UNTIL.
