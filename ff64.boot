( ff64.boot — FreeForth2 x86-64 boot source )
( Provides standard Forth words using ff64 built-in primitives )

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
