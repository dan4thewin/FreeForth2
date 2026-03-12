# FreeForth2 x86-64 Port — Timeline

A chronological record of the x86-64 port of FreeForth, built
experiment by experiment from a blank assembly file to a self-hosting
Forth system.  Each entry marks what became possible that wasn't before.

The original FreeForth was imported from Christophe Lavarenne's
ff100104.zip on 2016-03-11.  DG maintained and extended the i386
version through 2024.  The x86-64 port began on 2026-02-22.

### Pace

| Period | Days | Experiments | Notes |
|--------|------|-------------|-------|
| Feb 22 | 1 | 001–020 | Bootstrap + SWAPbit — 20 experiments in one day |
| Feb 23 | 1 | 021–035 | Forth-defined macros + dictionary |
| Feb 23–24 | 1 | 036–050 | Compiler infrastructure, suffix mechanism |
| Feb 24–25 | 2 | 051–069 | Self-booting — the "it works" moment |
| Feb 25–27 | 2 | 070–077 | Hardening, \_parse fix |
| Feb 27–Mar 4 | 6 | 078–134 | Libraries, assembly reduction, parity — the long march |
| Mar 5–6 | 2 | 135–145 | Flow control audit, \_loadfile removal |
| Mar 7 | 1 | 146–150 | hanoi runs, test consolidation |
| Mar 8–11 | 4 | 146–148 (2nd) | FFPATH, ffpp preprocessor |
| **Total** | **~18 days** | **~148 experiments** | |

---

## Phase 1: Bootstrap (Experiments 001–014)

*2026-02-22 afternoon.  Experiments 001–014 committed in a single
batch — the first 14 experiments were done in one session, roughly
6 hours from first commit to last.*

*Building the minimum viable Forth from scratch in x86-64 assembly.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| 001 | Hello World | FASM x86-64 toolchain proven — static ELF, syscall ABI |
| 002 | Data stack via r15 | Two-register TOS/NOS cache (rbx/rdx), memory stack in r15 |
| 003 | Runtime codegen | Write machine code to a buffer and jump to it |
| 004 | Subroutine threading | CALL rel32 linking — words call words |
| 005 | SWAPbit concept | Compile-time register renaming — swap is free |
| 006 | Dictionary + FIND | Header chain, name lookup, compile-or-execute dispatch |
| 007 | Compiler loop | Text → machine code, token by token |
| 008 | Interactive REPL | `> ` prompt, `ok` response, live compilation |
| 009 | Colon definitions | `: name ... ;` — user-defined words |
| 010 | Flow control | IF/THEN/ELSE, BEGIN/UNTIL/WHILE/REPEAT in assembly |
| 011 | Memory + arithmetic | @, !, c@, c!, +, -, *, AND, OR, XOR |
| 012 | Variables + strings | `variable`, `constant`, `."` strings, ct rework |
| 013 | File I/O | Open, read, close — load source from files |
| 014 | Return stack + cmove | `>r`, `r>`, `r@`, `zlen`, `cmove`, `fill`, `emit` |

**Status:** A working but primitive Forth. Everything is in assembly.
Flow control, comparisons, and stack ops are all runtime subroutines.
No backtick macros, no inline code generation, no SWAPbit integration.

---

## Phase 2: The SWAPbit Revolution (Experiments 015–020)

*2026-02-22 evening, continuing into late night (~19:22–21:56).
Six experiments in ~2.5 hours — the fastest phase, because the
pattern was established and each experiment followed the same
template: convert N primitives, update SWAPbit tables, test.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| 015 | SWAPbit infrastructure | s01/s08/s09 advance helpers, litcomma (`,` suffix) |
| 016–018 | *(inline conversion)* | 10 core primitives → inline macros, then 8 more |
| 019 | Inline comparisons | `=`, `<`, `>`, `0=`, `0<>` as SWAPbit-aware macros |
| 020 | FLAGS-based conditionals | CPU flags replace stack booleans — FreeForth's defining trait |

