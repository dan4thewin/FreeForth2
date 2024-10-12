: dup` under`
: nipdup` $DA89, s09 ;
: tuck` swap` over` ;
: r>` over`
: dropr>` >C0 $5B, s1 ;
: dup>r` >C0 $53, s1 ;
: >r` dup>r` drop` ;

: here` over` $EB89, s01 ;
: allot` $DD01, s08 drop` ;
: ,3` $036D8D, ,"^M~m^C" ;
: ,4` $046D8D, ,3 ;
: ,2` $026D8D, ,3 ;
: ,1` $45, ,"E" ;
: c,` $45005D88, s08 ,2 drop` ;
: ,` $FF005D89, s08 ,1 ,4` drop` ;
: w,` $005D8966, ,1 s08 ,1 ,2` drop` ;
: 2r` over` $04588B, s08 ,1
: r` over` $188B, s08 ;
: rdrop` $04C483, c04 ,1 ;
: 2rdrop` $08C483, c04 ,1 ;
: -rot` swap`
: >rswapr>` $201487, s08 -1 allot c04 ;
: rot` >rswapr>` swap` ;
: 2xchg` swap` >rswapr>` swap` ;

: ~` $D3F7, s01 ;
: negate` $DBF7, s01 ;
: bswap` $CB0F, s01 ;
: flip`  $FB86, s09 ;
: over&` $D321, s09 ;
: over|` $D309, s09 ;
: over^` $D331, s09 ;
: over+` $D301, s09 ;
: over-` $D329, s09 ;
: over*` $DAAF0F, ,1 s09 ;
: /%` >S0 $99D08950, ,4 $C389FBF7, ,4 $58, ,1 ;
: 1-` $4B, s1 ;
: 1+` $43, s1 ;
: 2+` 1+` 1+` ;
: 4+` $04C383, s01 ,1 ;
: 2*` $E3D1, s01 ;
: 2/` $FBD1, s01 ;
: 4*` $02E3C1, s01 ,1 ;
: 4/` $02FBC1, s01 ,1 ;
: 8*` $03E3C1, s01 ,1 ;
: 8/` $03FBC1, s01 ,1 ;
: <<` $E2D3D989, s08 s01 drop` ;
: >>` $EAD3D989, s08 s01 drop` ;
: @` $1B8B, s09 ;
: c@` $1BB60F, ,1 s09 ;
: cs@` $1BBE0F, ,1 s09 ;
: w@` $1BB70F, ,1 s09 ;
: ws@` $1BBF0F, ,1 s09 ;
: dup@`  over` $1A8B, s09 ;
: dupc@` over` $1AB60F, ,1 s09 ;
: dupw@` over` $1AB70F, ,1 s09 ;
: 2dupw!` $66, ,1
: 2dup!`  $1389, s09 ;
: 2dupc!` $1388, s09 ;
: 2dup+!` $1301, s09 ;
: 2dup-!` $1329, s09 ;
: place` $D189DF89, s08 s08 >C1 $5AA4F35E, ,3 s1 ;
: cmove` swap` place` drop` ;

: &` over&` nip` ;
: |` over|` nip` ;
: ^` over^` nip` ;
: +` over+` nip` ;
: -` swap` over-` nip` ;
: *` over*` nip` ;
: /` /%` nip` ;
: %` /%` drop` ;
: 2dup+` over` over+` ;

: over!`  swap` : tuck!`  2dup!`  nip` ; : !`  tuck!`  drop` ;
: overw!` swap` : tuckw!` 2dupw!` nip` ; : w!` tuckw!` drop` ;
: overc!` swap` : tuckc!` 2dupc!` nip` ; : c!` tuckc!` drop` ;
: over+!` swap` : tuck+!` 2dup+!` nip` ; : +!` tuck+!` drop` ;
: over-!` swap` : tuck-!` 2dup-!` nip` ; : -!` tuck-!` drop` ;

:  @+` dup@`  swap` 4+` swap` ;
: w@+` dupw@` swap` 2+` swap` ;
: c@+` dupc@` swap` 1+` swap` ;
: 2@` @+` swap` @` swap` ;
: 2!` tuck!` 4+` !` ;
: off` 0 lit` swap` !` ;
: on` -1 lit` swap` !` ;

: 2dup` over` over` ;
: 3dup` 2dup` $082474FF, ,4 ;
: 2r>` 2dup` dropr>` swap` dropr>` swap` ;
: 2dup>r` swap` dup>r` swap` dup>r` ;
: 2>r` 2dup>r`
: 2drop` drop` drop` ;
: 2swap` rot` >r` rot` r>` ;
: bounds` over+` swap` ;

: :.` :`
: pvt` 8 H@
: ct|! h.ct+ dupc@ rot | swap c! ;
: alias` :`
:. _alias H@ ! $20 H@ ct|! anon:` ;
: create` :` 1 H@ ct|! anon:` ;
: variable` create` 0 , anon:` ;
: constant` create` _alias ;
: :^` :` $68, ,1 here 5+ , $C3, ,1 ;

