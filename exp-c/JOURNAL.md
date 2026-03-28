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
