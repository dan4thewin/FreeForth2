# Experiment 152: 3-byte SWAPbit adjusters for x86-64

## Background

The SWAPbit adjusters `s01`, `s08`, `s09` advance rbp by 2 and XOR
the ModR/M byte with the appropriate SC bits. This matches i386
register-register instructions, which are exactly 2 bytes (opcode +
ModR/M).

In x86-64, the REX.W prefix adds a third byte, making
register-register ops 3 bytes (REX + opcode + ModR/M). Every x86-64
backtick macro must split the REX prefix into a separate litcomma:

    : 1-` $48, ,1 $CBFF, s01 ;

The i386 equivalent is simply:

    : 1-` $4B, s1 ;

### The double-adjuster trick (i386 only)

In i386, two 2-byte instructions pack into one 4-byte litcomma with
two s-adjusters walking through them:

    : <<` $E2D3D989, s08 s01 drop` ;
    \     89D9(mov ecx,ebx) D3E2(shl edx,cl)
    \     s08 XORs byte 1 (D9, MOV's ModR/M)
    \     s01 XORs byte 3 (E2, SHL's ModR/M)

The x86-64 version needs four litcomma calls:

    : <<` $48, ,1 $D989, s08 $48, ,1 $E2D3, s01 drop` ;

## Proposal

Define 3-byte-stride adjusters, trivially composed from existing words:

    : s01. ,1 s01 ;  \ advance 3, XOR bit 0 of ModR/M
    : s08. ,1 s08 ;  \ advance 3, XOR bit 3 of ModR/M
    : s09. ,1 s09 ;  \ advance 3, XOR bits 0+3 of ModR/M

The `,1` advances past the REX byte; `s01`/`s08`/`s09` then operates
on the remaining 2-byte opcode+ModR/M pair as usual.

### Before/after examples

Stack macros:
    \ under` -- before
    : under` $F87F8D4D, ,4 $49, ,1 $1789, s08 ;
    \ under` -- after (r15 instructions unchanged, only the s08 pair)
    : under` $F87F8D4D, ,4 $178949, s08. ;

    \ nip` -- before
    : nip` $49, ,1 $178B, s08 $087F8D4D, ,4 ;
    \ nip` -- after
    : nip` $178B49, s08. $087F8D4D, ,4 ;

Unary ops:
    \ before                          after
    : 1-` $48, ,1 $CBFF, s01 ;       : 1-` $CBFF48, s01. ;
    : 1+` $48, ,1 $C3FF, s01 ;       : 1+` $C3FF48, s01. ;
    : 2*` $48, ,1 $E3D1, s01 ;       : 2*` $E3D148, s01. ;
    : 2/` $48, ,1 $FBD1, s01 ;       : 2/` $FBD148, s01. ;

Binary ops:
    \ before                              after
    : over&` ext $D321, s09 ;            : over&` $D32148, s09. ;
    : over+` ext $D301, s09 ;            : over+` $D30148, s09. ;
    : @`  ext $1B8B, s09 ;               : @`  $1B8B48, s09. ;
    : 2dup!` ext $1389, s09 ;            : 2dup!` $138948, s09. ;

Shifts (double-adjuster trick restored):
    \ before (4 litcomma calls)
    : <<` $48, ,1 $D989, s08 $48, ,1 $E2D3, s01 drop` ;
    \ after (2 litcomma calls)
    : <<` $D98948, s08. $E2D348, s01. drop` ;

Other multi-byte macros:
    \ allot` -- before
    : allot` $48, ,1 $DD01, s08 drop` ;
    \ allot` -- after
    : allot` $DD0148, s08. drop` ;

    \ rdrop` -- before
    : rdrop` $48, ,1 $C483, ,2 $08, ,1 ;
    \ rdrop` -- after (not applicable -- C483 has no SWAPbit, just ,2)

### What stays the same

- i386 code is unchanged (still uses 2-byte s01/s08/s09)
- Instructions without REX prefix still use the 2-byte adjusters
  (e.g., flip`, 2dupc!`, w@`, 0-` in i386 section)
- Instructions with fixed registers (/%`, place`) use >S0 and
  bundle freely -- no s-adjusters needed
- The 2-byte s01/s08/s09 remain for i386 and non-REX x86-64 use

### Scope

- Define s01./s08./s09. (3 one-line definitions in the [64] section)
- Convert x86-64 backtick macros to use them
- Verify binary identity (comment-level change in terms of output)
- Count: roughly 30 macros would benefit

### Risk

Low. The new words compose existing primitives. The generated machine
code is identical -- only the compile-time path changes (fewer
litcomma calls, same bytes emitted). Verified by md5sum of ff64.

### Notes

- The `ext` abstraction (`;` on i386, `$48, ,1` on x86-64) would
  be partially superseded for macros that use s-adjusters. `ext`
  remains useful for macros that follow the REX with a `,N` rather
  than an s-adjuster (e.g., rdrop`, which uses `,2` not s-anything).
- Naming: the `.` suffix mirrors Lavarenne's dotted convention
  (IF./WHILE. etc.) meaning "extended variant." Open to alternatives
  (s03, s018, s038, s039, etc.).
