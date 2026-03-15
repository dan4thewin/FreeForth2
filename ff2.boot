\ ff2.boot  FreeForth2 unified boot (i386 + x86-64)
\ backtick macros: "dup" in source compiles via dup` defined here

\ --------------------------------------------------------------------
\ true primitives -- arch-specific register encodings
\ swap` and SWAPbit adjusters (s01/s08/s09/s1) are assembly
[64] [IF]
\ x86-64 opcodes [REX.W = $48]:
\   4D8D7FF8(lea r15,[r15-8])  push-NOS: allocate slot
\   4D8D7F08(lea r15,[r15+8])  pop-NOS: release slot
\   498917(mov [r15],rdx)      store NOS to data stack
\   498B17(mov rdx,[r15])      load NOS from data stack
\   4889DA(mov rdx,rbx)        copy TOS to NOS
: ,4` $04C58348, ,"H^C~E~^D" ; \ self-bootstrap: 4883C504(add rbp,4)
: ,3` $03C58348, ,4 ;
: ,2` $02C58348, ,4 ;
: ,1` $C5FF48, ,3 ;             \ 48FFC5(inc rbp) is 3 bytes
: under` $F87F8D4D, ,4 $178949, ,1 s08 ; \ 4D8D7FF8 498917
: nip` $178B49, ,1 s08 $087F8D4D, ,4 ;   \ 498B17 4D8D7F08
: ext $48, ,1 ; \ REX.W prefix
[ELSE]
: ,3` $036D8D, ,"^M~m^C" ; \ self-bootstrap: 8D6D03(lea ebp,[ebp+3])
: ,4` $046D8D, ,3 ;
: ,2` $026D8D, ,3 ;
: ,1` $45, ,"E" ;           \ 45(inc ebp) is 1 byte
: under` >C1 $52, s1 ;     \ 52(push edx) with SWAPbit
: nip` >C1 $5A, s1 ;       \ 5A(pop edx) with SWAPbit
: ext ;
[THEN]
: s01. ,1 s01 ; : s08. ,1 s08 ; : s09. ,1 s09 ;
\ --------------------------------------------------------------------
\ shared compositions -- arch-independent
: over` under` swap` ;
: drop` swap` nip` ;
: dup` under`
: nipdup` ext $DA89, s09 ; \ 4889DA(mov rdx,rbx) / 89DA(mov edx,ebx)
: tuck` swap` over` ;

\ --------------------------------------------------------------------
\ arch-specific backtick macros
[64] [IF]
: allot` $DD0148, s08. drop` ; \ 4801DD(add rbp,rbx)
: c,` $5D88, s08 $00, ,1 $C5FF48, ,3 drop` ; \ 885D00(mov [rbp],bl)48FFC5(inc rbp)
: w,` $66, ,1 $5D89, s08 $00, ,1 $02C58348, ,4 drop` ; \ 66895D00(mov [rbp],bx)4883C502(add rbp,2)
: d,` $5D89, s08 $00, ,1 $04C58348, ,4 drop` ; \ 895D00(mov [rbp],ebx)4883C504(add rbp,4)
: ,`  $5D8948, s08. $00, ,1 $086D8D48, ,4 drop` ; \ 48895D00(mov [rbp],rbx)488D6D08(lea rbp,[rbp+8])

\ r@: 488B1C24(mov rbx,[rsp])
\ 2r@: 488B5C2408(mov rbx,[rsp+8]) then fall through to r`
: 2r` over` $5C8B48, s08. $24, ,1 $08, ,1
: r`  over` $1C8B48, s08. $24, ,1 ;
\ return stack inline macros
: rdrop` $48, ,1 $C483, ,2 $08, ,1 ; \ 4883C408(add rsp,8)
: 2rdrop` $48, ,1 $C483, ,2 $10, ,1 ; \ 4883C410(add rsp,16)

\ rotation via xchg [r15],reg
: -rot` swap`
: >rswapr>` $178749, s08. ; \ 498717(xchg [r15],rdx)

