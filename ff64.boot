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
: nipdup` $48, ,1 $DA89, s09 ;
: drop` swap` nip` ;
: dup` under` nipdup` ;
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
: 2dup!` $48, ,1 $1389, s09 ;
: 2dupc!` $1388, s09 ;
: 2dupw!` $66, ,1 $1389, s09 ;
: 2dup+!` $48, ,1 $1301, s09 ;
: 2dup-!` $48, ,1 $1329, s09 ;
\ Consuming store ops
: tuck!` 2dup!` nip` ;
: !` tuck!` drop` ;
: tuckc!` 2dupc!` nip` ;
: c!` tuckc!` drop` ;
: tuckw!` 2dupw!` nip` ;
: w!` tuckw!` drop` ;
: tuck+!` 2dup+!` nip` ;
: +!` tuck+!` drop` ;
: tuck-!` 2dup-!` nip` ;
: -!` tuck-!` drop` ;
: over!` swap` tuck!` ;
: overc!` swap` tuckc!` ;
: overw!` swap` tuckw!` ;
: over+!` swap` tuck+!` ;
: over-!` swap` tuck-!` ;

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

\ Shift ops
: <<` $48, ,1 $D989, s08 $48, ,1 $E2D3, s01 drop` ;
: >>` $48, ,1 $D989, s08 $48, ,1 $EAD3, s01 drop` ;

\ Compilation helpers
: here` over` $48, ,1 $EB89, s01 ;
: allot` $48, ,1 $DD01, s08 drop` ;

\ Compilation emit: store value at [rbp] and advance rbp
\ c,` ( n -- ): store byte, advance 1
: c,` $5D88, s08 $00, ,1 $C5FF48, ,3 drop` ;
\ w,` ( n -- ): store 16-bit word, advance 2
: w,` $66, ,1 $5D89, s08 $00, ,1 $02C58348, ,4 drop` ;
\ ,` ( n -- ): store 64-bit cell, advance 8
: ,` $48, ,1 $5D89, s08 $00, ,1 $086D8D48, ,4 drop` ;

\ Composed operations
: 2dup` over` over` ;
: 3dup` 2dup` $F87F8D4D, ,4 $18478B49, ,4 $078949, ,3 ;
: 2drop` drop` drop` ;
: 2dup+` over` over+` ;
: 2r>` 2dup` dropr>` swap` dropr>` swap` ;
: 2dup>r` swap` dup>r` swap` dup>r` ;
: 2>r` 2dup>r` 2drop` ;

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

( Flow control — Forth-defined, replacing assembly )
( ? exposes the cond_jmp byte used by FLAGS-based conditions )
: d, here d! 4 allot ;
: cond ? c@ 0 ? c! 1 xor ;
: IF` >S0 cond $0F c, $10 + c, here 4 allot ;
: THEN` >S0 here over - 4 - swap d! ;
: BEGIN` >S0 here ;
: AGAIN` >S0 $E9 c, dup here 4 + - d, drop ;
: UNTIL` >S0 cond $0F c, $10 + c, dup here 4 + - d, drop ;
: WHILE` IF` ;
: REPEAT` swap AGAIN` THEN` ;
: TIMES` >r` >S0 here $48 c, $FF c, $0C c, $24 c, $0F c, $88 c, here 4 allot ;
: LOOP` >S0 swap AGAIN` THEN` rdrop` ;

( Stack manipulation )
: 2swap rot >r rot r> ;
: ?dup 0- 0<> IF dup THEN ;

( Arithmetic )
: abs 0- 0< IF negate THEN ;
: max > IF swap THEN nip ;
: min < IF swap THEN nip ;

( Output )
: ? @ . ;
: on -1 swap ! ;
: off 0 swap ! ;
: space $20 emit ;
: spaces BEGIN 0- 0> WHILE space 1 - REPEAT drop ;
: type BEGIN 0- 0> WHILE swap dup c@ emit 1 + swap 1 - REPEAT 2drop ;
: count dup 1 + swap c@ ;

( Memory )
: fill rot rot BEGIN 0- 0> WHILE 1 - -rot 2dup c! 1 + rot REPEAT drop 2drop ;
: erase 0 fill ;

( Flow control macros — composable backtick versions )
: ;;` >S0 $C3, ,1 ;
: ;THEN` ;;` THEN` ;
: 0;` 0-` 0=` IF` drop` ;THEN` ;
: 0<>;` 0-` 0<>` IF` drop` ;THEN` ;
: ?dup` 0-` 0<>` IF` dup` THEN` ;
: BOOL` 0 lit` IF` ~` THEN` ;
: SKIP` >S0 $E9, ,1 here 4 allot ;
: ELSE` SKIP` swap THEN` ;
: CASE` =` drop` IF` drop` ;

( Inline macros — miscellaneous )
\ reverse` pops return address and calls it (turns call into jmp)
: reverse` $D1FF59, ,3 ;

( Utilities )
: bl $20 ;
: noop ;

( Boolean constants )
-1 constant TRUE
0 constant FALSE

( Header layout constants )
8 constant h.ct
9 constant h.sz
10 constant h.nm

( Dictionary access )
: H@ H @ ;
: anon@ anon @ ;
: ct|! 8 + dupc@ rot | swap c! ;
: pvt` 8 H@ ct|! ;

( Dictionary operations )
: execute >r ;
: :.` :` pvt` ;
: _alias H@ ! $20 H@ ct|! anon:` ;
: alias` :` _alias ;
: constant` :` 1 H@ ct|! H@ ! anon:` ;

( Bracket state switching )
: [` anon@ SC c@ anon:` ;
: ]` 2>r ;` 2r> SC c! anon ! ;

( Number output )
variable base
10 base ! ;
: base@ base @ ;
: base! base ! ;
:. _d tuck 0 swap m/mod 0- 0= IF drop nip ;THEN rot _d
: .digit $30 + $39 u> drop IF 39 + $7A u> drop IF drop $3F THEN THEN emit ;
: .ub\ _d .digit ;
: .ub .ub\ space ;
:. .sign 0- 0< IF $2D emit negate THEN ;
: .\ .sign base@ .ub\ ;
: . .\ space ;
: .dec\ .sign 10 .ub\ ;
: .dec .dec\ space ;
: .u\ base@ .ub\ ;
: .u .u\ space ;
: .ux\ $10 .ub\ ;
: .ux .ux\ space ;
: .x\ .sign $10 .ub\ ;
: .x .x\ space ;

( Hex digit output — .#s prints N hex digits of a value )
: .#s TIMES dup r@ 4* >> $F and .digit LOOP drop ;
: .b 2 .#s ;
: .w 4 .#s ;

( Dictionary listing )
: h.next dup h.sz + c@ h.nm + 1 + + ;
: h.name dup h.nm + over h.sz + c@ type space ;
: words H@ BEGIN dup h.sz + c@ 0- 0<> drop WHILE h.name h.next REPEAT drop cr ;
