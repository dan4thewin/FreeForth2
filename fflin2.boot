\ fflin2.boot  unified Linux boot (i386 + x86-64)
\ syscall wrappers in lib/{x86,x86-64}/syscalls.ff

1 constant [os]`
: zt over+ 0 swap c! ; \ @ # -- ; zero-terminate

\ --------------------------------------------------------------------
\ dynamic library interface (dlopen now; hook to _boot for turnkey)

[64] [IF] variable libc [THEN] \ i386: libc is asm DATA in ff.asm
:. dlsetup libc@ 0<>; drop "libc.so.6" #lib libc! ; \ 0<>; guards against repeats
dlsetup
: libc.` wsparse libc@ #fun lit` #call ' call, ; \ compile-time: inlines #call
: libc_ libc@ #fun #call ; \ runtime version, turnkey safe

\ --------------------------------------------------------------------
\ SEGV handler (raw rt_sigaction, no libc)

[64] [IF]
create _ksa pvt 32 allot \ handler(8) flags(8) restorer(8) mask(8)
:. SEGVhndlr !"SEGV caught" ;
SEGVhndlr ' _ksa !
$14000004 _ksa 8+ !
sigrestorer _ksa 16+ !
0 _ksa 24+ !
:. SEGVthrow 8 0 _ksa 11 4 13 syscall drop ;
[ELSE]
create _ksa pvt 20 allot _ksa 20 0 fill \ handler(4) flags(4) restorer(4) mask(8)
:. SEGVhndlr !"SEGV caught" ;
SEGVhndlr ' _ksa !
$44000000 _ksa 4+ !
sigrestorer _ksa 8+ !
:. SEGVthrow 8 0 _ksa 11 4 174 syscall drop ;
[THEN]
SEGVthrow ;

\ --------------------------------------------------------------------
\ syscall wrappers (i386 read/openr/openw/openw0/close in fflinio.asm)

"syscalls.ff" marker
[64] [IF] lib/x86-64/syscalls.ff
[ELSE] lib/x86/syscalls.ff
[THEN]

\ --------------------------------------------------------------------
\ environment access

: envp CS0@ dup @ 2+ cell* + ; \ -- @ ; pointer to envp[]
: env envp @ BEGIN zlen 0<> WHILE 2dup+ -rot type cr 1+ REPEAT 2drop ;
:. _getenv swap -rot >= drop IF nip ;THEN
  >r 2dup r $- drop 0<> IF drop r> ;THEN
  r + c@+ '='- drop 0<> IF drop r> ;THEN
  nip zlen 2rdrop rdrop ;
: getenv envp @ BEGIN zlen 0- 0= IF BREAK 2dup+ 1+ >r _getenv
  r> REPEAT drop nip nip 0 ; \ @ # -- @ # ; value, or last-checked 0

\ --------------------------------------------------------------------
\ ffpath -- search path for needs/openlib

"HOME" getenv dup>r
"FFPATH" getenv dup>r
2r> + 54+ create ffpath allot
[64] [IF] ":.:lib/x86-64:lib:" [ELSE] ":.:lib/x86:lib:" [THEN]
tuck ffpath place + >r
0- 0= IF 2drop ELSE tuck r> place + ':' overc! 1+ >r THEN
0- 0= IF 2drop ELSE tuck r> place + "/.local/share/ff:" dup>r rot place r> + >r THEN
"/usr/local/share/ff:^@" r> place drop

ffpath zlen over+ swap 1+ dup >r
START dupc@ ':' = 2drop IF r> 2dup - swap 1- c! 1+ dup >r THEN 1+
ENTER <= UNTIL 2drop r> 1- 0 swap c!

\ --------------------------------------------------------------------
\ openlib -- search ffpath for a file

create openbuf pvt 80 allot
:. openlib over dupc@ '.' = 2drop IF 1+ THEN \ @ # -- fd
  dupc@ '.' = 2drop IF 1+ THEN c@ '/' = 2drop IF openr ;THEN 2>r ffpath
  START tuck 2dup openbuf place + '/' overc! 1+ 2r rot place drop over+ swap
  r + 1+ openbuf swap openr 0- 0>= IF 2rdrop nip ;THEN drop
  ENTER c@+ 0- 0= UNTIL 2rdrop 2drop -1 ;

\ --------------------------------------------------------------------
\ needed/needs` -- file loading via eval
\ needs` ;` flushes anon code to prevent code-overwrite
\ marker dict entry makes repeated needs a no-op

: needs` ;` wsparse
: needed 2dup+ dupc@ >r dup>r '`' swap c! 1+ find 2r> c! 0= IF 2drop ;THEN 1-
  2dup openlib 0- 0< IF drop type space !"Can't_open_file." ;THEN
  >r marker pvtmargin tp@ eob over- under r read r> close drop
  over w@ [ "#!" drop w@ ] lit = 2drop
  IF bounds BEGIN c@+ 10- 0= drop UNTIL swap over- THEN eval 0 noauto! ;
:. needexec needed H@ @ execute ; \ needed + execute last def

\ lazy loaders
: help` ;` "help.ff" needexec ;
: see` ;` "see.ff" needexec ;
[32] [IF]
: -d` "debug.ff" needexec ;
: +longconds` "longconds.ff" needexec ;
[THEN]

\ --------------------------------------------------------------------
\ turnkey support (-f` loads file, finds "main", rewrites vectors)
\ _postboot runs doargv + hidepvt; nop'd by -f` via n^ for turnkey images

variable mainxt pvt
:. _main mainxt @ execute 0 exit
:. _ffhide "FFHIDE" getenv 0- 0<> IF swap c@ '0'- 0= IF hide off THEN THEN 2drop ;
:^ _postboot _ffhide doargv hidepvt` ;
: -f` needs` "main" find 0- 0= drop IF mainxt ! _main ' _top !^ doargv n^ ELSE drop THEN ;
: quit _top ^^ _top ;

\ --------------------------------------------------------------------
\ boot hook (dlopen + SEGV; wired to ossetup for turnkey re-entry)

:. linsetup dlsetup SEGVthrow ;
linsetup ' ossetup !^