\ --------------------------------------------------------------------
\ I/O -- stdout, write, type needed before dictionary listing
: write ( addr # fd -- n ) >rswapr> 3 1 syscall ;
: type 1 write drop ;

\ division -- >S0 forces rbx=TOS, rdx=NOS before hardcoded register ops
\ /%` ( a b -- a%b a/b )
\ 4889D0(mov rax,rdx)4899(cqo)48F7FB(idiv rbx)4889C3(mov rbx,rax)
: /%` >S0 $48D08948, ,4 $FBF74899, ,4 $C38948, ,3 ;

\ unary ops
: 1-` $CBFF48, s01. ; \ 48FFCB(dec rbx)
: 1+` $C3FF48, s01. ; \ 48FFC3(inc rbx)
: 4+` $C38348, s01. $04, ,1 ; \ 4883C304(add rbx,4)
: 8+` : cell+` $C38348, s01. $08, ,1 ; \ 4883C308(add rbx,8)
: 2*` $E3D148, s01. ; \ 48D1E3(shl rbx,1)
: 2/` $FBD148, s01. ; \ 48D1FB(sar rbx,1)
: 4*` $E3C148, s01. $02, ,1 ; \ 48C1E302(shl rbx,2)
: 8*` : cell*` $E3C148, s01. $03, ,1 ; \ 48C1E303(shl rbx,3)
: 4/` $FBC148, s01. $02, ,1 ; \ 48C1FB02(sar rbx,2)
: 8/` $FBC148, s01. $03, ,1 ; \ 48C1FB03(sar rbx,3)
: <<` $D98948, s08. $E2D348, s01. drop` ; \ 4889D9(mov rcx,rbx)48D3E2(shl rdx,cl)
: >>` $D98948, s08. $EAD348, s01. drop` ; \ 4889D9(mov rcx,rbx)48D3EA(shr rdx,cl)

: d@` $1B6348, s09. ; \ 48631B(movsxd rbx,[rbx])

\ string/memory copy (rep movsb)
\ place` ( src count dest -- dest )
\ 4889DF(mov rdi,rbx)4889D1(mov rcx,rdx)498B37(mov rsi,[r15])
\ 498B5708(mov rdx,[r15+8])4983C710(add r15,16)F3A4(rep movsb)
: place` >S0
    $DF8948, ,3 $D18948, ,3 $378B49, ,3
    $08578B49, ,4 $10C78349, ,4 $A4F3, ,2 ;

\ 32-bit (dword) store -- for patching jump offsets
: 2dupd!` $1389, s09 ; \ 8913(mov [ebx],edx) 32-bit store
: overd!` swap` : tuckd!` 2dupd!` nip` ; : d!` tuckd!` drop` ;

\ 3dup` ( a b c -- a b c a b c ) over` over` then copy 3rd item:
\ 4D8D7FF8(lea r15,[r15-8])498B4718(mov rax,[r15+24])498907(mov [r15],rax)
: 3dup` over` over` $F87F8D4D, ,4 $18478B49, ,4 $078949, ,3 ;

: >C0 ; : >C1 ; \ no CALLbit in x86-64
[ELSE]
: allot` $DD01, s08 drop` ;
: c,` $45005D88, s08 ,2 drop` ;
: d,` : ,` $FF005D89, s08 ,1 ,4` drop` ;
: w,` $005D8966, ,1 s08 ,1 ,2` drop` ;
: 2r` over` $04588B, s08 ,1
: r` over` $188B, s08 ;
: rdrop` $04C483, c04 ,1 ;
: 2rdrop` $08C483, c04 ,1 ;
: -rot` swap`
: >rswapr>` $201487, s08 -1 allot c04 ;

: /%` >S0 $99D08950, ,4 $C389FBF7, ,4 $58, ,1 ;

: 1-` $4B, s1 ;
: 1+` $43, s1 ;
: 4+` : cell+` $04C383, s01 ,1 ;
: 2*` $E3D1, s01 ;
: 4*` : cell*` $02E3C1, s01 ,1 ;
: 2/` $FBD1, s01 ;
: 4/` $02FBC1, s01 ,1 ;
: 8*` $03E3C1, s01 ,1 ;
: 8/` $03FBC1, s01 ,1 ;
: <<` $E2D3D989, s08 s01 drop` ;
: >>` $EAD3D989, s08 s01 drop` ;

: place` $D189DF89, s08 s08 >C1 $5AA4F35E, ,3 s1 ;

: 3dup` over` over` $082474FF, ,4 ;
[THEN]
: r>` over`
: dropr>` >C0 $5B, s1 ; \ 5B(pop rbx)
: dup>r`  >C0 $53, s1 ; \ 53(push rbx)
: >r` dup>r` drop` ;
: rot` >rswapr>` swap` ;
: 2xchg` swap` >rswapr>` swap` ;

\ compilation helpers
: here` over` ext $EB89, s01 ; \ 4889EB(mov rbx,rbp)

: ~`      ext $D3F7, s01 ; \ 48F7D3(not rbx)
: negate` ext $DBF7, s01 ; \ 48F7DB(neg rbx)
: bswap`  ext $CB0F, s01 ; \ 480FCB(bswap rbx)
: flip`       $FB86, s09 ; \ 86FB(xchg bh,bl)
\ binary arithmetic -- "over" variants preserve NOS
: over&` ext $D321, s09 ; \ 4821D3(and rbx,rdx)
: over|` ext $D309, s09 ; \ 4809D3(or rbx,rdx)
: over^` ext $D331, s09 ; \ 4831D3(xor rbx,rdx)
: over+` ext $D301, s09 ; \ 4801D3(add rbx,rdx)
: over-` ext $D329, s09 ; \ 4829D3(sub rbx,rdx)
\ : over*` ext $0F, ,1 $DAAF, s09 ;
: over*` ext $DAAF0F, ,1 s09 ; \ 480FAFDA(imul rbx,rdx)

\ memory load
: @` ext [32] [IF] : d@` [THEN] $1B8B, s09 ; \ 488B1B(mov rbx,[rbx])
: c@` ext $1BB60F, ,1 s09 ; \ 480FB61B(movzx rbx,byte[rbx])
: cs@` ext $1BBE0F, ,1 s09 ; \ 480FBE1B(movsx rbx,byte[rbx])
: w@` $1BB70F, ,1 s09 ; \ 0FB71B(movzx rbx,word[rbx])
: ws@` ext $1BBF0F, ,1 s09 ; \ 480FBF1B(movsx rbx,word[rbx])
\ fetch preserving address: dup@` = over` + fetch through NOS
: dup@`  over` ext $1A8B, s09 ; \ 488B1A(mov rbx,[rdx])
: dupc@` over` ext $1AB60F, ,1 s09 ; \ 480FB61A(movzx rbx,byte[rdx])
: dupw@` over` $1AB70F, ,1 s09 ; \ 0FB71A(movzx rbx,word[rdx])

\ memory store (2dup variants preserve both operands)
\ 2dupw!` can't fall through -- REX.W overrides the $66 prefix
: 2dupw!` $66, ,1 $1389, s09 ; \ 668913(mov [ebx],dx) 16-bit store
: 2dup!` ext $1389, s09 ; \ 488913(mov [rbx],rdx)
: 2dupc!` $1388, s09 ; \ 8813(mov [rbx],dl)
: 2dup+!` ext $1301, s09 ; \ 480113(add [rbx],rdx)
: 2dup-!` ext $1329, s09 ; \ 482913(sub [rbx],rdx)

: 2+` 1+` 1+` ;
: cmove` swap` place` drop` ;

\ consuming binary ops
: &` over&` nip` ;
: |` over|` nip` ;
: ^` over^` nip` ;
: +` over+` nip` ;
: -` swap` over-` nip` ;
: *` over*` nip` ;
: /` /%` nip` ;
: %` /%` drop` ;
: 2dup+` over` over+` ;

\ consuming store ops -- fall-through triads (over! -> tuck! -> !)
: over!`  swap` : tuck!`  2dup!`  nip` ; : !`  tuck!`  drop` ;
: overw!` swap` : tuckw!` 2dupw!` nip` ; : w!` tuckw!` drop` ;
: overc!` swap` : tuckc!` 2dupc!` nip` ; : c!` tuckc!` drop` ;
: over+!` swap` : tuck+!` 2dup+!` nip` ; : +!` tuck+!` drop` ;
: over-!` swap` : tuck-!` 2dup-!` nip` ; : -!` tuck-!` drop` ;

\ fetch and advance
: @+`  dup@`  swap` cell+` swap` ;
: w@+` dupw@` swap` 2+` swap` ;
: c@+` dupc@` swap` 1+` swap` ;

\ double-cell fetch/store
: 2@` @+` swap` @` swap` ;
: 2!` tuck!` cell+` !` ;

\ compile literal: lit` takes value from TOS, emits push code
: off` 0 lit` swap` !` ;
: on` -1 lit` swap` !` ;

\ composed operations
: 2dup` over` over` ;
: 2r>` 2dup` dropr>` swap` dropr>` swap` ;
: 2dup>r` swap` dup>r` swap` dup>r` ;
\ 2>r` falls through to 2drop` -- push both then discard both
: 2>r` 2dup>r`
: 2drop` drop` drop` ;
: 2swap` rot` >r` rot` r>` ;

\ --------------------------------------------------------------------
\ dictionary defining words
: ct|! h.ct+ dupc@ rot | swap c! ;
: create` :` 1 H@ ct|! anon:` ;
: variable` create` 0 , anon:` ;
\ alias` falls through to _alias
: alias` :`
: _alias H@ ! $20 H@ ct|! anon:` ;
\ equ shorter, and more usual for assembly programmers
: constant` : equ` create` _alias ;

\ private word infrastructure
8   constant CT_PVT
$10 constant CT_MGN
$20 constant CT_ALIAS
: :.` :`
: pvt` CT_PVT H@ ct|! ;
: pvtmargin CT_MGN H@ ct|! ;

\ extended arithmetic
[64] [IF]
\ _m/mod: 498B07(mov rax,[r15])4983C708(add r15,8) 48 w, 4889C3(mov rbx,rax)
:. _m/mod >S0 $078B49, ,3 $08C78349, ,4 $48, ,1 w, $C38948, ,3 ;
\ _m*: 4889D0(mov rax,rdx) 48 w, 4889D3(mov rbx,rdx)4889C2(mov rdx,rax)
:. _m* >S0 $D08948, ,3 $48, ,1 w, $D38948, ,3 $C28948, ,3 ;
[ELSE]
:. _m/mod >S0 >C1 $240487, ,3 w, $58C389, ,3 ;
:. _m* >S0 $D089C189, ,4 w, $D389, ,2 $C889C289, ,4 ;
[THEN]
\ ( x y z -- mod quot ) (x*y)/z
: m/mod`  $FBF7 _m/mod ;
: um/mod` $F3F7 _m/mod ;
: m*`  $EBF7 _m* ;
: um*` $E3F7 _m* ;
: */mod` >r` m*` r>` m/mod` ;
: */` */mod` nip` ;

\ --------------------------------------------------------------------
\ bracket state switching
\ [ saves anon/SC state; ] restores via _]
: [` anon@ SC c@ anon:` ;
: ]` 2>r ;` 2r> : _] SC c! anon! ;
: execute >r ;
: reverse` $D1FF59, ,3 ; \ 59(pop rcx)FFD1(call rcx)

\ noauto -- controls auto-semicolon in REPL
variable noauto pvt
: \` 2 >in -! lnparse 2drop 1 noauto! ;
: (` ')' parse 2drop ;
: EOF` tp@ >in! ;` ;

\ --------------------------------------------------------------------
\ FLAGS-based conditionals
\ 0-` emits test TOS,TOS; SWAPbit via s09
[64] [IF]
: 0-` $DB8548, s09. ; \ 4885DB(test rbx,rbx)
[ELSE]
variable ?#
: 0-` $DB09, s09 ; \ 09DB(or ebx,ebx)
[THEN]
\ helpers -- set FLAGS from known values
: zFALSE 0 0- drop ;
: nzTRUE 1 0- drop ;
\ _?1 unary, _?2 binary, _?1. unary dotted, _?2. binary dotted
:. _?1 ?# c! ;
\ _?1./_?2. produce a Forth boolean [-1/0] in a register
:. _?1a. $C931, ,2 ; \ 31C9(xor ecx,ecx)
\ SETcc cl / dec rcx / mov rbx,rcx [with SWAPbit]
\ 1^ inverts Jcc; $20+ converts Jcc to SETcc; 8<< positions in dword
:. _?1b. 1^ $20+ 8 <<
   [64] [IF] $48C1000F| d, $C9FF48, ,3 [ELSE] $49C1000F| , [THEN]
   $CB89, ,1 s1 ;
:. _?1. _?1a. 0-` _?1b. ;
\ _?2: store Jcc + emit cmp rdx,rbx
:. _?2 _?1 ext $DA39, s09 ; \ 4839DA(cmp rdx,rbx)
:. _?2. _?1a. ext $DA39, s09 _?1b. nip` ;
\ condition code factory -- dup shares Jcc opcode between definitions
\ ; after each def executes the anon body, consuming one copy
$74 dup : 0=`  lit _?1 ; dup : 0=.`  lit _?1. ; dup : =`  lit _?2 ; : =.`  lit _?2. ;
$75 dup : 0<>` lit _?1 ; dup : 0<>.` lit _?1. ; dup : <>` lit _?2 ; : <>.` lit _?2. ;
$7C dup : 0<`  lit _?1 ; dup : 0<.`  lit _?1. ; dup : <`  lit _?2 ; : <.`  lit _?2. ;
$7D dup : 0>=` lit _?1 ; dup : 0>=.` lit _?1. ; dup : >=` lit _?2 ; : >=.` lit _?2. ;
$7E dup : 0<=` lit _?1 ; dup : 0<=.` lit _?1. ; dup : <=` lit _?2 ; : <=.` lit _?2. ;
$7F dup : 0>`  lit _?1 ; dup : 0>.`  lit _?1. ; dup : >`  lit _?2 ; : >.`  lit _?2. ;
\ carry flag + unsigned: C1?/C0? use _?1 (unary); u< etc use _?2 (binary)
$72 dup : C1?` lit _?1 ; : C1?.` lit _?1. ;
$73 dup : C0?` lit _?1 ; : C0?.` lit _?1. ;
$72 dup : u<`  lit _?2 ; : u<.`  lit _?2. ;
$73 dup : u>=` lit _?2 ; : u>=.` lit _?2. ;
$76 dup : u<=` lit _?2 ; : u<=.` lit _?2. ;
$77 dup : u>`  lit _?2 ; : u>.`  lit _?2. ;

\ --------------------------------------------------------------------
\ vectors -- :^ creates push/ret preamble, 6 bytes
\ xt layout: $68 <target32> $C3; target32 sign-extended by push
: :^` :` $68, ,1 here 5+ d, $C3, ,1 ; \ 68xxxxxxxx(push imm32)C3(ret)

\ --------------------------------------------------------------------
\ flow control
\ ?@: fetch ?# and zero it; ?#! is a cell store (cond_jmp is dq in asm)
:. ?@ ?# c@ 0 ?#! ;
:. ?nn 0- ,"t^AC~" !"is_not_preceded_by_a_condition"
\ cond: read ?#, validate, invert bit 0 (jump on OPPOSITE condition)
: cond ?@ ?nn 1^ ;
\ cond.: convert stack boolean to FLAGS for IF./WHILE./UNTIL.
:. cond. 0-` drop` 0<>` ;
:. -c` here dup 4- d@ + -5 allot 0 callmark! ;
[64] [IF]
: IF.` cond.
: IF` >S0 cond $0F c, $10+ c, here 4 allot ; \ 0F8x(Jcc rel32)
: SKIP` >S0 $E9, ,1 here 4 allot ; \ E9(jmp rel32)
: THEN` >S0 0 callmark!
:. _then here over- 4 - swap d! ;
: ELSE` SKIP` swap THEN` ;

: ;THEN` ;;` THEN` ;

: -call callmark@ here = 2drop IF -c` ELSE drop THEN ;
\ ?` converts preceding call to conditional jump
:. _?` ?@ dup 0- 0= drop IF drop $75 THEN
  $0F c, $10+ c, dup here 4+ - d, drop ;
[ELSE]
:. -js c, c, ;
:. -jc $0F, ,1 $12+ swap 1- swap
:. -ju 2- c, 3- , ;
:. _?` ?@ 0- ,"u^C" $75_ swap
:. -j here 2+ - -$80 >= drop swap -js [ -c` 1 here +! ] _?
  $EB = drop -ju -c _? -jc ;
