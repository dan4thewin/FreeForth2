> [!NOTE]
> This page preserves the writings of Christophe Lavarenne (1956-2011) about FreeForth.

\[[FreeForth Home Page](FreeForth.md)\] \[[FreeForth Primer](FreeForth_Primer.md)\]

# FreeForth Code Generation

FreeForth generates compact and fast i386 native code, as shown in the following example of an iterative
(i.e. non-recursive) implementation of the factorial function:

                \ cSP = call Stack Pointer (normal = esp, alternate = eax)
                \ dSP = data Stack Pointer (normal = eax, alternate = esp)
                \ TOS = Top  Of DATAstack  (normal = ebx, alternate = edx)
                \ NOS = Next Of DATAstack  (normal = edx, alternate = ebx)
                \                                     esp eax ebx edx
    : factorial \ n -- n! ;                           cSP dSP TOS NOS  initial=normal
      1         \           0: 94       xchg eax,esp; dSP cSP
                \           1: 52       push edx;             NOS TOS  under swap
                \           2: 6A 01    push 1;        (push 1; pop edx; takes 3 bytes)
                \ n 1     ; 4: 5A       pop  edx;      (mov edx,1; would take 5 bytes)
      BEGIN     \ i f     ; 5: 90 90 90 nop; nop; nop; (loop aligned on multiple of 4)
        over*   \ i f*i   ; 8: 0F AF D3 imul edx,ebx;
        swap    \ f*i i   ;                                   TOS NOS  renaming
        1-      \ f*i i-1 ; B: 4B       dec  ebx;      (modifies i386 flags)
        swap    \ i-1 f*i ;                                   NOS TOS  renaming
      0= UNTIL  \ 0   n!  ; C: 75 FA    jnz  8;        (no drop)
      nip       \ n!      ; E: 5B       pop  ebx;
    ;           \           F: 87 DA    xchg ebx,edx;         TOS NOS  final=normal
                \          11: 94       xchg eax,esp; cSP dSP          final=normal
                \          12: C3       ret

To push the literal `1` onto the DATAstack, the initial single byte instruction `[0:94 xchg eax,esp]` first allows
to use short push/pop instructions to access the DATAstack within the definition body, then `[1:52 push edx]`
saves NOS into memory (as does `under`), then we exchange the roles of `ebx` and `edx` (as does `swap`), then we
can load the constant `1` into `TOS=edx`.

The `BEGIN` generates 3 `nop` to align the loop start address on a multiple of 4 bytes: this will reduce the number
of clock cycles for the loop conditional jump `[C:75,FA jnz 8]`.  
The `over*` macro generates the push-pop-less single instruction `[8:OF,AF,D3 imul edx,ebx]`.  
The two `swap` generate no code, they only exchange the roles of `ebx` and `edx` at compile time, then the sequence
`swap 1- swap` compiles the single instruction `[B:4B dec ebx]`.  
FreeForth conditional jumps don't modify the DATAstack, they only test the i386 flags modified by the last arithmetic
or logic instruction; then the `0= UNTIL` generates the single instruction `[C:75,FA jnz 8]`.

The following `nip` generates a `pop NOS`, i.e. here `[E:5B pop ebx]`.  
The final `;` must restore the normal registers before compiling the final `[12:C3 ret]`:  
the `[F:87,DA xchg ebx,edx]` restores the normal use of `ebx=TOS` and `edx=NOS`, and the `[11:94 xchg eax,esp]`
restores the normal use of `esp=cSP` and `eax=dSP`.

This makes a total of 19 bytes, of which 6 for 3 assembly instructions in the loop. For a compiler, as simple as
FreeForth is, this is not too bad.

If you need the best performance from your x86, and can write a smaller and faster definition in direct assembler,
use fasm to obtain the binary code, then embed it in FreeForth inline strings (note `^` subtracts 64 from the next
ASCII, and `~` adds 128 to the previous ASCII):

    : factorial  \ n -- n!
      ,"^I~Y~"      \ 0: 89 D9           mov ecx,ebx
      ,";~^A^@^@^@" \ 2: BB 01 00 00 00  mov ebx,1
      ,"^P~"        \ 7: 90              nop ; align loop on multiple of 4
      ,"^O/~Y~"     \ 8: 0F AF D9        imul ebx,ecx
      ,"b~{~"       \ B: E2 FB           loop 8
    ;               \ D: C3              ret

This takes 14 bytes, of which 5 for 2 instructions in the loop: that's indeed better.

If you want the very best performance from your x86, and accept to trade space for speed, to save the `call` and
`ret` instructions execution time, you can alternatively define factorial as a macro (i.e. executed at compile
time and generating inline code) using inlining literals, but remember the i386 is little-endian, i.e. the least
significant byte of an inlining literal will be at the smallest address:

    : factorial`  \ n -- n! ; inlines 12 bytes
      \ 89D9(mov ecx,ebx)BB.01000000(mov ebx,1)0FAFD9(imul ebx,ecx)E2FB(loop -5)
      $BBD989, s08 s1  1, ,4  align`  $D9AF0F, ,1 s08  $FBE2, ,2
    ;

The inlining literal `$BBD989,` compiles code which, when `` factorial` `` is executed (as `` factorial` `` is a
macro, this will usually be at compile time), will store at the address in `ebp` (the compilation pointer) the 4
bytes `[+0:89,D9,BB,00]`;  
then `s08` will add 2 to `ebp` and, if using alternate `TOS=edx`, will `xor` with 8 the last byte `[+2-1:D9]`
to change the `89D9(mov ecx,ebx)` into `89D1(mov ecx,edx)`;  
then `s1` will add 1 to `ebp` and, if using alternate `TOS=edx`, will `xor` with 1 the last byte `[+3-1:BB]`
to change the `BB.01000000(mov ebx,1)` into `BA.01000000(mov edx,1)`;  
then `1,` will overwrite the last stored `[+3:00]` with the 4 bytes `[+3:01,00,00,00]` and `,4` will add 4 to `ebp`;  
then `` align` `` will store at `ebp` 4 `nop` instructions `[+7:90,90,90,90]`, and align `ebp` on a multiple of 4;  
then `$D9AF0F,` will overwrite some of the 4 nop instructions with the 4 bytes `[+8:0F,AF,D9,00]` and `,1` will
add 1 to `ebp`;  
then `s08`, as previously, will add 2 to `ebp` and, if using alternate `TOS=edx`, will `xor` with 8 the last byte
`[+11-1:D9]` to change the `0FAFD9(imul ebx,ecx)` into `0FAFD1(imul edx,ecx)`;  
then finally `$FBE2, ,2` will overwrite the last stored `[+11:00]` with the 4 bytes `[+11:E2,FB,00,00]` and add 2 to
`ebp`, leaving it pointing at the two last stored `[+13:00,00]`, reading for compiling code following factorial.

Then, in any of the 3 cases, you can use FreeForth interactivity to test your code: _isn't it cool?_

    5 factorial . ;  \ this is your command (an "anonymous" definition)
    120  0;          \ this is the result of "." followed by FreeForth prompt
    6 factorial . ;
    720  0;

- - -

[CL](http://christophe.lavarenne.free.fr/index.html)090903