**Status:** The compiler now emits inline machine code instead of CALL
instructions for core words. `dup` compiles to 7 bytes of inline code,
not a 5-byte CALL. Conditionals use CPU FLAGS directly — no boolean on
the stack, no test instruction, no DROP. This is the point where ff64
stopped being "a Forth" and became "FreeForth."

---

## Phase 3: Forth-Defined Macros (Experiments 021–032)

*2026-02-23, midnight to evening (~00:30–18:09).  Twelve experiments
in ~18 hours.  This is where the assembly file starts shrinking and
ff64.boot starts growing — Lavarenne's design philosophy that most
things belong in the boot file, not the assembler.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| 021 | Trailing-comma literal compiler | `$DA89,` — emit literal bytes at compile time |
| 022 | Backtick name mangling | `: dup\`` compiles inline; `dup\`` compiles a CALL |
| 023 | Forth-defined code generators | dup, drop, over, nip, tuck — all in ff64.boot now |
| 024 | Store/return/rotation | `!`, `c!`, `>r`/`r>` as Forth macros, rot, -rot |
| 025 | Load variants + address ops | `w@`, `c@+`, `bounds`, `bswap` |
| 026 | lit\` and on\`/off\` | Push compile-time values; boolean variable helpers |
| 027 | c,\` w,\` ,\` | Compile-time memory emit macros |
| 028 | 2xchg\` 2r\` 3dup\` /% | Stack gymnastics and combined div/mod |
| 029 | place\`/cmove\` + shifts | String copy, 2\*, 2/, 4\*, 8\* — all Forth-defined |
| 030 | Extended arithmetic | m/mod, um/mod, m\*, \*/mod — 128-bit intermediates |
| 031 | Utility words | abs, min, max, negate — colon definitions |
| 032 | Flow control macros | BOOL\`, SKIP\`, ELSE\`, 0;\`, ;THEN\` |

**Status:** ~130 words ported. The assembly file is shrinking as
functionality migrates to ff64.boot. The backtick naming convention is
the bridge: assembly provides the primitives, Forth composes them.

---

## Phase 4: Dictionary and Compiler Infrastructure (Experiments 033–050)

*2026-02-23 evening through 2026-02-24 (~18:28–18:00, spanning
midnight).  Eighteen experiments in ~24 hours.  The self-modifying
tools: header access, suffix literals, compile-time stack, REPL —
the words that make words.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| 033 | Dictionary manipulation | h.ct, h.sz, h.nm, h.next, ct\|!, words |
| 034 | Execute/alias/constant | `execute`, `: alias`, `constant`, `[` `]` |
| 035 | Number output (PNO) | `.` with base variable — hex, decimal, binary |
| 036 | Flow control → Forth | **Major:** IF/THEN/ELSE/BEGIN etc. moved from asm to boot |
| 037 | TIMES/LOOP | Counted loops using return stack |
| 038 | ct=1 bugfix | Constants with value 9 corrupted compile-time stack |
| 039 | .s debug output | Stack display for debugging |
| 040 | Character literals | `'A` syntax |
| 041 | Vectors and tick | `!^`, `n^`, `'` — runtime code patching |
| 042 | Tail-call optimization | `;` emits JMP instead of CALL+RET when possible |
| 043 | Parser + system words | `parse`, `lnparse`, `catch`/`throw` |
| 044 | START/ENTER/BREAK/END | High-level loop constructs |
| 045 | create/variable/mark | `create`, `variable`, `mark`/`marker` |
| 046 | -call, tick, vectors | Uncall mechanism — the backtick macro engine |
| 047 | catch/throw, allot | Error recovery, memory allocation |
| 048 | Suffix mechanism | `foo@`, `foo!`, `8+`, `$FF&` — literal suffixes |
| 049 | hidepvt | Private words hidden after boot (name-zeroing) |
| 050 | Compile-time stack | cstack for forward references — robust flow control |

**Status:** 304 tests passing. The compiler is now self-aware: it can
create words, manage the dictionary, handle errors, and optimize its
own output. The suffix mechanism means `H@` "just works" without a
dedicated definition.

---

