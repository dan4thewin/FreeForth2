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