: [` anon@ SC c@  anon:` ;
: ]` 2>r ;` 2r> :. _] SC c! anon! ;
: execute >r ;
: reverse` $D1FF59, ,3 ;

:. _m/mod >S0 >C1 $240487, ,3 w, $58C389, ,3 ;
: m/mod`  $FBF7 _m/mod ;
: um/mod` $F3F7 _m/mod ;
:. _m* >S0 $D089C189, ,4 w, $D389, ,2 $C889C289, ,4 ;
: m*`  $EBF7 _m* ;
: um*` $E3F7 _m* ;
: */mod` >r` m*` r>` m/mod` ;
: */` */mod` nip` ;

variable noauto pvt
: \` 2 >in -! lnparse 2drop 1 noauto! ;
: (` ')' parse 2drop ;
: EOF` tp@ >in! ;` ;

variable ?#
: 0-` $DB09, s09 ;
:. _?1 ?# c! ;
:. _?1a. $C931, ,2 ;
:. _?1b. 1^ $20+ 8 << $49C1000F | , $CB89, ,1 s1 ;
:. _?1. _?1a. 0-` _?1b. ;
:. _?2 _?1 $DA39, s09 ;
:. _?2. _?1a. $DA39, s09 _?1b. nip` ;
$74 dup : 0=`  lit _?1 ; dup : 0=.`  lit _?1. ; dup : =`  lit _?2 ; : =.`  lit _?2. ;
$75 dup : 0<>` lit _?1 ; dup : 0<>.` lit _?1. ; dup : <>` lit _?2 ; : <>.` lit _?2. ;
$7C dup : 0<`  lit _?1 ; dup : 0<.`  lit _?1. ; dup : <`  lit _?2 ; : <.`  lit _?2. ;
$7D dup : 0>=` lit _?1 ; dup : 0>=.` lit _?1. ; dup : >=` lit _?2 ; : >=.` lit _?2. ;
$7E dup : 0<=` lit _?1 ; dup : 0<=.` lit _?1. ; dup : <=` lit _?2 ; : <=.` lit _?2. ;
$7F dup : 0>`  lit _?1 ; dup : 0>.`  lit _?1. ; dup : >`  lit _?2 ; : >.`  lit _?2. ;
$72 dup : C1?` lit _?1 ; : C1?.` lit _?1. ;
$73 dup : C0?` lit _?1 ; : C0?.` lit _?1. ;
$72 dup : u<`  lit _?2 ; : u<.`  lit _?2. ;
$73 dup : u>=` lit _?2 ; : u>=.` lit _?2. ;
$76 dup : u<=` lit _?2 ; : u<=.` lit _?2. ;
$77 dup : u>`  lit _?2 ; : u>.`  lit _?2. ;
:. -c` here dup 4- @ + -5 allot 0 callmark! ;
:. -js c, c, ;
:. -jc $0F, ,1 $12+ swap 1- swap
:. -ju 2- c, 3- , ;
:. ?@ ?# c@ 0 ?#! ;
:. _?` ?@ 0- ,"u^C" $75_ swap
:. -j here 2+ - -$80 >= drop swap -js [ -c` 1 here +! ] _?
  $EB = drop -ju -c _? -jc ;
:^ -call callmark@ here = 2drop -c` -c _? !"is_not_preceded_by_a_call"
: ?` -call _?` ;
: '` -call lit` ;
: lib:` :` #lib lit` #fun ' call, ;` ;
: fun:` :` lit` lit` #call ' call, ;` ;

:. _off !"jump_off_range"
:. ?off dup 2* over^ -$100& drop _off ? ;
:. ?nn 0- ,"t^AC~" !"is_not_preceded_by_a_condition"
: cond ?@ ?nn 1^ ;
: cond. 0-` drop` 0<>` ;
:. SC, here SC c@ c, ;
: IF.` cond.
: IF` cond c, SC, ;
: SKIP` $EB c, SC, ;
: ELSE` SKIP` swap dupc@ SC c!
: THEN` dupc@ >SC
:. _then here over- 1- ?off swap c! 0 callmark! ;
: 0;` 0-` 0=` IF` drop`
: ;THEN` ;;` dupc@ SC c! _then ;
: 0<>;` 0-` 0<>` IF` drop` ;THEN` ;
: ?dup` 0-` 0<>` IF` dup` THEN` ;
: BOOL` 0 lit` IF` ~` THEN` ;
: zFALSE 0 0- drop ;
: nzTRUE 1 0- drop ;
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
: CASE` =` drop` IF` drop` ;
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

: @^` -call over` $1D8B, s08 1+ , ;
: ^^` -call $05C7, ,2 dup 1+ , 6+ , ;
:. nop ;
: n^` -call nop ' lit` SKIP
: !^` -call THEN $1D89, s08 1+ , drop` ;
: x^` -call 6+ dcall, ;

: s>d` dup` 0<.` ;
: abs`  0-` 0<` IF` negate` THEN` ;
: dnegate` ~` swap` negate` swap` ;
: dabs` 0-` 0<` IF` dnegate` THEN` ;
: adc` $D311, s09 nip` ;
: d+` >r` rot` +` swap` r>` adc` ;