:^ -call callmark@ here = 2drop -c` -c _? !"is_not_preceded_by_a_call"
: ?` -call _?` ;
: lib:` :` #lib lit` #fun ' call, ;` ;
: fun:` :` lit` lit` #call ' call, ;` ;

:. _off !"jump_off_range"
:. ?off dup 2* over^ -$100& drop _off ? ;
:. SC, here SC c@ c, ;
: IF.` cond.
: IF` cond c, SC, ;
: SKIP` $EB c, SC, ;
: ELSE` SKIP` swap dupc@ SC c!
: THEN` dupc@ >SC
:. _then here over- 1- ?off swap c! 0 callmark! ;
: ;THEN` ;;` dupc@ SC c! _then ;
[THEN]

: '` -call lit` ;
: 0;`   0-` 0=`  IF` drop` ;THEN` ;
: 0<>;` 0-` 0<>` IF` drop` ;THEN` ;
: ?dup` 0-` 0<>` IF` dup` THEN` ;
: BOOL` 0 lit` IF` ~` THEN` ;
: CASE` =` drop` IF` drop` ;

\ --------------------------------------------------------------------
\ loop infrastructure: mrk, cstack, START/ENTER/BREAK/END
\ mrk cell 0: loop body address (backward jump target)
\ loop openers save old mrk to cstack, push 0 break-sentinel, set mrk[0]
\ loop closers resolve breaks from cstack and restore mrk
\ BEGIN: ( -- 0 ), RTIMES: ( -- -1 js )
\ END only resolves forward refs; use AGAIN/UNTIL/REPEAT for backward
\ >cs ( x -- ) pushes to compile-time stack
\ cs> ( -- x ) pops from compile-time stack
[64] [IF]
: ?` -call 0; _?` ;
variable mrk 0 mrk 8+ !
:. _begin mrk 2@ >cs >cs 0 >cs here mrk! ;
:. _jmpback_mrk >S0 $E9 c, mrk@ here 4+ - d, ;
:. _cjmpback_mrk >S0 cond $0F c, $10+ c, mrk@ here 4+ - d, ;
:. _resolve_breaks cs> 0; _then _resolve_breaks ;
:. _end_cs _resolve_breaks cs> cs> mrk 2! ;
:. _resolve_fwds 0- 0> IF THEN` _resolve_fwds THEN ;
: START` _begin 0 $E9 c, 0 d, here mrk! ;
: BEGIN` >S0 _begin 0 ;
: TIMES` >r`
: RTIMES` >S0 _begin -1 $240CFF48, ,4 $880F, ,2 here 4 allot ; \ 48FF0C24(dec qword[rsp])0F88(js rel32)
: ENTER` >S0 mrk@ 4- _then ;
: WHILE.` cond.
: WHILE` IF` ;
: BREAK` >S0 $E9 c, 0 d, here 4- >cs _then ;
: TILL.` cond.
: TILL` >S0 cond $0F c, $10+ c, mrk@ here 4+ - d, ;
: AGAIN` _jmpback_mrk 0- 0<> IF THEN` ELSE _end_cs drop THEN ;
: UNTIL.` cond.
: UNTIL` _cjmpback_mrk _resolve_fwds _end_cs drop ;
: END` >S0 _resolve_fwds _end_cs drop ;
: REPEAT` _jmpback_mrk _resolve_fwds _end_cs 0- 0<> drop IF rdrop` THEN ;
[ELSE]
: align` $90909090, here negate 3& allot ;
create mrk 0 , 0 ,
: START` $9090 w, align` $00EB here 2- w!
: BEGIN` mrk 2@ align` here SC c@ over+ mrk 2! ;
: TIMES` >r`
: RTIMES` >C1 BEGIN` $007808FF, ,4 ;
: ENTER` mrk@ dup 3& >SC -4& 1- _then ;
: WHILE.` cond.
: WHILE` cond
: +jmp mrk 2@ 3& >SC swap c, here dup mrk 4+ ! swap - ?off c, ;
: jmp` $EB +jmp ;
: BREAK` jmp` THEN` ;
: TILL.` cond.
: TILL` cond
: -jmp mrk@ dup 3& >SC -4& -j ;
: AGAIN` $EB -jmp THEN` ;
: UNTIL.` cond.
: UNTIL` TILL`
: END` mrk 2@ dup 3& >SC -4& swap
  START dupc@ over _then - ENTER = TILL [ mrk 2! ]
  @ $007808FF- 0= drop IF under 3+ _then rdrop` THEN
  drop mrk 2! ;
: REPEAT` $EB -jmp END` ;
[THEN]

[64] [IF]
: @^` -call 1+ lit` $1B8B, s09 ;
: ^^` -call dup 6 + lit` 1+ lit` d!` ;
:. nop ;
: n^` -call nop ' lit` 1+ lit` d!` ;
: !^` -call 1+ lit` d!` ;
[ELSE]
: @^` -call over` $1D8B, s08 1+ , ;
: ^^` -call $05C7, ,2 dup 1+ , 6+ , ;
:. nop ;
: n^` -call nop ' lit` SKIP
: !^` -call THEN $1D89, s08 1+ , drop` ;
\ : x^` -call 6+ dcall, ;
[THEN]
: x^` -call 6+ lit` >r` ;

