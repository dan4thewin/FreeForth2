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
: <<` $D989, s08 $48, ,1 $E2D3, s01 drop` ;
: >>` $D989, s08 $48, ,1 $EAD3, s01 drop` ;

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
\ d,` ( n -- ): store 32-bit dword, advance 4
: d,` $5D89, s08 $00, ,1 $04C58348, ,4 drop` ;

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
: d, here d! 4 allot ;
: cond ?# c@ 0 ?# c! 1 xor ;
: IF` >S0 cond $0F c, $10+ c, here 4 allot ;
: THEN` >S0 here over - 4- swap d! 0 callmark! ;
: BEGIN` >S0 here ;
: AGAIN` >S0 $E9 c, dup here 4+ - d, drop ;
: UNTIL` >S0 cond $0F c, $10+ c, dup here 4+ - d, drop ;
: WHILE` IF` ;
: REPEAT` swap AGAIN` THEN` ;
: TIMES` >r`
: RTIMES` >S0 here $48 c, $FF c, $0C c, $24 c, $0F c, $88 c, here 4 allot ;
: LOOP` >S0 swap AGAIN` THEN` rdrop` ;

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
: s>d` dup` $FBC148, ,3 $3F, ,1 s01 ;
: adc` $48, ,1 $D311, s09 nip` ;
: dnegate` ~` swap` negate` swap` ;
: dabs` 0-` 0<` IF` dnegate` THEN` ;
: d+` >r` rot` +` swap` r>` adc` ;

( Output )
: on -1 swap ! ;
: off 0 swap ! ;
: space $20 emit ;
: spaces BEGIN 0- 0> WHILE space 1- REPEAT drop ;
: type BEGIN 0- 0> WHILE swap dup c@ emit 1+ swap 1- REPEAT 2drop ;
: count dup 1+ swap c@ ;

( Memory )
: fill rot rot BEGIN 0- 0> WHILE 1- -rot 2dup c! 1+ rot REPEAT drop 2drop ;
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

\ Tail-call optimization: redefine ;;` now that IF/ELSE/THEN are available
: ;;` >S0 callmark@ here - 0= drop IF $E9 callmark@ 5- c! ELSE $C3, ,1 THEN ;
: ;THEN` ;;` THEN` ;
: _pick_detect
  here 5- c@ $BB = IF here 4- d@ -5 allot ;THEN
  here 3- c@ $6A- here 1- c@ $FE& $5A- or 0<> IF !"not_preceded_by_constant" ;THEN
  here 2- c@ -3 allot swap` $48 c, $DA89 w, s09 ;
: pick` _pick_detect
  dup 0- 0= IF drop ;THEN
  1- 3 << $49 c, $8B c, $5F c, c, ;
: 2over` 3 lit` pick` 3 lit` pick` ;

( Inline macros — miscellaneous )
\ reverse` pops return address and calls it (turns call into jmp)
: reverse` $D1FF59, ,3 ;

( Forward jump resolution helper )
\ _then ( addr -- ) patches a forward jmp's rel32 at addr to target here
: _then here over - 4 - swap d! ;

( Advanced loop infrastructure: START/ENTER/BREAK/END )
\ Structured loop with optional first-entry skip.
\
\ mrk is a 2-cell compiler variable:
\   cell 0: loop body address (backward jump target for END)
\   cell 1: SC state at loop start
\ START/END/BREAK use a separate compile-time stack (cstack) for
\ saved mrk values and break addresses, keeping the data stack clean.
\ This is critical for the _exec pattern where START _eval ENTER
\ has no matching END — an unterminated START must not pollute
\ the data stack.
\
\ >cs ( x -- ) pushes to compile-time stack
\ cs> ( -- x ) pops from compile-time stack
\
\ START ( -- ) opens a structured loop. Saves old mrk (2 cells) and
\   a 0 break-sentinel onto the compile-time stack. Compiles a forward
\   E9 jmp (patched by ENTER if used). Stores loop body addr in mrk[0].
\
\ ENTER ( -- ) resolves START's forward jmp to target here.
\
\ BREAK ( -- ) compiles a forward E9 out of the loop. Pushes the
\   rel32 address onto the compile-time stack. Resolves preceding IF.
\
\ END ( -- ) closes the loop: compiles backward E9 to mrk[0].
\   Pops and resolves break addresses from compile-time stack
\   until it hits the 0 sentinel. Restores mrk.
variable mrk 0 mrk 8+ !
: align` $90909090, here negate 3& allot ;
: START` mrk 2@ >cs >cs 0 >cs $E9 c, 0 d, here mrk! ;
: ENTER` >S0 mrk@ 4- _then ;
: TILL` >S0 cond $0F c, $10+ c, mrk@ here 4+ - d, ;
: BREAK` >S0 $E9 c, 0 d, here 4- >cs _then ;
: _resolve_breaks cs> 0; _then _resolve_breaks ;
: END` >S0 $E9 c, mrk@ here 4+ - d, _resolve_breaks cs> cs> mrk 2! ;

