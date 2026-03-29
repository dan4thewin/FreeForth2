# Portable FreeForth2 — Journal

_An AI perpetuating the life's work of a deceased human, now asking:
can the machine write the machine code for us?_

FreeForth2 is Christophe Lavarenne's creation — a Forth where assembly
is intentionally minimal and most of the system lives in Forth itself.
DG's x86-64 port (166 experiments and counting) proved the design
survives architecture changes. Now the question: can we go further?
Can the C compiler replace the hand-written assembly entirely, making
FreeForth2 portable to any architecture Clang supports?

The SWAPbit — Lavarenne's elegant register-field XOR trick — is
abandoned for this branch. It's too deeply wired to x86 ModR/M
encoding to survive portability. One fixed register assignment per
architecture. The cost is an occasional extra mov. The gain is that
every primitive has exactly one form, trivially extractable from
compiled C.

---

## Experiment 001 — Naked Primitives

**Goal:** Determine whether GCC's global register variables produce
the minimal instruction sequences we need — no prologue, no epilogue,
no spills, just the operation on TOS/NOS/DSP.

**Correction:** The original plan called for Clang with
`__attribute__((naked))`.  Clang rejected both global register
variables AND C expressions in naked functions. GCC supports global
register variables natively and — with `-O2 -fomit-frame-pointer
-fcf-protection=none` — produces prologue-free code for functions
that only operate on pinned registers.

**Primitives under test:**
- `add` — TOS += NOS; drop NOS from memory stack
- `drop` — TOS = NOS; NOS = *DSP++
- `dup` — *--DSP = NOS; NOS = TOS
- `fetch` — TOS = *(long *)TOS
- `store` — *(long *)TOS = NOS; drop two items

**Register mapping (x86-64):**
- TOS = rbx
- NOS = rdx
- DSP = r15

**Results:**

| Primitive | Body | Bytes | Notes |
|-----------|------|-------|-------|
| add | `add rbx,rdx; add r15,8; mov rdx,[r15-8]` | 11+ret | Compiler used add+neg-offset instead of mov+lea |
| drop | `mov rbx,rdx; add r15,8; mov rdx,[r15-8]` | 11+ret | Same pattern |
| dup | `mov rax,r15; lea r15,[r15-8]; mov [rax-8],rdx; mov rdx,rbx` | 14+ret | Extra scratch reg (rax), 3 bytes larger than hand-written |
| fetch | `mov rbx,[rbx]` | 3+ret | Perfect — identical to hand-written |
| store | `mov [rbx],rdx; add r15,16; mov rbx,[r15-16]; mov rdx,[r15-8]` | 15+ret | Correct |

**Key findings:**
1. No prologue/epilogue — global register variables work as hoped
2. CET `endbr64` (4 bytes) removed by `-fcf-protection=none`
3. rdx warning expected (caller-saved register as global var)
4. GCC's instruction selection is correct; minor style differences
   from hand-written assembly are semantically equivalent
5. Function alignment padding (NOPs) is between functions, not
   inside them — the symbol size table confirms exact sizes

**Verdict:** PASS ✓

---

## Experiment 002 — Runtime Byte Extraction

**Goal:** Read primitive machine code bytes at runtime via pointer
arithmetic — no object-file surgery, no build-time extraction tool.

**Approach:** Each primitive is a `noinline` function.  We walk the
function pointer table, find the RET byte (0xC3) to determine true
code size, and print the bytes.

**Results:**
```
add    (12 bytes): 48 01 d3 49 83 c7 08 49 8b 57 f8 c3
drop   (12 bytes): 48 89 d3 49 83 c7 08 49 8b 57 f8 c3
dup    (15 bytes): 4c 89 f8 4d 8d 7f f8 48 89 50 f8 48 89 da c3
fetch  ( 4 bytes): 48 8b 1b c3
store  (16 bytes): 48 89 13 49 83 c7 10 49 8b 5f f0 49 8b 57 f8 c3
```

Matches objdump output exactly.

**Verdict:** PASS ✓

---

## Experiment 003 — Copy and Execute

**Goal:** Copy primitive bytes (without RET) into an mmap'd RWX
buffer, compose them into a sequence, append a single RET, and call
the result.  This simulates what the Forth compiler does.