:. mov? here 6- c@ $8b- 0; !"is_not_preceded_by_a_mov" ;
:. dst? here 5- c@ $15- 0; $8- 0; !"destination_is_not_edx_or_ebx" ;
:^ >mov mov? dst? $90 here 7- c! here 6- w! ;
: ++` $5FF >mov swap` ;
: --` $DFF >mov swap` ;

:. _[] '[' parse 2drop wsparse  0- 0= drop IF drop >in! !"unbalanced" ;THEN
  1 >in -! dup "ELSE]" $- 0<> drop IF dup "THEN]" $- 0<> drop IF "IF]" $- drop _[] ?
  BEGIN _[] 0<> UNTIL _[] ;THEN 1+ THEN drop ;
: [IF]` 0- 0= drop IF
: [ELSE]` >in@ _[] drop
: [THEN]` THEN ;
: [~]` wsparse find nip ;
1 constant [1]`
0 constant [0]`

variable io pvt
: key io 1 under accept drop c@ ;
: space 32
:^ putc : emit io 2dupc! swap 1_ type ;
:^ cr ."^J" ;

variable base 10 base!
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
: .x\ .sign 9 > drop IF '$' putc THEN $10 .ub\ ;
: .x .x\ space ;
: .b 2
: .#s TIMES dup r 4* >> $F& .digit REPEAT drop ;
: .w 4 .#s ;
: .l 8 .#s ;
: 2dump dup .l .":" dup 16+ -rot
  START >rswapr> = IF nip cr 2dump ;THEN >rswapr>
    dup 3& 0= drop IF space THEN space c@+ .b
  ENTER u<= UNTIL 2drop drop space ;
:^ ui : prompt space depth .\ ';' anon@ 0- 0= drop IF 1- THEN emit space ;
:. _s  1- 0; swap >r _s depth 0= drop IF space THEN r . r> ;
: .s` prompt 9 _s cr ;
: .h` ."free:" H@ here - 1024/ .\ ."k_SC=" SC@ . .s`
  anon@ 0- 0= IF drop H@ @ THEN  here over-
: dump bounds 2dump cr ;

: words` H@ START 2dup+ 1+ -rot type space ENTER h.sz+ c@+ 0- 0= UNTIL 2drop cr ;
: .hdr+ dup .x\ .": " dup @ .x dup h.ct+ c@ .x h.sz+ c@+ 2dup type + 1+ ;
: .hdrs H@ START .hdr+ cr ENTER dup h.sz+ c@ 0- 0= drop UNTIL drop ;
: .hdr .hdr+ drop ;
variable hide hide on
:^ hidestop 0<> IF dup $10- drop THEN ;
: hidepvt` hide@ 0; drop H@ 0 over 2- c! dup h.nm- 1- swap
  START over h.sz+ c@+ + 1+ -rot 8& 0= drop swap IF nip THEN
  ENTER dup h.ct+ c@ dup $ff- drop hidestop 0= UNTIL 2drop
  dup h.sz+ c@+ + 1+ >r START over h.sz+ c@+ + 1+ swap
    START 1- dupc@ r> 1- dup>r c! ENTER = UNTIL 2drop
  ENTER H@ h.nm- 1- = drop UNTIL drop r> H! ;
:. _mark ;` r> 5- here - allot anon:`
  H@ BEGIN dup@ swap h.sz+ c@+ + 1+ swap here = 2drop UNTIL H! ;
: mark` ;` wsparse
: marker 2dup+ dupc@ >r dup>r '`' swap c! 1+
  here 0 header 2r> c!  _mark ' call, anon:` ;
: pvtmargin $10 H@ ct|! ;
: eval >in@ tp@ 2>r over+ tp! >in! compiler 2r> tp! >in! ;

: argc CS0@ @ ;
:. _argv 1+ 4* CS0@ + @ ;
: argv _argv zlen ;
:^ ossetup ;
:. _back >in@ 1- dup BEGIN tib <> drop WHILE 1- dupc@ 10- drop 0= TILL 1+ END
   swap over- type ;
:. _auto noauto@ 0- drop 0= IF >in@ -- ;` THEN ;
:. eval. >in@ tp@ 2>r over+ tp! >in! compiler _auto 2r> tp! >in! ;
:. _eval eval. '
:. _exec catch 0;  _back ."_<-error:_" c@+ type cr  2drop
  anon@ 0- 0= IF drop H@ dup@ swap h.sz+ c@+ + 1+ H! THEN
  here - allot  0 SC c! anon:` 0<>`  START _eval ENTER
:^ _top pvt ui 0 noauto! tib 1024 under accept 0- 0= UNTIL
: bye` ;` cr 0 exit ;
: help` !"Can't_find_file_ff.ff_needed_for_help!"
:^ doargv argc 1- 0; 1 _argv swap 2+ _argv over- tuck tib place swap _eval ;
:. _boot ossetup doargv _top ;
_boot ' _bootxt! ;
