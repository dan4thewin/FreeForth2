1 constant [os]`
: zt over+ 0 swap c! ;
\ do dlopen now, and hook it to _boot to do dlopen for the turnkey case
:. dlsetup libc@ 0<>; drop "libc.so.6" #lib libc! ;
dlsetup
: libc.` wsparse libc@ #fun lit` #call ' call, ;
: libc_ libc@ #fun #call ; \ runtime version, turnkey safe

\ SEGV handler — raw rt_sigaction (no libc dependency)
\ i386 struct kernel_sigaction: handler(4) sa_flags(4) sa_restorer(4) sa_mask(8) = 20 bytes
create _ksa pvt 20 allot _ksa 20 0 fill
:. SEGVhndlr !"SEGV caught" ;
SEGVhndlr ' _ksa !
$44000000 _ksa 4+ !           \ SA_NODEFER | SA_RESTORER
sigrestorer _ksa 8+ !
:. SEGVthrow 8 0 _ksa 11 4 174 syscall drop ;

\ Syscall wrappers — match x86-64 fflin64.boot signatures
\ Lets lib/ files use named words instead of _sys.N constants
: _lseek     ( whence offset fd -- pos )  3 19 syscall ;
: _stat      ( buf addr -- ior )  2 195 syscall ;
: _fstat     ( buf fd -- ior )  2 197 syscall ;
: _lstat     ( buf addr -- ior )  2 196 syscall ;
: ioctl3     ( arg req fd -- ior )  3 54 syscall ;
: select     ( timeout exceptfds writefds readfds nfds -- n )  5 142 syscall ;
: nanosleep  ( rem req -- ior )  2 162 syscall ;
: time       ( tloc -- sec )  1 13 syscall ;
: gettimeofday ( tz tv -- ior )  2 78 syscall ;
: chdir      ( addr -- ior )  1 12 syscall ;
: ftruncate  ( len fd -- ior )  2 93 syscall ;
: tell       ( fd -- pos ) 1 0 rot _lseek ;
: mmap       ( off fd flags prot len addr -- ptr )  6 192 syscall ;
: munmap     ( len addr -- ior )  2 91 syscall ;
 98 constant _stat.sz
 44 constant st.size

: envp CS0@ dup @ 2+ cell* + ;
: env envp @ BEGIN zlen 0<> WHILE 2dup+ -rot type cr 1+ REPEAT 2drop ;
:. _getenv swap -rot >= drop IF nip ;THEN
  >r 2dup r $- drop 0<> IF drop r> ;THEN
  r + c@+ '='- drop 0<> IF drop r> ;THEN
  nip zlen 2rdrop rdrop ;
: getenv envp @ BEGIN zlen 0- 0= IF BREAK 2dup+ 1+ >r _getenv
  r> REPEAT drop nip nip 0 ;

"HOME" getenv dup>r
"FFPATH" getenv dup>r
2r> + 54+ create ffpath allot
":.:lib/x86:lib:" tuck ffpath place + >r
0- 0= IF 2drop ELSE tuck r> place + ':' overc! 1+ >r THEN
0- 0= IF 2drop ELSE tuck r> place + "/.local/share/ff:" dup>r rot place r> + >r THEN
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
: help` ;` "help.ff" needexec ;
: see` "see.ff" needexec ;
: -d` "debug.ff" needexec ;
: +longconds` "longconds.ff" needexec ;


variable mainxt pvt
:. _main mainxt @ execute 0 exit
: -f` needs` "main" find 0- 0= drop IF mainxt ! _main ' _top !^ doargv n^ ELSE drop THEN ;
: quit _top ^^ _top ;

:. _ffhide "FFHIDE" getenv 0- 0<> IF swap c@ '0'- 0= IF hide off THEN THEN 2drop ;
:^ _postboot _ffhide doargv hidepvt` ;

:. _feat` ;` $20 features appendc wsparse features append ;
_feat boot
_feat help
_feat dynlink
_feat segv

:. linsetup dlsetup SEGVthrow ;
linsetup ' ossetup !^