## Phase 5: Becoming Self-Hosting (Experiments 051–069)

*2026-02-24 evening through 2026-02-25 (~18:00–20:13).  Nineteen
experiments in ~26 hours.  The longest individual experiments live
here — file I/O (062), dynamic linking (068), and self-booting (069)
each required substantial assembly work.  Experiment 069 is the
watershed: ff64 boots from embedded source for the first time.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| 051 | REPL auto-execute | Top-level code runs automatically |
| 052 | Forth-based REPL | `_top` — the REPL loop in Forth, not assembly |
| 053 | Boot sequence | `_boot`, argc/argv, `_hidepvt` wired together |
| 054 | .s stack display | Debugging tool for interactive use |
| 055 | String comparison | `$-` and `!"..."` string literals |
| 056 | [IF] [ELSE] [THEN] | Conditional compilation within Forth |
| 057 | Dotted conditionals | `IF.`, `WHILE.` — stack-boolean flow control |
| 058 | Pictured numeric output | `<# # #s #>` — formatted number conversion |
| 059 | within, abs, max, min | Standard utility words |
| 059b | pick, 2over | Indexed stack access |
| 060 | RTIMES, dump | Counted loops variant, memory dump |
| 061 | ++\` and --\` | Peephole optimization — increment/decrement in place |
| 062 | File I/O (openr, close) | Read files from Forth |
| 064 | SEGV handler | Catch segfaults, print diagnostic, continue |
| 065 | needed/find | Load-once file inclusion |
| 066 | needs, -f, doargv | Command-line file loading |
| 067 | Help system | `help word` loads and searches ff64.help |
| 068 | Dynamic linking | #lib, #fun, #call — dlopen/dlsym from Forth |
| **069** | **Self-booting ff64** | **The binary boots from embedded source — no external files** |

**Status:** 414 tests. ff64 is self-hosting: the binary contains its
boot source, compiles it at startup, processes command-line arguments,
loads files, links shared libraries, and runs an interactive REPL.
This is the "it works" moment.

---

## Phase 6: Hardening (Experiments 070–077)

*2026-02-25 late night through 2026-02-26 (~23:52–15:03), with
exp 074 (OS separation) on 2026-02-26 and exp 077 (\_parse fix)
landing 2026-02-27.  Eight experiments over ~3 days.  Pace slows
here because bugs are harder — the \_parse fix (exp 077) was the
deepest bug in the port.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| 070 | TIMES...REPEAT fix | Auto-rdrop for counted loops |
| 071 | hidepvt compaction | True header removal with cmove\> (not just name-zeroing) |
| 072 | Features buffer | Runtime feature detection |
| 073 | Turnkey builder | fftk64 — build standalone executables from Forth |
| 074 | fflin64.boot | OS/architecture separation (Linux-specific code split out) |
| 075 | Recoverable SEGV | Continue after segfault instead of dying |
| 076 | Generic syscall | Arbitrary Linux syscalls from Forth |
| 077 | **\_parse fix** | **The deepest bug: every parse call leaked a stack item** |

**Status:** The \_parse bug (exp 077) had been present since the
beginning — every call to `parse` or `lnparse` consumed one extra
stack item, causing cumulative compile-time corruption. This was the
root cause of the "ELSE corruption bug" that had forced IF...;THEN
workarounds throughout ff64.boot.

---

## Phase 7: Libraries and Parity (Experiments 078–134)

*2026-02-27 through 2026-03-04 (~6 days).  The longest phase: 57
experiments spanning library infrastructure, assembly reduction,
cross-architecture unification, and boot file parity.  2026-02-28
alone saw 14 experiments (086–097) — an assembly-reduction blitz
that removed dozens of WORD64 entries.  2026-03-04 saw 12 experiments
(123–134) restoring fall-through chains and achieving conditional
parity with ff.boot.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| 078 | FFPATH | Search path for library loading |
| 079 | fixup (self-patching) | libc symbols resolved on first call |
| 080 | lib/64 library system | Shared libraries: pno, see64, console, debug |
| 081 | Full number parser | All FreeForth number syntax: $hex, %bin, grouping |
| 082 | Original literal notation | Restore Lavarenne's exact number format |
| 086 | PNO to library | Number output moved from boot to lib/ |
| 087 | FFHIDE + needed guard | Private word hiding + load-once guards |
| 088 | SEGV recovery fix | Robust signal handling |
| 089 | Anon block flush | variable/constant flush pending code |
| 090 | Remove keyword fast-paths | Compiler simplified — no special cases |
| 091 | Remove ct=2 entries | Inline words fully Forth-defined |
| 092–093 | Remove WORD64 entries | Assembly dictionary shrinks dramatically |
| 095 | Test framework | Structured test suite with PASS/FAIL reporting |
| 096 | Consolidated tests | test/ directory with permanent regression tests |
| 097 | Vector ops fixed | !^, n^ as backtick macros |
| 098–099 | see64.ff | Disassembler for generated code |
| 100 | WORD64 XT ordering | Header entries ordered by code address |
| 101 | nexth bug fix | Dictionary navigation corrected |
| 102 | s\>d fix | Sign extension code generation |
| 103 | see64 polish | TTY detection, register display |
| 104 | pick/2over/within fix | SWAPbit masking in pick detection |
| 105 | BEGIN/CASE/BREAK/END fix | Flow control unification |
| 106 | Static ELF64 | Pure FASM build — no linker, no libc |
| 107 | fflin64.asm wrapper | Static ff64s binary |
| 108–110 | Syscall migration | Assembly syscalls → Forth library |
| 112 | File test words | stat/lstat from Forth |
| 113 | Assembly reduction | Remove dead assembly code |
| 114 | Vectors → backtick macros | nop emits 0x90 |
| 115 | common1.ff + cell/[64] | Cross-architecture shared code begins |
| 116 | **n\^ fix — -f works** | **Vector nullify bug killed doargv since day 1** |
| 117–122 | Library unification | Shared lib/ tree for both architectures |
| 123 | cell constant bug fix | Backtick constant compilation |
| 124 | compat.ff | Pure-Forth compatibility layer |
| 125–128 | Fall-through restoration | Restore Lavarenne's fall-through chains |
| 129 | [~]\` | Conditional compilation: test word existence |
| 130 | Conditional parity | ff64.boot matches ff.boot's conditional blocks |
| 131 | Eliminate redefinitions | Clean boot with no re-`:` of existing words |
| 132 | Naming conflicts resolved | Boot vs library name collisions fixed |
| 133 | Help file audit | ff64.help load hints standardized |
| 134 | Native getenv | envp walking without libc |

**Status:** The n\^ bug (exp 116) is the cautionary tale: it had been
present since the port began, silently killing `_postboot`. Every test
that used `-f` was testing nothing — `doargv` never fired. Dozens of
experiments piped stdin as a workaround. One line fixed n\^, unlocking
argv, -f, and `make test64`.

---

## Phase 8: Deep Debugging (Experiments 135–145)

*2026-03-05 through 2026-03-06 (~2 days).  The pace is 5–6
experiments per day, but each one is harder.  The loop+conditional
audit (exp 135) alone produced 84 tests.  Experiments 136–138
fixed three interrelated flow-control bugs that had been masked by
simpler test cases.  The \_loadfile removal (exp 141) deleted 107
lines of assembly, replaced by pure Forth matching i386.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| 135 | Loop+conditional audit | 84 tests probing every loop/conditional combo |
| 136 | IF AGAIN fix | Compile-time data stack corruption in conditional restart |
| 137 | REPEAT fix | BEGIN...IF BREAK...REPEAT (no WHILE) |
| 138 | TIMES+WHILE fix | Multiple WHILE via recursive \_resolve\_fwds |
| 139 | eval file-loading proof | Confirm i386 eval-based loading works on ff64 |
| 140 | tib/eob unification | Single buffer pair for source and terminal |
| 141 | Remove \_loadfile | Adopt i386's pure-Forth `needed` — 107 lines of asm deleted |
| 142 | BSS section + CS0/getenv | Uninitialized buffers save 64KB on disk; env access |
| 143 | openlib/ffpath/needed port | Verbatim port of i386 library search |
| 144 | Native libc replacements | strlen/memset/memcpy without libc |
| 145 | Shared mmap + boot syscalls | Cross-platform memory mapping |
| 145b | Static turnkey + BSS opt | fftk64s builder, BSS for large buffers |

**Status:** File loading now matches i386 exactly — pure Forth, no
assembly \_loadfile. The BSS section reduced the binary from ~168KB
to ~100KB. The system is robust enough to run real programs.

---

## Phase 9: Real Programs (Experiments 146–150)

*2026-03-07.  Five experiments in one day.  The w! bug fix (exp 146)
was the last wall before `hanoi` ran — a 16-bit store encoding error
that had been present since exp 024.  Test consolidation (exp 150)
unified i386 and ff64 tests under `make testall`.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| **146** | **w! bug — hanoi runs** | **The last wall: 16-bit store encoding was wrong** |
| 147 | see.ff opcode gaps | Disassembler handles $66 prefix, more opcodes |
| 148 | Bug triage | Quick fixes for accumulated minor issues |
| 149 | shell.ff + mmap fixes | Cross-platform shell commands and memory mapping |
| 150 | Test consolidation | Unified test/ directory, `make testall` |

**Status:** `hanoi` (Towers of Hanoi) runs correctly — the first
non-trivial demo program to work end-to-end on ff64. The test suite
is consolidated: `make testall` runs i386 tests, ff64 tests, and all
experiments in one command.

---

## Phase 10: Infrastructure (Experiments 146–148, second series)

*2026-03-08 through 2026-03-11 (~4 days).  The experiment numbers
were reused after the test consolidation renumbered things.  FFPATH
redesign took two experiments (146–147) over 2026-03-08.  The ffpp
preprocessor (exp 148) spanned 2026-03-09 through 2026-03-11,
evolving from a Perl replacement to a conditional-compilation engine.*

| Exp | Milestone | What it unlocked |
|-----|-----------|-----------------|
| 146 | FFPATH redesign | Lua-inspired template search path |
| 147 | FFPATH tib-based | No scratch buffers — builds paths in tib |
| 148 | ffpp preprocessor | x86-64 assembly preprocessor: comments, whitespace, includes, conditionals |

**Status:** ffpp replaces the Perl minifier with a native x86-64
binary (~10KB). It strips comments, collapses whitespace, handles
recursive includes (^V sigil), and provides `[64]`/`[32]`/`[0]`/`[1]`
with `[IF]`/`[ELSE]`/`[THEN]` for conditional compilation — enabling
unified boot files that serve both architectures from a single source.

---

## Current State

| Metric | Value |
|--------|-------|
| ff64.asm | 2,179 lines |
| ff64.boot | 803 lines |
| fflin64.boot | 197 lines |
| Assembly primitives | ~65 WORD64 entries |
| Forth-defined words | ~400+ |
| Test suite | 120 tests (make testall) |
| Binary size | ~100KB (static ELF64, no libc) |
| Known compiler bugs | 2 (IF AGAIN, rdrop ;THEN) |

### What the i386 has that ff64 doesn't yet

- Lavarenne's compacting hidepvt (ff.boot) — ff64 has a cmove\>-based
  reimplementation and an unconnected port of the original (xhidepvt)
- Some ff.ff library code not yet ported
- Networking (lib/x86-64/net.ff is new to ff64, not yet mature)
- FPU words

### The hidepvt question

Experiment 071 built a cmove\>-based hidepvt because the simpler
bulk-copy approach was easier to get right than Lavarenne's original
two-pass collect-and-pack algorithm (ff.boot:285).  The Lavarenne
original uses START/ENTER loops with `c@+`/`dupc@` byte-copy loops
and careful stack choreography — all of which existed by exp 071, but
the cmove\> approach required less debugging.  `_postboot` still calls
the cmove\>-based `_hidepvt`.
