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
: m/mod` >S0 >C1 $F7240487, ,4 $58C389FB, ,4 ;
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
: w@` $1BB70F, ,1 s09 ;
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
: 2r>` 2dup` dropr>` swap` dropr>` swap` ;
: 2>r` swap` dup>r` swap` dup>r`
: 2drop` drop` drop` ;
: 2swap` rot` >r` rot` r>` ;
: bounds` over+` swap` ;

: \` 2 >in -! lnparse 2drop ;
: (` ')' parse 2drop ;
: EOF` tp@ >in! ;` ;

: [` anon@ SC c@  anon:` ;
: ]` 2>r ;` 2r> : `] SC c! anon! ;
: execute >r ;
: reverse` $D1FF59, ,3 ;

: alias` :`
: `alias H@ ! anon:` ;
: create` :` 1 H@ 4+ c! anon:` ;
: variable` create` 0 , anon:` ;
: constant` create` `alias ;
: :^` :` $68, ,1 here 5+ , $C3, ,1 ;

variable `?#
: 0-` $DB09, s09 ;
: 0=` $74 : `?1 `?# c! ;
: 0<>` $75 `?1 ;
: 0<` $7C `?1 ;
: 0>=` $7D `?1 ;
: 0<=` $7E `?1 ;
: 0>` $7F `?1 ;
: C1?` $72 `?1 ;
: C0?` $73 `?1 ;
: u<` $72 : `?2 `?1 $DA39, s09 ;
: u>=` $73 `?2 ;
: =` $74 `?2 ;
: <>` $75 `?2 ;
: u<=` $76 `?2 ;
: u>` $77 `?2 ;
: <` $7C `?2 ;
: >=` $7D `?2 ;
: <=` $7E `?2 ;
: >` $7F `?2 ;
: `?@ `?# c@ : 0?1 0 `?#! ;
: `-c` here dup 4- @ + -5 allot 0 callmark! ;
: `-js c, c, ;
: `-jc $0F, ,1 $12+ swap 1- swap
: `-ju 2- c, 3- , ;
: `?` `?@ 0- ,"u^C" $75_ swap
: `-j here 2+ - -$80 >= drop swap `-js [ `-c` 1 here +! ] `?
  $EB = drop `-ju `-c `? `-jc ;
: -call callmark@ here = 2drop `-c` `-c `? !"is_not_preceded_by_a_call"
: ?` -call `?` ;
: '` -call lit` ;
: @^` -call over` $1D8B, s08 1+ , ;
: !^` -call $1D89, s08 1+ , drop` ;
: ^^` -call $05C7, ,2 dup 1+ , 6+ , ;
: n^` -call $05C7, ,2 , $441F0F , ;
: lib:` :` #lib lit` #fun ' call, ;` ;
: fun:` :` lit` lit` #call ' call, ;` ;

