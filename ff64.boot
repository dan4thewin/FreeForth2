( ff64.boot — FreeForth2 x86-64 boot source )
( Provides standard Forth words using ff64 built-in primitives )

( Inline code generators — Forth-defined macros using litcomma )
( The compiler's backtick name mangling finds these when the user )
( writes "dup", "drop", etc. during compilation. )
(                                                               )
( x86-64 opcodes [REX.W = $48]:                                )
(   lea r15,[r15-8]  = 4D 8D 7F F8  push-NOS: allocate slot    )
(   lea r15,[r15+8]  = 4D 8D 7F 08  pop-NOS: release slot      )
(   mov [r15],rdx    = 49 89 17     store NOS to data stack     )
(   mov rdx,[r15]    = 49 8B 17     load NOS from data stack    )
(   mov rdx,rbx      = 48 89 DA     copy TOS to NOS            )

\ Core stack macros (swap` is an assembly primitive)
: under` $F87F8D4D, ,4 $49, ,1 $1789, s08 ;
: nip` $49, ,1 $178B, s08 $087F8D4D, ,4 ;
: drop` swap` nip` ;
( dup` falls through to nipdup` — Lavarenne's key insight: )
( dup = allocate NOS slot + store TOS there + copy TOS to NOS )
( The "copy TOS to NOS" part IS nipdup, so dup shares its code. )
: dup` under`
: nipdup` $48, ,1 $DA89, s09 ;
: over` under` swap` ;
: tuck` swap` over` ;

\ Binary arithmetic — "over" variants preserve NOS
: over+` $48, ,1 $D301, s09 ;
: over-` $48, ,1 $D329, s09 ;
: over&` $48, ,1 $D321, s09 ;
: over|` $48, ,1 $D309, s09 ;
: over^` $48, ,1 $D331, s09 ;
: over*` $48, ,1 $0F, ,1 $DAAF, s09 ;
\ Consuming binary ops
: +` over+` nip` ;
: -` swap` over-` nip` ;
: *` over*` nip` ;
: &` over&` nip` ;
: |` over|` nip` ;
: ^` over^` nip` ;

\ Division — >S0 forces rbx=TOS, rdx=NOS before hardcoded register ops
\ /%` ( a b -- a%b a/b ): mov rax,rdx; cqo; idiv rbx; mov rbx,rax
: /%` >S0 $48D08948, ,4 $FBF74899, ,4 $C38948, ,3 ;
: /` /%` nip` ;
: %` /%` drop` ;

\ w,` ( n -- ): store 16-bit word at [rbp], advance rbp by 2
\ Needed early: _m/mod and _m* use w, before the compilation-emit section
: w,` $66, ,1 $5D89, s08 $00, ,1 $02C58348, ,4 drop` ;

\ Extended arithmetic helpers — parameterized via w, for the mul/div opcode
: _m/mod >S0 $078B49, ,3 $08C78349, ,4 $48, ,1 w, $C38948, ,3 ;
: m/mod` $FBF7 _m/mod ;
: um/mod` $F3F7 _m/mod ;
: _m* >S0 $D08948, ,3 $48, ,1 w, $D38948, ,3 $C28948, ,3 ;
: m*` $EBF7 _m* ;
: um*` $E3F7 _m* ;

\ Unary ops
: negate` $48, ,1 $DBF7, s01 ;
: ~` $48, ,1 $D3F7, s01 ;
: 1+` $48, ,1 $C3FF, s01 ;
: 1-` $48, ,1 $CBFF, s01 ;
: 2+` 1+` 1+` ;
: 4+` $48, ,1 $C383, s01 $04, ,1 ;
: 2*` $48, ,1 $E3D1, s01 ;
: 2/` $48, ,1 $FBD1, s01 ;
: 4*` $48, ,1 $E3C1, s01 $02, ,1 ;
: 4/` $48, ,1 $FBC1, s01 $02, ,1 ;
: 8*` $48, ,1 $E3C1, s01 $03, ,1 ;
: 8/` $48, ,1 $FBC1, s01 $03, ,1 ;
: bswap` $48, ,1 $CB0F, s01 ;
: flip` $FB86, s09 ;
: 8+` $48, ,1 $C383, s01 $08, ,1 ;
: 8-` $48, ,1 $EB83, s01 $08, ,1 ;
: <<` $48, ,1 $D989, s08 $48, ,1 $E2D3, s01 drop` ;
: >>` $48, ,1 $D989, s08 $48, ,1 $EAD3, s01 drop` ;

\ Memory load
: @` $48, ,1 $1B8B, s09 ;
: c@` $48, ,1 $0F, ,1 $1BB6, s09 ;
: cs@` $48, ,1 $0F, ,1 $1BBE, s09 ;
: w@` $0F, ,1 $1BB7, s09 ;
: ws@` $48, ,1 $0F, ,1 $1BBF, s09 ;
\ Fetch preserving address: dup@` = over` + fetch through NOS
: dup@`  over` $48, ,1 $1A8B, s09 ;
: dupc@` over` $48, ,1 $0F, ,1 $1AB6, s09 ;
: dupw@` over` $0F, ,1 $1AB7, s09 ;

\ Memory store (2dup variants preserve both operands)
( 2dupw!` falls through to 2dup!` — the $66 prefix makes the mov 16-bit, )
( then the mov [rdx],rbx body is shared with 2dup!`. )
: 2dupw!` $66, ,1
: 2dup!` $48, ,1 $1389, s09 ;
: 2dupc!` $1388, s09 ;
: 2dup+!` $48, ,1 $1301, s09 ;
: 2dup-!` $48, ,1 $1329, s09 ;
\ Consuming store ops — Lavarenne's fall-through triads:
\ over!` falls through to tuck!` (just adds swap` prefix)
\ tuck!` falls through to !` (emits 2dup! + nip + drop in layers)
: over!`  swap` : tuck!`  2dup!`  nip` ; : !`  tuck!`  drop` ;
: overc!` swap` : tuckc!` 2dupc!` nip` ; : c!` tuckc!` drop` ;
: overw!` swap` : tuckw!` 2dupw!` nip` ; : w!` tuckw!` drop` ;
: over+!` swap` : tuck+!` 2dup+!` nip` ; : +!` tuck+!` drop` ;
: over-!` swap` : tuck-!` 2dup-!` nip` ; : -!` tuck-!` drop` ;

\ 32-bit (dword) store — for patching jump offsets
: 2dupd!` $1389, s09 ;
: tuckd!` 2dupd!` nip` ;
: d!` tuckd!` drop` ;

\ Return stack inline macros
: dup>r` $53, s1 ;
: r>` over`
: dropr>` $5B, s1 ;
: >r` dup>r` drop` ;
: rdrop` $48, ,1 $C483, ,2 $08, ,1 ;
: 2rdrop` $48, ,1 $C483, ,2 $10, ,1 ;
\ r@ inline: mov rbx,[rsp] = 48 8B 1C 24
\ 2r@ inline: read [rsp+8] then fall through to r`
: 2r` over` $48, ,1 $5C8B, s08 $24, ,1 $08, ,1
: r` over` $48, ,1 $1C8B, s08 $24, ,1 ;

\ Rotation via xchg [r15],reg
: -rot` swap`
: >rswapr>` $49, ,1 $1787, s08 ;
: rot` >rswapr>` swap` ;
: 2xchg` swap` >rswapr>` swap` ;

\ Compilation helpers
: here` over` $48, ,1 $EB89, s01 ;
: allot` $48, ,1 $DD01, s08 drop` ;

\ Compilation emit: store value at [rbp] and advance rbp
\ c,` ( n -- ): store byte, advance 1
: c,` $5D88, s08 $00, ,1 $C5FF48, ,3 drop` ;
\ ,` ( n -- ): store 64-bit cell, advance 8
: ,` $48, ,1 $5D89, s08 $00, ,1 $086D8D48, ,4 drop` ;
\ d,` ( n -- ): store 32-bit dword, advance 4
: d,` $5D89, s08 $00, ,1 $04C58348, ,4 drop` ;

\ Composed operations
: 2dup` over` over` ;
: 3dup` 2dup` $F87F8D4D, ,4 $18478B49, ,4 $078949, ,3 ;
: 2dup+` over` over+` ;
: 2r>` 2dup` dropr>` swap` dropr>` swap` ;
: 2dup>r` swap` dup>r` swap` dup>r` ;
( 2>r` falls through to 2drop` — push both then discard both. )
: 2>r` 2dup>r`
: 2drop` drop` drop` ;

\ Fetch and advance (address on stack, returns value and advanced addr)
: @+`  dup@`  swap` 8+` swap` ;
: c@+` dupc@` swap` 1+` swap` ;
: w@+` dupw@` swap` 2+` swap` ;

\ Double-cell fetch/store
: 2@` @+` swap` @` swap` ;
: 2!` tuck!` 8+` !` ;

\ Address arithmetic
: bounds` over+` swap` ;

\ String/memory copy (rep movsb)
\ place` ( src count dest -- dest ): >S0 forces rbx=dest, rdx=count
: place` >S0
    $DF8948, ,3 $D18948, ,3 $378B49, ,3
    $08578B49, ,4 $10C78349, ,4 $A4F3, ,2 ;
: cmove` swap` place` drop` ;

\ Compile literal: lit` takes value from TOS, emits push code
\ off`/on` use lit` to compile 0/-1 then store
: off` 0 lit` swap` !` ;
: on` -1 lit` swap` !` ;

\ Extended scale ops (need >r`/r>` defined above)
: */mod` >r` m*` r>` m/mod` ;
: */` */mod` nip` ;

: (` ')' parse 2drop ;

( Private word infrastructure — Lavarenne's 3-way fall-through chain: )
( :.` starts a named def and falls through to pvt` which falls through )
( to ct|! — three operations composed without any call/ret overhead. )
: :.` :`
: pvt` 8 H@
: ct|! 8+ dupc@ rot | swap c! ;

( Dictionary defining words )
: create` :` 1 H@ ct|! anon:` ;
: variable` create` 0 , anon:` ;
( alias` falls through to _alias — :` creates the header, )
( then _alias stores the value, sets the constant flag, and closes. )
: alias` :`
: _alias H@ ! $20 H@ ct|! anon:` ;
( constant` reuses _alias: create` makes a ct=1 header, then _alias )
( overwrites the xt with the value and adds the $20 alias flag. )
: constant` create` _alias ;

( FLAGS-based conditionals — from ff.boot )
( 0-` emits test TOS,TOS. i386: 09 DB [or ebx,ebx]. x64: 48 85 DB )
( [test rbx,rbx] with REX.W prefix. SWAPbit via s09 handles register )
( alternation — the actual register tested depends on current SB state. )
: 0-` $48, ,1 $DB85, s09 ;
( _?1 stores a Jcc opcode byte in the ?# variable. When IF`/WHILE`/etc )
( later read ?#, they emit a conditional jump using this opcode. )
:. _?1 ?# c! ;
( Dotted condition factories — _?1./_?2. produce a Forth boolean [-1/0] )
( directly in a register, instead of setting ?#. Used by 0=.` <.` etc. )
( _?1a.: xor ecx,ecx — zero rcx [32-bit xor zero-extends on x86-64] )
:. _?1a. $C931, ,2 ;
( _?1b.: emit SETcc cl / dec rcx / mov rbx,rcx [with SWAPbit] )
( 1^ inverts Jcc; $20+ converts Jcc [$7x] to SETcc [$9x]; 8<< positions )
( in dword. i386 uses $49 [single-byte dec ecx]; x64 needs $48 FF C9 )
( [REX.W dec rcx]. i386 emits dword with , [cell=4]; ff64 uses )
( here d! 4 allot because , stores 8 bytes [cell=8] on x86-64. )
:. _?1b. 1^ $20+ 8 << $48C1000F | here d! 4 allot $C9FF, ,2 $48, ,1 $CB89, ,1 s1 ;
( _?1.: unary dotted — xor ecx, test TOS, SETcc+dec+mov )
:. _?1. _?1a. 0-` _?1b. ;
( _?2: binary condition — store Jcc + emit cmp rdx,rbx )
( i386: $DA39, — 39 DA [cmp edx,ebx]. x64: 48 39 DA with REX.W. )
:. _?2 _?1 $48, ,1 $DA39, s09 ;
( _?2.: binary dotted — xor ecx, cmp, SETcc+dec+mov, nip )
:. _?2. _?1a. $48, ,1 $DA39, s09 _?1b. nip` ;
( Condition code factory: each line defines up to 4 words from one Jcc )
( opcode. dup shares the opcode between consecutive definitions. )
( The ; after each definition executes the anonymous body, consuming )
( one copy of the opcode — so each dup feeds exactly two definitions. )
$74 dup : 0=`  lit _?1 ; dup : 0=.`  lit _?1. ; dup : =`  lit _?2 ; : =.`  lit _?2. ;
$75 dup : 0<>` lit _?1 ; dup : 0<>.` lit _?1. ; dup : <>` lit _?2 ; : <>.` lit _?2. ;
$7C dup : 0<`  lit _?1 ; dup : 0<.`  lit _?1. ; dup : <`  lit _?2 ; : <.`  lit _?2. ;
$7D dup : 0>=` lit _?1 ; dup : 0>=.` lit _?1. ; dup : >=` lit _?2 ; : >=.` lit _?2. ;
$7E dup : 0<=` lit _?1 ; dup : 0<=.` lit _?1. ; dup : <=` lit _?2 ; : <=.` lit _?2. ;
$7F dup : 0>`  lit _?1 ; dup : 0>.`  lit _?1. ; dup : >`  lit _?2 ; : >.`  lit _?2. ;
( Carry flag + unsigned: C1?/C0? are on separate lines from u</u>= )
( because they use _?1 [unary] while u</u>= use _?2 [binary]. )
$72 dup : C1?` lit _?1 ; : C1?.` lit _?1. ;
$73 dup : C0?` lit _?1 ; : C0?.` lit _?1. ;
$72 dup : u<`  lit _?2 ; : u<.`  lit _?2. ;
$73 dup : u>=` lit _?2 ; : u>=.` lit _?2. ;
$76 dup : u<=` lit _?2 ; : u<=.` lit _?2. ;
$77 dup : u>`  lit _?2 ; : u>.`  lit _?2. ;

( Flow control — Forth-defined )
: d, here d! 4 allot ;
: _then here over - 4 - swap d! ;
( ?@: fetch ?# and zero it. ?#! is a cell store — cond_jmp is dq in asm )
( to make this safe. Matches i386 ff.boot exactly. )
( ?nn: validate a condition was set — errors if ?# was empty. The )
( ,"t^AC~" is a string escape that compiles to throw-string bytes. )
:. ?@ ?# c@ 0 ?#! ;
:. ?nn 0- ,"t^AC~" !"is_not_preceded_by_a_condition"
( cond: read the condition opcode from ?#, validate, invert bit 0. )
( The 1^ inversion is because IF/WHILE/UNTIL all jump on the OPPOSITE )
( condition — IF skips the body when the condition is FALSE. )
: cond ?@ ?nn 1^ ;
( cond.: convert a stack boolean to FLAGS for dotted flow control. )
( Emits 0- [test TOS], drop [consume it], 0<> [set Jcc for nonzero]. )
( Falls through to IF.` which falls through to IF`, matching i386. )
: cond. 0-` drop` 0<>` ;
: IF.` cond.
: IF` >S0 cond $0F c, $10+ c, here 4 allot ;
: THEN` >S0 here over - 4- swap d! 0 callmark! ;
: _emit_rdrop $48 c, $83 c, $C4 c, $08 c, ;

( Flow control macros — composable backtick versions )
: SKIP` >S0 $E9, ,1 here 4 allot ;
: ELSE` SKIP` swap THEN` ;
( ;;` with tail-call optimization: if last emitted instruction was a CALL, )
( convert it to JMP [change E8 opcode to E9]. Otherwise emit RET. )
: ;;` >S0 callmark@ here - 0= drop IF $E9 callmark@ 5- c! ELSE $C3, ,1 THEN ;
( 0;` falls through to ;THEN` — Lavarenne's fall-through pattern. )
( 0;` emits: test-zero, conditional-jump, drop. If TOS was nonzero, )
( execution continues past ;THEN. If zero, ;THEN emits RET and )
( resolves the forward jump from IF`. )
: 0;` 0-` 0=` IF` drop`
: ;THEN` ;;` THEN` ;
: 0<>;` 0-` 0<>` IF` drop` ;THEN` ;
: ?dup` 0-` 0<>` IF` dup` THEN` ;
: BOOL` 0 lit` IF` ~` THEN` ;
: CASE` =` drop` IF` drop` ;

( Loop infrastructure: mrk, cstack, START/ENTER/BREAK/END )
\ mrk is a 2-cell compiler variable:
\   cell 0: loop body address (backward jump target for AGAIN/UNTIL etc.)
\   cell 1: reserved
\ All loop openers (BEGIN, START, TIMES/RTIMES) save old mrk to cstack,
\ push a 0 break-sentinel, and set mrk[0] = loop body address.
\ All loop closers resolve breaks from cstack and restore mrk.
\
\ Data stack layout from loop openers:
\   BEGIN:  ( -- 0 )     flag=0 means no rdrop needed
\   RTIMES: ( -- -1 js ) flag=-1 triggers rdrop in REPEAT; js=fixup
\
\ END does NOT emit a backward jump — it only resolves forward refs
\ (WHILE/BREAK). Use AGAIN/UNTIL/REPEAT for backward jumps.
\ Pattern: BEGIN ... CASE ... BREAK ... END (multi-way dispatch)
\
\ >cs ( x -- ) pushes to compile-time stack
\ cs> ( -- x ) pops from compile-time stack
variable mrk 0 mrk 8+ !
: align` $90909090, here negate 3& allot ;
:. _begin mrk 2@ >cs >cs 0 >cs here mrk! ;
:. _jmpback_mrk >S0 $E9 c, mrk@ here 4+ - d, ;
:. _cjmpback_mrk >S0 cond $0F c, $10+ c, mrk@ here 4+ - d, ;
:. _resolve_breaks cs> 0; _then _resolve_breaks ;
:. _end_cs _resolve_breaks cs> cs> mrk 2! ;
: START` _begin 0 $E9 c, 0 d, here mrk! ;
: ENTER` >S0 mrk@ 4- _then ;
: BEGIN` >S0 _begin 0 ;
: AGAIN` _jmpback_mrk 0- 0<> IF THEN` ELSE _end_cs drop THEN ;
: TILL.` cond.
: TILL` >S0 cond $0F c, $10+ c, mrk@ here 4+ - d, ;
: UNTIL.` cond.
: UNTIL` _cjmpback_mrk _end_cs drop ;
: WHILE.` cond.
: WHILE` IF` ;
: BREAK` >S0 $E9 c, 0 d, here 4- >cs _then ;
: END` >S0 _end_cs drop ;
:. _resolve_fwds 0- 0> IF THEN` _resolve_fwds THEN ;
: REPEAT` _jmpback_mrk _resolve_fwds _end_cs 0- 0<> drop IF _emit_rdrop THEN ;
: TIMES` >r`
: RTIMES` >S0 _begin -1 $48 c, $FF c, $0C c, $24 c, $0F c, $88 c, here 4 allot ;
: LOOP` >S0 _jmpback_mrk THEN` _end_cs drop rdrop` ;

( Stack manipulation )
: 2swap rot >r rot r> ;
: ?dup 0- 0<> IF dup THEN ;

( Arithmetic )
: abs 0- 0< IF negate THEN ;
: max > IF swap THEN nip ;
: min < IF swap THEN nip ;

( Backtick macro versions — inline at compile time )
: abs` 0-` 0<` IF` negate` THEN` ;
: max` >` IF` swap` THEN` nip` ;
: min` <` IF` swap` THEN` nip` ;
: s>d` dup` $C148, ,2 $FB, s1 $3F, ,1 ;
: adc` $48, ,1 $D311, s09 nip` ;
: dnegate` ~` swap` negate` swap` ;
: dabs` 0-` 0<` IF` dnegate` THEN` ;
: d+` >r` rot` +` swap` r>` adc` ;

( Output )
: on -1 swap ! ;
: off 0 swap ! ;
( space/putc — on i386, space falls through to putc which is a vector )
( for emit. On ff64, emit is assembly; putc is just an alias. )
: space 32 emit ;
: putc emit ;

( Memory )
: fill rot rot BEGIN 0- 0> WHILE 1- -rot 2dup c! 1+ rot REPEAT drop 2drop ;
: erase 0 fill ;
: zlen ( addr -- addr len ) dup BEGIN dup c@ 0- 0<> WHILE drop 1+ REPEAT drop over - ;

( Inline macros — miscellaneous )
\ reverse` pops return address and calls it (turns call into jmp)
: reverse` $D1FF59, ,3 ;

( FLAGS helpers — set FLAGS from known values )
: zFALSE 0 0- drop ;
: nzTRUE 1 0- drop ;

( Indexed stack access — pick` peephole detects preceding literal )
( _lit_compile emits 10-byte DUP1 + BB/BA imm32. SWAPbit unchanged. )
( lit` emits 7-byte DUP + 6Axx5B/5A. SWAPbit toggled by DUP. )
( pick` removes the literal, keeps the DUP, emits the pick instruction. )
:. _pick_bb ( -- ) ( BB path: full DUP1, SB unchanged )
  here 4- d@ -5 allot
  dup 0- 0= drop IF drop ;THEN
  1- 3 << $49 c, $8B c, $5F c, c, ;
:. _pick_6a ( -- ) ( 6A path: 7-byte DUP, SB toggled )
  -3 allot here 1+ c@ 1- 0= IF drop ;THEN
  0< IF drop nipdup` ;THEN
  3 << $49 c, $5F8B, s08 c, ;
: pick`
  here 5- c@ $FE& $BA- 0= drop IF _pick_bb ;THEN
  here 3- c@ $6A- here 1- c@ $FE& $5A- | 0<> IF !"pick:_need_constant" ;THEN
  drop _pick_6a ;
: 2over` 3 lit` pick` 3 lit` pick` ;

( Header layout constants )
8 constant h.ct
9 constant h.sz
10 constant h.nm

( Dictionary operations )
: execute >r ;
: pvtmargin $10 H@ ct|! ;

( Vector words — :^ creates push/ret preamble, 6 bytes )
( Vector xt layout: $68 <target32> $C3 <body...> )
( target32 at xt+1 is sign-extended to 64-bit by push )
: :^` :` $68, ,1 here 4+ 1+ d, $C3, ,1 ;
:. -c here dup 4- d@ + -5 allot 0 callmark! ;
: -call callmark@ here = 2drop IF -c ELSE drop THEN ;
:. _nop ;
H@ @ constant _nop pvt
: nop` $90 c, ;
: @^` -call 1+ lit` $1B8B, s09 ;
: !^` -call 1+ lit` d!` ;
: ^^` -call dup 6 + lit` 1+ lit` d!` ;
: n^` -call _nop lit` 1+ lit` d!` ;
: x^` -call 6+ lit` >r` ;
: '` -call lit` ;
( ?` converts preceding call to conditional jump )
:. _?` ?@ dup 0- 0= drop IF drop $75 THEN
  $0F c, $10+ c, dup here 4+ - d, drop ;
: ?` -call 0; _?` ;

( Range check — uses FLAGS tail-call pattern )
: within over- -rot - u> 2drop nzTRUE ? zFALSE ;

\ Locals — direct access to call stack cells and bulk data↔call transfers
\ r0/r0! alias r/r! — call stack top; r1..r5 access deeper cells
\ mov [rsp+N],rbx = 48 89 5C 24 NN (s08: XOR 5C→54 swaps rbx↔rdx)
\ mov rbx,[rsp+N] = 48 8B 5C 24 NN (s08: XOR 5C→54 swaps rbx↔rdx)
: r0!` $48, ,1 $1C89, s08 $24, ,1 drop` ;
: r1`  over` $48, ,1 $5C8B, s08 $24, ,1 $08, ,1 ;
: r1!` $48, ,1 $5C89, s08 $24, ,1 $08, ,1 drop` ;
: r2`  over` $48, ,1 $5C8B, s08 $24, ,1 $10, ,1 ;
: r2!` $48, ,1 $5C89, s08 $24, ,1 $10, ,1 drop` ;
: r3`  over` $48, ,1 $5C8B, s08 $24, ,1 $18, ,1 ;
: r3!` $48, ,1 $5C89, s08 $24, ,1 $18, ,1 drop` ;
: r4`  over` $48, ,1 $5C8B, s08 $24, ,1 $20, ,1 ;
: r4!` $48, ,1 $5C89, s08 $24, ,1 $20, ,1 drop` ;
: r5`  over` $48, ,1 $5C8B, s08 $24, ,1 $28, ,1 ;
: r5!` $48, ,1 $5C89, s08 $24, ,1 $28, ,1 drop` ;
\ >>r ( xn..x1 n -- | == xn..x1 ) move n items from data stack to call stack
\ loop: push [r15](41 FF 37); lea r15,[r15+8](4D 8D 7F 08);
\       dec rbx(48 FF CB); jnz -12(75 F4)
: >>r` under` 0-` 0>` IF`
  $37FF41, ,3 $087F8D4D, ,4 $CBFF48, ,3 $F475, ,2
  THEN` 2drop` ;
\ >>rr ( xn..x1 n -- | == x1..xn ) move n items, reversed order on call stack
\ shl rdx,3(48 C1 E2 03); sub rsp,rdx(48 29 D4)
\ loop: mov rdi,[r15](49 8B 3F); mov [rsp],rdi(48 89 3C 24);
\       lea r15,[r15+8](4D 8D 7F 08); add rsp,8(48 83 C4 08);
\       dec rbx(48 FF CB); jnz -20(75 EC)
\ sub rsp,rdx(48 29 D4)
: >>rr` dup` 0-` 0>` IF` $03E2C148, ,4 $D42948, ,3
  $3F8B49, ,3 $243C8948, ,4 $087F8D4D, ,4 $08C48348, ,4
  $CBFF48, ,3 $EC75, ,2
  $D42948, ,3 THEN` 2drop` ;
\ +r ( n -- | xn..x1 == ) pop n cells from call stack (lost)
\ shl rbx,3(48 C1 E3 03); add rsp,rbx(48 01 DC)
: +r` $48, ,1 $E3C1, s01 $03, ,1 $48, ,1 $DC01, s08 drop` ;
\ -r ( n -- | == ?n..?1 ) reserve n uninitialized cells on call stack
\ shl rbx,3(48 C1 E3 03); sub rsp,rbx(48 29 DC)
: -r` $48, ,1 $E3C1, s01 $03, ,1 $48, ,1 $DC29, s08 drop` ;
: r0` r` ;
r0!` ' alias r!`
: xxr` +r` ;
: rp@` over` $48, ,1 $E389, s01 ;
: sp@` over` $4C, ,1 $FB89, s01 ;

( Bracket state switching )
( [/] — switch between compilation and interpretation within a definition )
( [ saves anon and SC state, starts a new anonymous block )
( ] saves the block via ;, then restores original anon/SC via _] )
( ]` falls through to _] — 2>r saves SC byte + anon, ;` closes the )
( bracket block, 2r> recovers the saved state, _] restores it. )
: [` anon@ SC c@ anon:` ;
: ]` 2>r ;` 2r>
:. _] SC c! anon! ;

