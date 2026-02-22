( ff64.boot — FreeForth2 x86-64 boot source )
( Provides standard Forth words using ff64 built-in primitives )

( Stack manipulation )
: 2dup over over ;
: 2drop drop drop ;
: 2swap rot >r rot r> ;
: ?dup dup 0<> IF dup THEN ;

( Arithmetic )
: abs dup 0< IF negate THEN ;
: max 2dup < IF swap THEN drop ;
: min 2dup > IF swap THEN drop ;
: within over - >r - r> < ;

( Comparison )
: >= < not ;
: <= > not ;
: <> = not ;

( Memory )
: ? @ . ;
: on -1 swap ! ;
: off 0 swap ! ;

( Output )
: space $20 emit ;
: spaces BEGIN dup 0 > WHILE space 1 - REPEAT drop ;

( Boolean constants )
-1 constant TRUE
0 constant FALSE