( Dotted conditionals: for stack-boolean values instead of FLAGS )
: cond.` 0-` drop` 0<>` ;
: IF.` cond.` IF` ;
: WHILE.` cond.` WHILE` ;
: TILL.` cond.` TILL` ;
: UNTIL.` cond.` UNTIL` ;

( Utilities )
: bl $20 ;
: noop ;

( Boolean constants )
-1 constant TRUE
0 constant FALSE

( FLAGS helpers — set FLAGS from known values )
: zFALSE 0 0- drop ;
: nzTRUE 1 0- drop ;

( Header layout constants )
8 constant h.ct
9 constant h.sz
10 constant h.nm

( Dictionary access )
: ct|! 8+ dupc@ rot | swap c! ;
: pvt` 8 H@ ct|! ;

( Dictionary operations )
: execute >r ;
: :.` :` pvt` ;
: create` :` 1 H@ ct|! anon:` ;
: variable` create` 0 , anon:` ;
: pvtmargin $10 H@ ct|! ;

( Vector words — :^ creates push/ret preamble, 6 bytes )
( Vector xt layout: $68 <target32> $C3 <body...> )
( target32 at xt+1 is sign-extended to 64-bit by push )
: :^` :` $68, ,1 here 4+ 1+ d, $C3, ,1 ;
:. -c here dup 4- d@ + -5 allot 0 callmark! ;
: -call callmark@ here = 2drop IF -c ELSE drop THEN ;
: @^ ( xt -- target ) 1+ d@ ;
: !^ ( new-target xt -- ) 1+ d! ;
: n^ ( xt -- ) dup 6+ swap 1+ d! ;
: x^ ( xt -- ) 6+ >r ;
: '` -call lit` ;
( ?` converts preceding call to conditional jump )
:. _?` ?# c@ 0 ?# c! dup 0- 0= drop IF drop $75 THEN
  $0F c, $10+ c, dup here 4+ - d, drop ;
: ?` -call 0; _?` ;

( Range check — uses FLAGS tail-call pattern )
: within over- -rot - u> 2drop nzTRUE ? zFALSE ;

: _alias H@ ! $20 H@ ct|! anon:` ;
: alias` :` _alias ;
: constant` :` 1 H@ ct|! H@ ! anon:` ;

( Bracket state switching )
: [` anon@ SC c@ anon:` ;
: ]` 2>r ;` 2r> SC c! anon! ;

( Number output )
variable base
10 base! ;
:. _d tuck 0 swap m/mod 0- 0= IF drop nip ;THEN rot _d
: .digit $30+ $39 u> drop IF 39+ $7A u> drop IF drop $3F THEN THEN emit ;
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
: h.next dup h.sz+ c@ h.nm+ 1+ + ;
: h.name dup h.nm+ over h.sz+ c@ type space ;
: words H@ BEGIN dup h.sz+ c@ 0- 0<> drop WHILE h.name h.next REPEAT drop cr ;

( Debug output — .s` shows compile-time stack, ds shows runtime stack )
:^ ui : prompt space depth .\ ';' anon@ 0- 0= drop IF 1- THEN emit space ;
:. _s 0; depth 2 < drop IF drop ;THEN drop 1- swap >r _s r@ . r> ;
: .s` prompt depth _s cr ;
: ds prompt depth _s cr ;
: .h` ."free:" here H@ - $400/ .\ ."k_SC=" SC c@ . .s` ;
: .l 8 .#s ;

( Pictured numeric output — ANS-style <# # #s hold sign #> )
( Builds a number string right-to-left in pnbuf )
46 constant pnmaxlen
create pnbuf pvt pnmaxlen 2+ allot
: <# pnmaxlen pnbuf c! 0 pnbuf pnmaxlen+ 1+ c! ; <#
: #> 2drop pnbuf c@+ swap over + swap pnmaxlen swap - ;
:. _len1- pnbuf dupc@ 1- swap c! ;
: hold pnbuf dupc@ + c! _len1- ;
:. _dh 9 u> drop IF over+ THEN nip $30+ $7A u> drop IF drop $3F THEN hold ;
:. _# >r um/mod r> rot _dh 0 ;
: # base@ 7 _# ;
: x# $10 39 _# ;
: X# $10 7 _# ;
:. _ps >r BEGIN r@ execute over 0- drop 0= UNTIL rdrop ;
: #s # ' _ps ;
: x#s x# ' _ps ;
: X#s X# ' _ps ;
: sign 0- drop 0< IF $2D hold THEN ;

( Dictionary inspector )
: .hdr+ dup .x\ .":_" dup @ .x space dup h.ct+ c@ .x space dup h.sz+ c@ . dup h.name ;
: .hdrs H@ BEGIN dup h.sz+ c@ 0- 0<> drop WHILE .hdr+ cr h.next REPEAT drop ;
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
: marker 2dup + dup c@ >r dup >r $60 swap c! 1+
  here 0 header 2r> c! _mark ' call, anon:` ;
: mark` ;` wsparse marker ;

( I/O constants )
0 constant stdin
1 constant stdout
2 constant stderr

( noauto — variable controlling auto-semicolon in REPL )
( When 0, typed lines auto-execute via _auto calling ; )
variable noauto pvt

( eval — evaluate a counted string as Forth source )
( Saves >in and tp, sets new parsing bounds, calls compiler, restores. )
: eval >in@ tp@ 2>r over + tp! >in! compiler 2r> tp! >in! ;

( _auto — auto-execute anonymous code if noauto is 0 )
( Called after compiler returns in eval. Decrements >in and calls ; )
:. _auto noauto@ 0- drop 0= IF >in@ 1- >in! ;` THEN ;

( eval. — evaluate with auto-execution )
( Like eval but calls _auto to execute the compiled code )
:. eval. >in@ tp@ 2>r over + tp! >in! compiler _auto 2r> tp! >in! ;

( _eval — evaluate and get result xt via tick )
:. _eval eval. '

( key — read a single character from stdin )
: key tib 1 accept drop tib c@ ;

( type — output a counted string: addr len -- )
: type stdout write drop ;

( Hide private words — zero the first name byte of pvt-marked headers )
( Stops at pvtmargin. Does not compact memory. )
( hidepvt` is a compile-time macro; _hidepvt is the runtime callable version )
variable hide hide on
:. _hidepvt hide@ 0; drop
  H@ BEGIN dup h.sz+ c@ 0- 0<> drop WHILE
    dup h.ct+ c@ dup $10& 0<> drop IF 2drop ;THEN
    8& 0<> drop IF 0 over h.nm+ c! THEN
    h.next
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
  tib 80 accept dup 0- 0= drop IF drop 0 exit THEN
  here saved_here! tib swap eval. ' catch dup 0- 0<> drop IF _recover ELSE drop THEN
AGAIN

( Command-line arguments — ff_argc and ff_argv set by assembly at startup )
: argc ff_argc@ ;
:. _argv 8* ff_argv@ + @ ;
: argv _argv zlen ;

( Hex memory dump )
: dump bounds dup .l .":" BEGIN space c@+ .b 2dup u<= UNTIL 2drop cr ;

( Peephole: >mov replaces variable fetch with inc/dec for ++`/--` )
: >mov here 7- c@ $48- here 6- c@ $8B- or drop
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
1 constant [1]`
0 constant [0]`

( Call `hidepvt` at compile time, or `_boot ;` for full boot sequence )
:^ ossetup ;
:. _boot ossetup _hidepvt _top ;