( Number output )
variable base
10 base! ;
:. _d tuck 0 swap m/mod 0- 0= IF drop nip ;THEN rot _d
( .digit — convert digit value 0-35 to character and emit )
( Lavarenne's char-literal version: '0'+ checks if past '9', )
( adjusts for A-F, checks 'z' overflow, falls back to '?' )
: .digit '0'+ '9' u> drop IF 39+ 'z' u> drop IF '?'_ THEN THEN emit ;
: .ub\ _d .digit ;
: .ub .ub\ space ;
:. .sign 0- 0< IF '-' emit negate THEN ;
: .\ .sign base@ .ub\ ;
: . .\ space ;
: .dec\ .sign 10 .ub\ ;
: .dec .dec\ space ;
: .u\ base@ .ub\ ;
: .u .u\ space ;
: .ux\ $10 .ub\ ;
: .ux .ux\ space ;
( .x\ — Lavarenne's hex display: shows $ prefix for values > 9 )
: .x\ .sign 9 > drop IF '$' emit THEN $10 .ub\ ;
: .x .x\ space ;

( Hex digit output — .#s prints N hex digits of a value )
( .b falls through to .#s — just provides the count 2. )
( REPEAT not LOOP: Lavarenne's original uses TIMES...REPEAT. )
: .b 2
: .#s TIMES dup r 4* >> $F & .digit REPEAT drop ;
: .w 4 .#s ;

( cr — print newline, as a vector for overridability )
:^ cr ."^J" ;

( I/O — stdout, write, type needed before dictionary listing )
1 constant stdout
: write ( addr # fd -- n ) >r swap r> 3 1 syscall ;
: type stdout write drop ;

( Dictionary listing — Lavarenne's original uses START/ENTER/UNTIL )
( words` is a backtick macro: START iterates headers, printing name, )
( ENTER advances to next header, UNTIL terminates on zero-length name. )
: h.next dup h.sz+ c@ h.nm+ 1+ + ;
: h.name dup h.nm+ over h.sz+ c@ type space ;
: words` H@ START 2dup+ 1+ -rot type space ENTER h.sz+ c@+ 0- 0= UNTIL 2drop cr ;

( Debug output — .s` shows compile-time stack, ds shows runtime stack )
( _s recurses depth-many times: 0; exits on zero count, depth 2 < )
( exits when stack is too shallow. On unwind, prints each saved value. )
:^ ui : prompt space depth .\ ';' anon@ 0- 0= drop IF 1- THEN emit space ;
:. _s 0; depth 2 < drop IF drop ;THEN drop 1- swap >r _s r . r> ;
: .s` prompt depth _s cr ;
: ds prompt depth _s cr ;
:. _ss 1- 0; swap >r _ss r .x r> ;
: ss depth ."( " dup .dec\ ."; " 1+ 3 max _ss .")" cr ;
: dd depth TIMES drop REPEAT ;
: .h` ."free:" here H@ - $400/ .\ ."k_SC=" SC c@ . .s` ;
: .l 8 .#s ;

( Dictionary inspector — Lavarenne's .hdr+ advances to next header )
( Stack effect: ( addr -- next-addr ) — prints header info, returns next )
: .hdr+ dup .x\ .":_" dup @ .x dup h.ct+ c@ .x h.sz+ c@+ 2dup type + 1+ ;
: .hdrs H@ START .hdr+ cr ENTER dup h.sz+ c@ 0- 0= drop UNTIL drop ;
: .hdr .hdr+ cr drop ;

( System words )
: bye` ;` cr 0 exit ;
: EOF` tp@ >in! ;` ;

( Dictionary state save/restore — mark/marker )
\ _mark: called from a marker word's body. Restores here and H to
\ the state when the marker was created. r> gets the return address
\ (inside the marker word); -5 gives the call instruction address;
\ subtracting from here and calling allot restores the code pointer.
\ Then walks headers from H@ via h.next, comparing each xt with here,
\ until finding the marker's header. The header after it becomes the
\ new H (discarding the marker and all later definitions).
:. _mark ;` r> 5- here - allot anon:`
  H@ BEGIN dup@ swap h.sz+ c@+ + 1+ swap here = 2drop UNTIL H! ;
( marker — Lavarenne's original uses '`' char literal for backtick append )
( mark` falls through to marker — ;` + wsparse provides the name string )
: mark` ;` wsparse
: marker 2dup + dup c@ >r dup >r '`' swap c! 1+
  here 0 header 2r> c! _mark ' call, anon:` ;

( I/O constants — stdout/write/type defined earlier [before h.name] )
0 constant stdin
2 constant stderr

( noauto — variable controlling auto-semicolon in REPL )
( When 0, typed lines auto-execute via _auto calling ; )
variable noauto pvt
: \` 2 >in -! lnparse 2drop 1 noauto! ;

( eval — evaluate a counted string as Forth source )
( Saves >in and tp, sets new parsing bounds, calls compiler, restores. )
: eval >in@ tp@ 2>r over+ tp! >in! compiler 2r> tp! >in! ;

( _auto — auto-execute anonymous code if noauto is 0 )
( Called after compiler returns in eval. Decrements >in and calls ; )
:. _auto noauto@ 0- drop 0= IF >in@ 1- >in! ;` THEN ;

( eval. — evaluate with auto-execution )
( Like eval but calls _auto to execute the compiled code )
:. eval. >in@ tp@ 2>r over+ tp! >in! compiler _auto 2r> tp! >in! ;

( key — read a single character from stdin )
: key tib 1 accept drop tib c@ ;

( features — buffer for tracking loaded features )
( append — append counted string to a counted-string buffer )
( appendc — append single char to a counted-string buffer )
( -v` — display list of loaded features )
variable features 100 allot
: append 2dup c@ + over 2>r c@+ + place drop 2r>
  2dup c! + 1+ 0 swap c! ;
: appendc tuck c@+ + tuck c! 0 over 1+ c! over- swap c! ;
: -v` ."\ features:" features c@+ type cr ;

( 2swap` — inline version of 2swap )
: 2swap` rot` >r` rot` r>` ;

( count — ANS standard name for c@+: addr -- addr+1 byte )
: count c@+ ;

( move — smart overlapping copy: src dst n -- )
:. _move> >r 2dup u< 2drop IF r> cmove> ;THEN r> cmove ;
: move _move> ;

( pad — scratch buffer, 256 bytes above here )
: pad here 256+ ;

( Hide private words — zero the first name byte of pvt-marked headers )
( Compact header chain: remove private entries, reclaim space )
( hidepvt` is a compile-time macro; _hidepvt is the runtime callable version )
( Algorithm: walk chain. For each pvt header, shift H@..here up by its )
( size, overwriting it. H@ advances by that amount. Pvtmargin stops walk. )
variable hide hide on
:. _hdr_size h.sz+ c@ h.nm+ 1+ ;
:. _remove_hdr ( addr -- addr+sz )
  dup _hdr_size             ( addr sz )
  >r dup H@ - H@            ( addr n src -- R: sz )
  swap H@ r + swap           ( addr src dst n )
  cmove>                     ( addr ) 
  r> dup H +! + ;            ( addr+sz )
:. _hidepvt hide@ 0; drop
  H@ BEGIN dup h.sz+ c@ 0- 0<> drop WHILE
    dup h.ct+ c@ dup $10& 0<> drop IF 2drop ;THEN
    8& 0<> drop IF _remove_hdr ELSE h.next THEN
  REPEAT drop ;
: hidepvt` _hidepvt ;

( Error recovery: show location, print message, restore dict/code state )
( saved_here holds the compilation pointer before each eval., for error recovery )
variable saved_here pvt
:. _recover tib >in@ over - type ."_<-error:_" c@+ type cr 2drop
  anon@ 0- 0= drop IF H@ dup @ swap h.sz+ c@ h.nm+ 1+ + H! THEN
  saved_here@ here swap - allot 0 SC c! anon:` ;
( Forth REPL: prompt, read, eval with catch, error recovery, loop )
( accept buffer is 80 bytes — adequate for line-at-a-time terminal input )
:^ _top pvt BEGIN
  ui 0 noauto!
  tib 4096 accept dup 0- 0= drop IF drop 0 exit THEN
  here saved_here! tib swap eval. ' catch dup 0- 0<> drop IF _recover ELSE drop THEN
AGAIN

( Command-line arguments — ff_argc and ff_argv set by assembly at startup )
: argc ff_argc@ ;
:. _argv 8* ff_argv@ + @ ;
: argv _argv zlen ;

( Hex memory dump — 16 bytes per line with address header )
:. _dumpln dup .l .":" 16 TIMES space dupc@ .b 1+ REPEAT ;
: dump bounds BEGIN 2dup u> WHILE _dumpln cr REPEAT 2drop ;

( Peephole: >mov replaces variable fetch with inc/dec for ++`/--` )
: >mov here 7- c@ $48- here 6- c@ $8B- | drop
  here 4- d@ 10+ swap -17 allot $48 c, $FF c, c, d, ;
: ++` $05 >mov ;
: --` $0D >mov ;

( Conditional compilation — ported from ff.boot )
( _[] scans input for matching [ELSE] or [THEN], handling nesting )
:. _[] '[' parse 2drop wsparse 0- 0= drop IF drop >in! !"unbalanced" ;THEN
  1 >in -! dup "ELSE]" $- 0<> drop IF dup "THEN]" $- 0<> drop IF "IF]" $- drop _[] ?
  BEGIN _[] 0<> UNTIL _[] ;THEN 1+ THEN drop ;
: [IF]` 0- 0= drop IF
: [ELSE]` >in@ _[] drop
: [THEN]` THEN ;
( [~]` — test whether a word exists. Returns 0 if found, nonzero if not. )
( Usage: [~] foo [IF] ...not-found code... [ELSE] ...found code... [THEN] )
: [~]` wsparse find nip ;
1 constant [1]`
0 constant [0]`
8 constant cell
cell 4 - constant [64]`

( OS-specific definitions continue in fflin64.boot )
