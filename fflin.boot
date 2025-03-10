1 constant [os]`
\ do dlopen now, and hook it to _boot to do dlopen for the turnkey case
:. dlsetup libc@ 0<>; drop "libc.so.6" #lib libc! ;
dlsetup
: libc.` wsparse libc@ #fun lit` #call ' call, ;
: libc_ libc@ #fun #call ; \ runtime version, turnkey safe

create SEGVact pvt 140 allot SEGVact 140 0 fill
:. SEGVhndlr !"SEGV caught" ;
SEGVhndlr ' SEGVact!
$40000000 SEGVact 132+ ! \ SA_NODEFER
:. SEGVthrow 0 SEGVact 11 3 "sigaction" libc_ drop ;
:. linsetup dlsetup SEGVthrow ;

"HOME"   1_ libc. getenv 0- 0<> IF zlen THEN dup >r
"FFPATH" 1_ libc. getenv 0- 0<> IF zlen THEN dup >r
2r> + 46+ create ffpath allot
":.:lib:" tuck ffpath place + >r
0- 0= IF drop ELSE tuck r> place + ':' overc! 1+ >r THEN
0- 0= IF drop ELSE tuck r> place + "/.local/share/ff:" dup>r rot place r> + >r THEN
"/usr/local/share/ff:^@" r> place drop

ffpath zlen over+ swap 1+ dup >r
START dupc@ ':' = 2drop IF r> 2dup - swap 1- c! 1+ dup >r THEN 1+
ENTER <= UNTIL 2drop r> 1- 0 swap c!

create openbuf pvt 80 allot
:. openlib over dupc@ '.' = 2drop IF 1+ THEN
  dupc@ '.' = 2drop IF 1+ THEN c@ '/' = 2drop IF openr ;THEN 2>r ffpath
  START tuck 2dup openbuf place + '/' overc! 1+ 2r rot place drop over+ swap
  r + 1+ openbuf swap openr 0- 0>= IF 2rdrop nip ;THEN drop
  ENTER c@+ 0- 0= UNTIL 2rdrop 2drop -1 ;

: needs` ;` wsparse
: needed 2dup+ dupc@ >r dup>r '`' swap c! 1+ find 2r> c! 0= IF 2drop ;THEN 1-
  2dup openlib 0- 0< IF drop type space !"Can't_open_file." ;THEN
  >r marker pvtmargin tp@ eob over- under r read r> close drop
  over w@ [ "#!" drop w@ ] lit = 2drop
  IF bounds BEGIN c@+ 10- 0= drop UNTIL swap over- THEN eval 0 noauto! ;
:. needexec needed H@ @ execute ;
: see` "see.ff" needexec ;
: -d` "debug.ff" needexec ;
: +longconds` "longconds.ff" needexec ;

variable mainxt pvt
:. _main mainxt @ execute 0 exit
: -f` needs` "main" find 0- 0= drop IF mainxt ! _main ' _top !^ doargv n^ ELSE drop THEN ;
: quit _top ^^ _top ;

linsetup ' ossetup !^ _boot ' >r
"ff.ff" needed ' _exec ;
