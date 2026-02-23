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

\ Unary ops
: negate` $48, ,1 $DBF7, s01 ;
: ~` $48, ,1 $D3F7, s01 ;
: 1+` $48, ,1 $C3FF, s01 ;
: 1-` $48, ,1 $CBFF, s01 ;
: 2+` 1+` 1+` ;

\ Memory access
: @` $48, ,1 $1B8B, s09 ;
: c@` $48, ,1 $0F, ,1 $1BB6, s09 ;

( Stack manipulation )
: 2dup over over ;
: 2drop drop drop ;
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

( Boolean constants )
-1 constant TRUE
0 constant FALSE