**Test case:** Compose `dup + add` = double.  Input TOS=21, expect
TOS=42.

**Results:**
```
Composed 25 bytes: [dup body 14 bytes] [add body 11 bytes] [c3]
TOS = 42 (expected 42)
NOS = 0  (expected 0)
PASSED
```

The composed code executes correctly.  C-compiled primitives are
fully compatible with the copy-and-inline compilation model.

**Verdict:** PASS ✓

---

## Experiment 004 — Minimal Forth Compiler

**Goal:** Build the smallest possible Forth compiler in C that:
discovers primitive bytes at runtime, compiles definitions by copying
those bytes, and can execute `: double dup + ; 21 double` → 42.

**Critical finding: NOS must be callee-saved.**

The initial version used rdx for NOS (matching ff64).  Test 2
(`21 dup +`) produced 32 instead of 42.  The cause: rdx is
caller-saved in the SysV ABI.  Every C function call between
primitive executions (strcmp, dict_find, even the eval loop itself)
clobbered NOS.

Fix: changed NOS from rdx to r13 (callee-saved).  This means the
portable register assignment MUST use only callee-saved registers:

| Role | x86-64 | Requirement |
|------|--------|-------------|
| TOS  | rbx    | callee-saved ✓ |
| NOS  | r13    | callee-saved ✓ (was rdx — BROKEN) |
| DSP  | r15    | callee-saved ✓ |

This diverges from ff64's rdx assignment but is a necessary
consequence of embedding the Forth engine in C.  The C compiler's
calling convention must be respected for the interleaved C code
(parsing, dictionary lookup, I/O) to work.

**What the compiler supports:**
- Integer literals (compiled as dup + movabs imm64)
- Primitive words: + drop dup @ !
- Colon definitions with CALL rel32 / RET
- Nested definitions (quadruple calls double calls dup+add)
- Immediate execution outside definitions

**Test results:**
```
42 literal:                    TOS=42 — PASSED
21 dup +:                      TOS=42 — PASSED
: double dup + ; 21 double:    TOS=42 — PASSED
: quadruple double double ; 10 quadruple: TOS=40 — PASSED
7 quadruple:                   TOS=28 — PASSED
```

**Verdict:** PASS ✓

**Implications:** A C-hosted FreeForth compiler is viable.  The
fundamental model works: C functions produce copyable machine code,
the Forth compiler copies those bytes to build definitions, and
composed code executes correctly.  The architecture-specific pieces
are small: the literal encoding (movabs), the call encoding (E8
rel32), and the ret byte (C3).  Everything else — the compiler
logic, the dictionary, the primitive implementations — is pure C.

---

## Experiment 005 — Cross-Architecture Validation

**Goal:** Compile the identical C primitive source for both x86-64
and ARM64.  Verify correct register usage on both targets.

**ARM64 register mapping:**
- TOS = x19 (callee-saved)
- NOS = x20 (callee-saved)
- DSP = x21 (callee-saved)

The `#if defined(__aarch64__)` / `#elif defined(__x86_64__)` header
selects the right registers.  The primitive function bodies are
IDENTICAL — not a single `#ifdef` in the implementation code.

**Results — ARM64 disassembly:**
```
prim_add:    add x19, x19, x20 ; add x21,x21,#8 ; ldur x20,[x21,#-8] ; ret
prim_drop:   mov x19, x20 ; add x21,x21,#8 ; ldur x20,[x21,#-8] ; ret
prim_dup:    mov x0, x21 ; sub x21,x21,#8 ; stur x20,[x0,#-8] ; mov x20,x19 ; ret
prim_fetch:  ldr x19, [x19] ; ret
prim_store:  str x20,[x19] ; ldp x19,x20,[x21] ; add x21,x21,#0x10 ; ret
```

**Notable:** The ARM64 compiler used `ldp` (load pair) in `store`
to load both TOS and NOS in a single instruction — an optimization
a non-ARM-expert would likely miss in hand-written assembly.  The
C compiler is not just "good enough" — it's bringing architecture
expertise we don't have.