\ --------------------------------------------------------------------
\ arithmetic
: max` >` IF` swap` THEN` nip` ;  \ n2 n1 -- max(n2,n1)
: min` <` IF` swap` THEN` nip` ;  \ n2 n1 -- min(n2,n1)
: abs` 0-` 0<` IF` negate` THEN` ;
: dnegate` ~` swap` negate` swap` ;
: dabs` 0-` 0<` IF` dnegate` THEN` ;
: adc` ext $D311, s09 nip` ; \ 4811D3(adc rbx,rdx)
: d+` >r` rot` +` swap` r>` adc` ;

\ address arithmetic
: bounds` over+` swap` ;
: within over- -rot - u> 2drop nzTRUE ? zFALSE ;  \ n [ ) -- ; nz?

[64] [IF]
: s>d` dup` $C148, ,2 $FB, s1 $3F, ,1 ; \ 48C1FB3F(sar rbx,63)
\ peephole: >mov replaces variable fetch with inc/dec for ++`/--`
: >mov here 7- c@ $48- here 6- c@ $8B- | drop
  here 4- d@ 10+ swap -17 allot $48 c, $FF c, c, d, ;
: ++` $05 >mov ;
: --` $0D >mov ;
[ELSE]
: s>d` dup` 0<.` ;
:. mov? here 6- c@ $8b- 0; !"is_not_preceded_by_a_mov" ;
:. dst? here 5- c@ $15- 0; $8- 0; !"destination_is_not_edx_or_ebx" ;
:^ >mov mov? dst? $90 here 7- c! here 6- w! ;
: ++` $5FF >mov swap` ;
: --` $DFF >mov swap` ;
[THEN]