: `off !"jump_off_range"
: `?off dup 2* over^ -$100& drop `off ? ;
: `?nn 0- ,"t^AC~" !"is_not_preceded_by_a_condition"
: `cond `?@ `?nn 1^ ;
: IF` `cond c, here SC c@ c, ;
: SKIP` $EB c, here SC c@ c, ;
: ELSE` SKIP` swap dupc@ SC c!
: THEN` dupc@ >SC
: `then here over- 1- `?off swap c! 0 callmark! ;
: 0;` 0-` 0=` IF` drop`
: ;THEN` ;;` dupc@ SC c! `then ;
: BOOL` 0 lit` IF` ~` THEN` ;
: zFALSE 0 0- drop ;
: nzTRUE 1 0- drop ;
: align` $90909090, here negate 3& allot ;
create `mrk 0 , 0 ,
: START` $9090 w, align` $00EB here 2- w!
: BEGIN` `mrk 2@ align` here SC c@ over+ `mrk 2! ;
: TIMES` >r`
: RTIMES` >C1 BEGIN` $007808FF, ,4 ;
: ENTER` `mrk@ dup 3& >SC -4& 1- `then ;
: WHILE` `cond
: `+jmp `mrk 2@ 3& >SC swap c, here dup `mrk 4+ ! swap - `?off c, ;
: CASE` =` drop` IF` drop` ;
: BREAK` $EB `+jmp THEN` ;
: TILL` `cond
: `-jmp `mrk@ dup 3& >SC -4& `-j ;
: AGAIN` $EB `-jmp THEN` ;
: UNTIL` TILL`
: END` `mrk 2@ dup 3& >SC -4& swap
  START dupc@ over `then - ENTER = TILL [ `mrk 2! ]
  @ $007808FF- 0= drop IF under 3+ `then rdrop` THEN
  drop `mrk 2! ;
: REPEAT` $EB `-jmp END` ;

: `[] '[' parse 2drop wsparse  0- 0= drop IF drop >in! !"unbalanced" ;THEN
  1 >in -! dup "ELSE]" $- 0<> drop IF dup "THEN]" $- 0<> drop IF "IF]" $- drop `[] ?
  BEGIN `[] 0<> UNTIL `[] ;THEN 1+ THEN drop ;
: [IF]` 0- 0= drop IF
: [ELSE]` >in@ `[] drop
: [THEN]` THEN ;
: [~]` wsparse find nip ;
1 constant [1]`
0 constant [0]`

variable `io
: key `io 1 under accept drop c@ ;
: space 32
:^ putc : emit `io 2dupc! swap 1_ type ;
:^ cr ."^J" ;

variable base 10 base!
: `.d 0 base@ m/mod 0; `.d
: .digit '0'+ '9' u> drop IF 7+ 'Z' u> drop IF '?'_ THEN THEN putc ;
: .\ 0- 0< IF ."-" negate THEN `.d .digit ;
: . .\ space ;
: .dec base@ 10 base! swap . base! ;
: .dec\ base@ 10 base! swap .\ base! ;
: .b 2
: .#s TIMES dup r 4* >> $F& .digit REPEAT drop ;
: .w 4 .#s ;
: .l 8 .#s ;
: 2dump dup .l .":" dup 16+ -rot
  START >rswapr> = IF nip cr 2dump ;THEN >rswapr>
    dup 3& 0= drop IF space THEN space c@+ .b
  ENTER u<= UNTIL 2drop drop space ;
:^ ui : prompt space depth .\ ';' anon@ 0- 0= drop IF 1- THEN emit space ;
: `.s  1- 0; swap >r `.s depth 0= drop IF space THEN r . r> ;
: .s` prompt 9 `.s cr ;
: .h` ."free:" H@ here - 1024/ .\ ."k_SC=" SC@ . .s`
  anon@ 0- 0= IF drop H@ @ THEN  here over-
: dump bounds 2dump cr ;

: words` H@ START 2dup+ 1+ -rot type space ENTER 5+ c@+ 0- 0= UNTIL 2drop cr ;
: hid'm` H@ 0 over 2- c! dup 1- swap
  START over+ 1+ swap dupc@ '`'- 0<> drop swap IF nip THEN
  ENTER 5+ c@+ 0- 0= UNTIL 2drop
  dup 1- c@+ + 1+ >r  START over 1- c@+ + 1+ swap 6-
    START 1- dupc@ r> 1- dup>r c! ENTER = UNTIL 2drop
  ENTER H@ 1- = drop UNTIL drop r> H! ;
: `mark ;` r> 5- here - allot anon:`
  H@ BEGIN dup@ swap 5+ c@+ + 1+ swap here = 2drop UNTIL H! ;
: mark` ;` wsparse
: marker 2dup+ dupc@ >r dup>r '`' swap c! 1+
  here 0 header 2r> c!  `mark ' call, anon:` ;
: eval >in@ tp@ 2>r over+ tp! >in! compiler 2r> tp! >in! ;

: argc CS0@ @ ;
: `argv 1+ 4* CS0@ + @ ;
: argv `argv zlen ;
:^ ossetup ;
: `back >in@ 1- dup BEGIN tib <> drop WHILE 1- dupc@ 10- drop 0= TILL 1+ END
  swap over- type ;
: `eval eval '
: `exec catch 0;  `back ."_<-error:_" c@+ type cr  2drop
  anon@ 0- 0= IF drop H@ dup@ swap 5+ c@+ + 1+ H! THEN
  here - allot  0 SC c! anon:` 0<>`  START `eval ENTER
:^ `top ui tib 1024 under accept 0- 0= exit ? dup 1- 0= drop IF AGAIN
  2dup 2- + c@ ';' - 0= drop IF AGAIN 2dup 1- + $3b20 swap w! 1+ REPEAT ;
: bye` ;` cr 0 exit ;
: help` !"Can't_find_file_ff.ff_needed_for_help!"
:^ doargv argc 1- 0; 1 `argv swap 2+ `argv over- tuck tib place swap `eval ;
: `boot ossetup doargv `top ;
`boot ' `bootxt! ;