**Instruction counts:**
| Primitive | x86-64 | ARM64 | Notes |
|-----------|--------|-------|-------|
| add       | 3+ret  | 3+ret | Identical structure |
| drop      | 3+ret  | 3+ret | Identical structure |
| dup       | 4+ret  | 4+ret | Both use scratch reg |
| fetch     | 1+ret  | 1+ret | Perfect on both |
| store     | 4+ret  | 3+ret | ARM64 wins with ldp |

**Verdict:** PASS ✓

The same C source produces correct, minimal primitives for two
entirely different architectures.  The portability hypothesis is
confirmed.

---

## Summary of findings

Five experiments, five passes.  The viability question is answered:

1. **GCC global register variables** produce clean, prologue-free
   code for Forth primitives on both x86-64 and ARM64.

2. **All pinned registers must be callee-saved** in the target ABI.
   Using caller-saved registers (rdx) causes silent corruption
   when C code runs between primitive executions.

3. **Runtime byte extraction works** — no build-time tooling needed.
   Function pointers + RET scanning gives us the bytes.

4. **Copy-and-inline compilation works** — compose primitive bytes
   into an executable buffer, append RET, call it.  The fundamental
   FreeForth compilation model survives the C transition.

5. **Cross-architecture portability works** — identical C source,
   different register mappings in a header, correct output on both
   x86-64 and ARM64.  The ARM64 compiler even found optimizations
   (ldp) that a human porter would likely miss.