\ --------------------------------------------------------------------
\ conditional compilation
\ _[] scans input for matching [ELSE] or [THEN], handling nesting
:. _[] '[' parse 2drop wsparse 0- 0= drop IF drop >in! !"unbalanced" ;THEN
  1 >in -! dup "ELSE]" $- 0<> drop IF dup "THEN]" $- 0<> drop IF "IF]" $- drop _[] ?
  BEGIN _[] 0<> UNTIL _[] ;THEN 1+ THEN drop ;
: [IF]` 0- 0= drop IF
: [ELSE]` >in@ _[] drop
: [THEN]` THEN ;
: [~]` wsparse find nip ; \ 0 if found, nonzero if not
1 constant [1]`
0 constant [0]`
1 cell* constant cell
cell 4 - 0= drop BOOL constant [32]`
[32]` ~ constant [64]`
\ I/O constants
0 constant stdin
1 constant stdout
2 constant stderr

: key tib 1 under accept drop c@ ; \ -- c
: space 32
:^ putc : emit tib 2dupc! swap 1_ type ; [THEN]
:^ cr ."^J" ; \ print newline

\ --------------------------------------------------------------------
\ number output
variable base 10 base! ;
\ .digit: 0-35 -> char; adjusts for a-z, falls back to '?'
:. _d tuck 0 swap m/mod 0- 0= IF drop nip ;THEN rot _d
: .digit '0'+ '9' u> drop IF 39+ 'z' u> drop IF '?'_ THEN THEN putc ;
: .ub\ _d .digit ;
: .ub .ub\ space ;
:. .sign 0- 0< IF '-' putc negate THEN ;
: .\ .sign base@ .ub\ ;
: . .\ space ;
: .dec\ .sign 10 .ub\ ;
: .dec .dec\ space ;
: .u\ base@ .ub\ ;
: .u .u\ space ;
: .ux\ $10 .ub\ ;
: .ux .ux\ space ;
: .x\ .sign 9 > drop IF '$' putc THEN $10 .ub\ ; \ hex with $ prefix
: .x .x\ space ;

\ .#s prints N hex digits; .b falls through with count 2
: .b 2
: .#s TIMES dup r 4* >> $F& .digit REPEAT drop ;
: .w 4 .#s ;
: .l 8 .#s ;

:^ ui : prompt space depth .\ ';' anon@ 0- 0= drop IF 1- THEN putc space ;
:. _ss 1- 0; swap >r _ss r .x r> ;
: ss depth ."( " dup .dec\ ."; " 1+ 3 max _ss .")" cr ;
: dd depth TIMES drop REPEAT ;
[64] [IF]
\ hex memory dump -- 16 bytes per line with address header
:. _dumpln dup .l .":" 16 TIMES space dupc@ .b 1+ REPEAT ;
: dump bounds BEGIN 2dup u> WHILE _dumpln cr REPEAT 2drop ;
\ _s recurses depth-many times, prints on unwind
:. _s 0; depth 2 < drop IF drop ;THEN drop 1- swap >r _s r . r> ;
: .s` prompt depth _s cr ;
: ds prompt depth _s cr ;
: .h` ."free:" here H@ - $400/ .\ ."k_SC=" SC c@ . .s` ;
[ELSE]
: 2dump dup .l .":" dup 16+ -rot
  START >rswapr> = IF nip cr 2dump ;THEN >rswapr>
    dup 3& 0= drop IF space THEN space c@+ .b
  ENTER u<= UNTIL 2drop drop space ;