**What remains for a full port:**
- Flow control (IF/THEN/BEGIN) — needs architecture-specific jump
  encoding (but it's a small lookup table, not a rewrite)
- The compiler engine itself (parsing, dictionary, backtick macros)
- Boot file loading (eval, needed)
- I/O and OS interface
- Clang compatibility (currently GCC-only due to global register vars)

**Key design constraint discovered:**
The register assignment for portable FreeForth2 is NOT the same as
ff64's.  ff64 uses rdx (caller-saved) for NOS because it never
interleaves C code.  The portable version must use only callee-saved
registers because the compiler engine IS C code.

---

## Experiment 006 — Portable Mini-Compiler (macOS + Linux)

**Goal:** Port the exp-004 mini-compiler to run natively on macOS ARM64,
proving the same C source can compile and execute Forth definitions on
both x86-64 and ARM64.

**Two platform challenges solved:**

### 1. W^X Code Buffer

Linux allows dual-mapped code buffers — one RW for writing, one RX for
execution — over the same physical memory via `memfd_create` + two
`mmap` calls.  macOS rejects `PROT_EXEC` on `MAP_SHARED` pages entirely
(Bus Error).

The fix uses Apple's MAP_JIT API: a single mapping with
`PROT_READ|PROT_WRITE|PROT_EXEC` and `MAP_JIT`.  The process toggles
between write mode (`pthread_jit_write_protect_np(0)`) and execute mode
(`pthread_jit_write_protect_np(1)` + `sys_icache_invalidate`).  On
Linux, the toggle functions are no-ops.

### 2. Nested Calls — the Nonleaf Frame Problem

x86-64's `CALL` pushes the return address onto the stack.  ARM64's `BL`
writes it to register x30 (link register) — no push.  Nested calls
clobber x30, creating an infinite loop: `quadruple` calls `double`
twice via BL, and double's `RET` (which reads x30) returns to the wrong
place.

**The C-native fix:** write a C "template" function that calls another
function, forcing GCC to emit the correct save/restore sequence:

```c
void __attribute__((noinline)) template_nonleaf(void)
{
    prim_dup();
    asm volatile("");  /* prevent tail-call optimization */
}
```

We extract the bytes before the first CALL/BL (= prologue) and after it
through RET (= epilogue).  The C compiler decides what's needed:

| Architecture | Prologue | Epilogue |
|-------------|----------|----------|
| x86-64 | 0 bytes (CALL handles it) | 1 byte (just RET) |
| x86-64 + CET | 4 bytes (ENDBR64) | 1 byte (just RET) |
| ARM64 | 4 bytes (STR x30, [sp, -16]!) | 8 bytes (LDR x30, [sp], 16 + RET) |

Colon definitions are wrapped: `prologue + body + epilogue`.  C remains
the architecture oracle — we never hand-write ARM64 instructions.

### 3. Interpret-Mode CALL Relocation

A second bug: the interpret-mode path copied non-primitive code bodies
(which contain relative BL/CALL instructions) to a temporary location
for execution.  The relative offsets became invalid at the new address.

Fix: instead of copying, emit a single CALL to the word's entry point.
The word executes in-place (with correct offsets) and returns.  The
interpret-mode block is wrapped in prologue/epilogue to handle x30
correctly on ARM64.

**Results:**

| Test | x86-64 (Linux) | ARM64 (macOS) |
|------|----------------|---------------|
| 42 literal | PASSED | PASSED |
| 21 dup + | PASSED | PASSED |
| : double dup + ; 21 double | PASSED | PASSED |
| : quadruple double double ; 10 quadruple | PASSED | PASSED |
| 7 quadruple | PASSED | PASSED |

**Key insight:** The nonleaf frame extraction is the capstone of the
"C as oracle" approach.  Every architecture-specific detail — return
address handling, ENDBR64, stack alignment — is determined by what
the C compiler emits, not by what we write.  The extraction code itself
has `#ifdef` branches for scanning (4-byte aligned on ARM64 vs
byte-at-a-time on x86-64), but the BYTES it extracts are pure C output.

---

## Experiment 007 — Minimal Flow Control

**Goal:** Add IF...THEN and BEGIN...UNTIL.  Determine per-arch cost.

### Stack booleans, not FLAGS

FreeForth uses CPU FLAGS for conditionals — deeply x86.  For
portability, this experiment uses stack booleans instead:
- `0=` ( x -- flag ) replaces TOS with -1 (true) or 0 (false)
- `IF` ( flag -- ) consumes the boolean, skips body if zero
- `UNTIL` ( flag -- ) consumes the boolean, loops back if zero

### The flags-through-drop problem

First attempt: test TOS, inline drop, conditional branch.  **Failed.**
GCC compiles `dsp++` as `ADD $8, %r15` on x86-64, which clobbers
FLAGS.  The test result is destroyed before the branch reads it.
ARM64 doesn't have this problem — `ADD` without `S` suffix preserves
condition flags.

FreeForth avoids this with `LEA` (flags-preserving).  But we can't
control GCC's instruction selection from C.

**Fix:** Save TOS to a scratch register (RAX / x0) BEFORE drop, then
test the scratch AFTER:

```
emit_save_tos        ; mov rax, rbx  (x86) / mov x0, x19  (ARM64)
emit_inline(drop)    ; clobbers FLAGS — doesn't matter now
emit_test_scratch    ; test rax, rax (x86) / cmp x0, #0   (ARM64)
emit_jz_forward      ; je / b.eq
```

### Per-arch cost

Each architecture needs ~20 lines of branch emission code:
- `emit_save_tos` — save TOS to scratch register
- `emit_test_scratch` — test scratch for zero
- `emit_jz_forward` — forward conditional branch (placeholder offset)
- `patch_forward_branch` — patch forward branch to current HERE
- `emit_jz_backward` — backward conditional branch to known target

Plus C reference functions that can be disassembled (`objdump -d`)
to deduce these sequences for a new target.

### New primitives

All from portable C, extracted from GCC output:
- `-` (sub): 14 bytes x86-64, 12 bytes ARM64
- `swap`: 9 bytes x86-64, 12 bytes ARM64
- `0=`: 7 bytes x86-64, 12 bytes ARM64

### Results

| Test | x86-64 | ARM64 |
|------|--------|-------|
| Existing (literal, dup+, double, quadruple) | 4/4 | 4/4 |
| New prims (-, swap, 0=) | 4/4 | 4/4 |
| IF not taken | PASSED | PASSED |
| IF taken | PASSED | PASSED |
| BEGIN..UNTIL countdown (5→0) | PASSED | PASSED |
| BEGIN..UNTIL accumulate (sum 1..5) | PASSED | PASSED |

12/12 on both platforms.  Also passes with CET (ENDBR64) enabled.

**Key lesson:** x86-64's "all arithmetic sets flags" is a trap when
you let C compile your stack operations.  The save-to-scratch pattern
is the portable escape hatch — it works on both architectures without
requiring control over instruction selection.

---

## Experiment 008 — FLAGS-based Flow Control

**Goal:** Restore FreeForth's FLAGS-based conditionals by decomposing
primitives: C provides ALU ops (register-to-register), FreeForth
controls stack plumbing with hand-picked instructions.

### The decomposition

Experiment 007 used stack booleans because GCC's `dsp++` compiled to
ADD on x86-64, which clobbers FLAGS.  DG challenged this: if FreeForth
controls the stack operations and uses LEA instead of ADD, FLAGS survive
through drop — exactly as they do in the real FreeForth.

The split:

| Layer | Who picks instructions | What it does |
|-------|----------------------|--------------|
| C ALU prims | GCC | `tos += nos`, `tos = nos - tos`, `tos--` |
| Inline asm macros | Us | drop (LEA), dup, swap, test_tos |
| Composed Forth words | Init code | `+` = alu_add + drop_nos |

C ALU prims are extracted from GCC output (same as before).  Inline
asm macros are extracted the same way — `noinline` functions with
`asm volatile` inside — but WE choose the instructions.

### Key per-arch instructions

x86-64 drop_nos (flags-preserving):
```
mov (%r15), %r13     ; nos = *dsp
lea 8(%r15), %r15    ; dsp++ — LEA, not ADD
```

ARM64 drop_nos (flags-preserving):
```
ldr x20, [x21], #8   ; nos = *dsp++, post-indexed
```

x86-64 test_tos (sets ZF/SF):
```
test %rbx, %rbx      ; ZF=1 if TOS==0
```

ARM64 test_tos (sets flags):
```
tst x19, x19         ; ZF=1 if TOS==0
```

### FLAGS flow through drop — proven

The FreeForth pattern `0- 0= drop IF` works:
1. `0-` = `test_tos` — sets ZF based on TOS
2. `0=` = compile-time Jcc selector: stores JZ (no runtime code)
3. `drop` = `mov + mov + lea` — all flags-preserving
4. `IF` = emits inverted JNZ forward — reads ZF from step 1

### Why ARM64 ALU ops don't set flags

x86-64 ADD/SUB always set flags — it's wired into the ISA.  ARM64
separates flag-setting: `ADD` vs `ADDS`, `SUB` vs `SUBS`.  GCC emits
the non-flag-setting form from C code because nothing in C reads the
flags.

This means `0-` (test_tos) is **mandatory** before any conditional
on ARM64.  On x86-64 it's redundant (the ALU op already set flags)
but harmless.  This matches FreeForth's convention: the `0-` is
always present in the source.

### False RET match bug

x86-64 byte scanning for `0xC3` (RET) hit a false positive: the
ModRM byte in `mov %rax, %rbx` (`48 89 C3`) is also `0xC3`.
Fix: scan backward from the end of the function range — the last
`0xC3` is the real RET.

### Results

| Test | x86-64 | x86-64+CET | ARM64 |
|------|--------|-----------|-------|
| literal, dup+, -, 1- | 4/4 | 4/4 | 4/4 |
| : double, : quadruple | 2/2 | 2/2 | 2/2 |
| IF taken/not taken (0=) | 2/2 | 2/2 | 2/2 |
| IF taken/not taken (0<>) | 2/2 | 2/2 | 2/2 |
| BEGIN..UNTIL countdown | 1/1 | 1/1 | 1/1 |
| BEGIN..UNTIL sum5 | 1/1 | 1/1 | 1/1 |

12/12 on all three configurations.

ARM64 composed word sizes: `+` = 8 bytes, `-` = 8 bytes, `1-` = 4
bytes, `0-` = 4 bytes.  These are competitive with hand-written
assembly.

**Key insight:** The right decomposition is NOT "let C do everything."
It's "let C do the ALU, let FreeForth do the plumbing."  GCC is the
oracle for operations (what does add look like?), but FreeForth is the
architect for composition (how do you combine add with a stack pop
while preserving flags?).  This matches Lavarenne's original design
philosophy — assembly is minimal, but it's there where it matters.