:. _s  1- 0; swap >r _s depth 0= drop IF space THEN r . r> ;
: .s` prompt 9 _s cr ;
: .h` ."free:" H@ here - 1024/ .\ ."k_SC=" SC@ . .s`
  anon@ 0- 0= IF drop H@ @ THEN  here over-
: dump bounds 2dump cr ;
[THEN]

\ --------------------------------------------------------------------
\ features -- buffer for tracking loaded features
variable features 100 allot
: append ( @ # c@ -- ) 2dup c@ + over 2>r c@+ + place drop 2r>
  2dup c! + 1+ 0 swap c! ;
: appendc ( c c@ -- ) tuck c@+ + tuck c! 0 over 1+ c! over- swap c! ;
: -v` ."\\ features: " features c@+ type cr ;

"locals" features append ;
[64] [IF]
\ move -- smart overlapping copy: src dst n --
: move >r 2dup u< 2drop IF r> cmove> ;THEN r> cmove ;

\ locals -- direct access to call stack cells and bulk data<->call transfers
\ r0/r0! alias r/r!; r1..r5 access deeper cells
\ 48895C24NN(mov [rsp+N],rbx) s08 XORs 5C->54 for rdx
\ 488B5C24NN(mov rbx,[rsp+N]) s08 XORs 5C->54 for rdx
: r0!`       $1C8948, s08. $24, ,1         drop` ;
: r1!`       $5C8948, s08. $24, ,1 $08, ,1 drop` ;
: r2!`       $5C8948, s08. $24, ,1 $10, ,1 drop` ;
: r3!`       $5C8948, s08. $24, ,1 $18, ,1 drop` ;
: r4!`       $5C8948, s08. $24, ,1 $20, ,1 drop` ;
: r5!`       $5C8948, s08. $24, ,1 $28, ,1 drop` ;
: r1`  over` $5C8B48, s08. $24, ,1 $08, ,1 ;
: r2`  over` $5C8B48, s08. $24, ,1 $10, ,1 ;
: r3`  over` $5C8B48, s08. $24, ,1 $18, ,1 ;
: r4`  over` $5C8B48, s08. $24, ,1 $20, ,1 ;
: r5`  over` $5C8B48, s08. $24, ,1 $28, ,1 ;
\ >>r ( xn..x1 n -- | == x1..xn ) move n items from data stack to call stack
\ 41FF37(push [r15])4D8D7F08(lea r15,[r15+8])
\ 48FFCB(dec rbx)75F4(jnz -12)
: >>r` under` 0-` 0>` IF`
  $37FF41, ,3 $087F8D4D, ,4 $CBFF48, ,3 $F475, ,2
  THEN` 2drop` ;
\ >>rr ( xn..x1 n -- | == xn..x1 ) move n items, reversed order on call stack
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
: +r` $E3C148, s01. $03, ,1 $DC0148, s08. drop` ;
\ -r ( n -- | == ?n..?1 ) reserve n uninitialized cells on call stack
\ shl rbx,3(48 C1 E3 03); sub rsp,rbx(48 29 DC)
: -r` $E3C148, s01. $03, ,1 $DC2948, s08. drop` ;
[ELSE]
\ 8B5804(mov ebx,[eax+0x4])
\ 8918(mov [eax],ebx) \ 895804(mov [eax+0x4],ebx)
: r0!` >C1    $1889, s08    drop` ;
: r1` over` $04588B, s08 ,1 ;
: r1!` >C1  $045889, s08 ,1 drop` ;
: r2` over` $08588B, s08 ,1 ;
: r2!` >C1  $085889, s08 ,1 drop` ;
: r3` over` $0C588B, s08 ,1 ;
: r3!` >C1  $0C5889, s08 ,1 drop` ;
: r4` over` $10588B, s08 ,1 ;
: r4!` >C1  $105889, s08 ,1 drop` ;
: r5` over` $14588B, s08 ,1 ;
: r5!` >C1  $145889, s08 ,1 drop` ;
\ 83E804(sub eax,4)8F00(pop dword[eax])4B(dec ebx)75F8(jnz -8)
: >>r` under` 0-` 0>` IF` $4E883, ,3 $1008F, ,2 $4B, s1 $F875, ,2 THEN` 2drop` ;
\ C1E302(shl ebx,2)01D8(add eax,ebx)
: +r` >C1 $02E3C1, s01 ,1 $D801, s08 drop` ;
\ 29D8(sub eax,ebx)
: -r` >C1 $02E3C1, s01 ,1 $D829, s08 drop` ;
\ C1E202(shl edx,2)29D0(sub eax,edx)
\ 8F00(pop dword[eax])83C004(add eax,4)4B(dec ebx)75F8(jnz -8)
: >>rr` dup` 0-` 0>` IF` $02E2C1, ,3 $D029, ,2
  $1008F, ,2 $4C083, ,3 $4B, ,1 $F875, ,2
  $D029, ,2 THEN` 2drop` ;
[THEN]
r` ' alias r0`
r0!` ' alias r!`
+r` ' alias xxr`

: fill rot rot BEGIN 0- 0> WHILE 1- -rot 2dup c! 1+ rot REPEAT drop 2drop ;
: erase 0 fill ;
: zlen ( addr -- addr len ) dup BEGIN dup c@ 0- 0<> WHILE drop 1+ REPEAT drop over - ;
\ --------------------------------------------------------------------
\ dictionary listing
: words` H@ START 2dup+ 1+ -rot type space ENTER h.sz+ c@+ 0- 0= UNTIL 2drop cr ;

\ dictionary inspector -- .hdr+ advances to next header
: .hdr+ dup .x\ .": " dup @ .x dup h.ct+ c@ .x h.sz+ c@+ 2dup type + 1+ ; \ addr -- next
: .hdrs H@ START .hdr+ cr ENTER dup h.sz+ c@ 0- 0= drop UNTIL drop ;
: .hdr .hdr+ cr drop ;

\ --------------------------------------------------------------------
\ hide private words
\ walk chain, remove pvt headers, reclaim space; pvtmargin stops walk
" hidepvt" features append ;
variable hide hide on
[64] [IF]
: h.next dup h.sz+ c@ h.nm+ 1+ + ;
:. _hdr_size h.sz+ c@ h.nm+ 1+ ;
:. _remove_hdr \ addr -- addr+sz
  dup _hdr_size
  >r dup H@ - H@
  swap H@ r + swap
  cmove>
  r> dup H +! + ;
:. _hidepvt hide@ 0; drop
  H@ BEGIN dup h.sz+ c@ 0- 0<> drop WHILE
    dup h.ct+ c@ dup $10& 0<> drop IF 2drop ;THEN
    8& 0<> drop IF _remove_hdr ELSE h.next THEN
  REPEAT drop ;
: hidepvt` _hidepvt ;
[THEN]

:^ hidestop 0<> IF dup CT_MGN- drop THEN ; \ ct -- ct ; at pvtmargin?
: xhidepvt` hide@ 0; drop   \ respect hide on/off
  \ hdrs grow down, H@ is most recent word at lowest address
  \ back over empty hdr, h.nm+1 bytes; set name size to 0 ( sentry H@ )
  H@ dup h.nm- 1- 0 over h.sz+ c! swap
  \ push the hfa, hdr field address, of each pvt word until the next margin ( sentry H@ p1@ p2@ ... pn@ )
  START over h.sz+ c@+ + 1+ -rot CT_PVT& 0= drop swap IF nip THEN
  ENTER dup h.ct+ c@ dup $ff- drop hidestop 0= UNTIL 2drop
  \ pop addresses and pack headers
  dup h.sz+ c@+ + 1+ >r START over h.sz+ c@+ + 1+ swap
    START 1- dupc@ r> 1- dup>r c! ENTER = UNTIL 2drop
  ENTER H@ h.nm- 1- = drop UNTIL drop r> H! ;
[32] [IF]
xhidepvt` ' alias hidepvt`
[THEN]

\ --------------------------------------------------------------------
\ dictionary state save/restore
\ _mark: restores here and H to the state when marker was created
\ r> gets return addr; -5 -> call insn; walks headers to find marker
:. _mark ;` r> 5- here - allot anon:`
  H@ BEGIN dup@ swap h.sz+ c@+ + 1+ swap here = 2drop UNTIL H! ;
\ mark` falls through to marker
: mark` ;` wsparse
: marker 2dup+ dupc@ >r dup>r '`' swap c! 1+
  here 0 header 2r> c!  _mark ' call, anon:` ;

: pad here 256+ ; \ scratch buffer, 256 bytes above here

[64] [IF]
\ --------------------------------------------------------------------
\ indexed stack access -- pick` peephole detects preceding literal
:. _pick_bb \ BB path: full DUP1, SB unchanged
  here 4- d@ -5 allot
  dup 0- 0= drop IF drop ;THEN
  1- 3 << $49 c, $8B c, $5F c, c, ;
:. _pick_6a \ 6A path: 7-byte DUP, SB toggled
  -3 allot here 1+ c@ 1- 0= IF drop ;THEN
  0< IF drop nipdup` ;THEN
  3 << $49 c, $5F8B, s08 c, ;
: pick`
  here 5- c@ $FE& $BA- 0= drop IF _pick_bb ;THEN
  here 3- c@ $6A- here 1- c@ $FE& $5A- | 0<> IF !"pick:_need_constant" ;THEN
  drop _pick_6a ;

: rp@` over` $E38948, s01. ;
: sp@` over` $FB894C, s01. ;
[ELSE]
: pick` \ xn..x0 n -- xn..x0 xn
  \ must be preceded by "52(push edx)6Axx(push byte)5A(pop edx)"
  here 4- @ $FE00FFFE& $5A006A52- 0<> IF !"is_not_preceded_by_a_constant" ;THEN
  drop -3 allot  here 1+ c@ 1- 0= IF drop ;THEN  \ "52(push edx)"=over` C=1
  0< IF drop swap` nipdup` ;THEN  \ i.e. dup`
  $5C8B, s08 10 << $24+ w, ;  \ 8B5C24xx(mov ebx,[esp+4n])
\ $89%11&sd(mov d,s) 0:eax 1:ecx 2:edx 3:ebx 4:esp 5:ebp 6:esi 7:edi
: rp@` over` $C389, s01 ;  \ 89C3(mov ebx,eax) -> 89D8(mov eax,ebx)
: sp@` over` $E389, s01 ;  \ 89E3(mov ebx,esp) -> 89DC(mov esp,ebx)
\ : rsp!` >C1 $D089DC89, s08 s08 2drop` ;  \ rp sp -- ; for multitasking
[THEN]
: 2over` 3 lit` pick` 3 lit` pick` ;

\ eval -- evaluate counted string as Forth source; saves/restores >in and tp
: eval >in@ tp@ 2>r over+ tp! >in! compiler 2r> tp! >in! ;

\ command-line arguments -- derived from CS0
: argc CS0@ @ ;
:. _argv 1+ cell* CS0@ + @ ;
: argv _argv zlen ;

\ boot sequence -- ossetup is a vector for platform-specific init
:^ ossetup ;

\ _auto -- auto-execute anonymous code if noauto is 0
:. _auto noauto@ 0- drop 0= IF >in@ -- ;` THEN ;

\ eval. -- evaluate with auto-execution
:. eval. >in@ tp@ 2>r over+ tp! >in! compiler _auto 2r> tp! >in! ;


\ --------------------------------------------------------------------
\ REPL coroutine -- _exec/_top form cross-word START...UNTIL loop
\ bye must follow _top: UNTIL falls through to bye on EOF
:. _back >in@ 1- dup BEGIN tib <> drop WHILE 1- dupc@ 10- drop 0= TILL 1+ END
   swap over- type ;
:. _eval eval. '
:. _exec catch 0;  _back ."_<-error:_" c@+ type cr  2drop
  anon@ 0- 0= IF drop H@ dup@ swap h.sz+ c@+ + 1+ H! THEN
  here - allot  0 SC c! anon:` 0<>`  START _eval ENTER
:^ _top pvt ui 0 noauto! tib 4096 under accept 0- 0= UNTIL
: bye` ;` cr 0 exit ;
:^ doargv argc 1- 0; 1 _argv swap 2+ _argv over- tuck tib place swap _eval ;
fflin2.boot
:. _boot ossetup _postboot _top ;
_boot ' _bootxt! _boot ' >r ;
