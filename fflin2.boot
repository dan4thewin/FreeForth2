\ fflin2.boot — FreeForth2 unified Linux boot source
\ Merged from fflin.boot (i386) and fflin64.boot (x86-64).
\ Architecture-specific syscall wrappers live in lib/{x86,x86-64}/syscalls.ff.
\ This file is ^V-included from ff2.boot after the compiler is ready.

1 constant [os]`
: zt over+ 0 swap c! ;

\ Dynamic library interface — fails gracefully in static builds (#lib absent).
\ dlsetup runs now (eager init) and again via linsetup at turnkey re-entry.
\ The 0<>; guard makes repeat calls a no-op.
\ i386: libc variable lives in ff.asm (DATA "libc"); x86-64 needs a Forth one.
[64] [IF] variable libc [THEN]
:. dlsetup libc@ 0<>; drop "libc.so.6" #lib libc! ;
dlsetup
: libc.` wsparse libc@ #fun lit` #call ' call, ; \ compile-time: inlines #call
: libc_ libc@ #fun #call ;                       \ runtime version, turnkey safe

\ SEGV handler — recoverable via throw, raw rt_sigaction (no libc dependency).
\ Struct layout and syscall number differ between i386 and x86-64.
[64] [IF]
\ x86-64: handler(8) sa_flags(8) restorer(8) sa_mask(8) = 32 bytes
create _ksa pvt 32 allot
:. SEGVhndlr !"SEGV caught" ;
SEGVhndlr ' _ksa !
$14000004 _ksa 8+ !
sigrestorer _ksa 16+ !
0 _ksa 24+ !
:. SEGVthrow 8 0 _ksa 11 4 13 syscall drop ;
[ELSE]
\ i386: handler(4) sa_flags(4) restorer(4) sa_mask(8) = 20 bytes
create _ksa pvt 20 allot _ksa 20 0 fill
:. SEGVhndlr !"SEGV caught" ;
SEGVhndlr ' _ksa !
$44000000 _ksa 4+ !
sigrestorer _ksa 8+ !
:. SEGVthrow 8 0 _ksa 11 4 174 syscall drop ;
[THEN]
SEGVthrow ;

\ Syscall wrappers — arch-specific, loaded via ffpp ^V include.
\ i386 omits read/openr/openw/openw0/close (those are in fflinio.asm).
"syscalls.ff" marker
[64] [IF] lib/x86-64/syscalls.ff
[ELSE] lib/x86/syscalls.ff
[THEN]

\ Environment access
: envp CS0@ dup @ 2+ cell* + ;
: env envp @ BEGIN zlen 0<> WHILE 2dup+ -rot type cr 1+ REPEAT 2drop ;
:. _getenv swap -rot >= drop IF nip ;THEN
  >r 2dup r $- drop 0<> IF drop r> ;THEN
  r + c@+ '='- drop 0<> IF drop r> ;THEN
  nip zlen 2rdrop rdrop ;
: getenv envp @ BEGIN zlen 0- 0= IF BREAK 2dup+ 1+ >r _getenv
  r> REPEAT drop nip nip 0 ;

\ ffpath — search path for needs/openlib
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

\ openlib — search ffpath for a file
create openbuf pvt 80 allot
:. openlib over dupc@ '.' = 2drop IF 1+ THEN
  dupc@ '.' = 2drop IF 1+ THEN c@ '/' = 2drop IF openr ;THEN 2>r ffpath
  START tuck 2dup openbuf place + '/' overc! 1+ 2r rot place drop over+ swap
  r + 1+ openbuf swap openr 0- 0>= IF 2rdrop nip ;THEN drop
  ENTER c@+ 0- 0= UNTIL 2rdrop 2drop -1 ;

\ needed / needs` — file loading via eval (no assembly _loadfile).
\ needs` flushes anonymous code (;`) before loading to prevent code-overwrite.
\ marker creates a dictionary entry so repeated needs is a no-op.
: needs` ;` wsparse
: needed 2dup+ dupc@ >r dup>r '`' swap c! 1+ find 2r> c! 0= IF 2drop ;THEN 1-
  2dup openlib 0- 0< IF drop type space !"Can't_open_file." ;THEN
  >r marker pvtmargin tp@ eob over- under r read r> close drop
  over w@ [ "#!" drop w@ ] lit = 2drop
  IF bounds BEGIN c@+ 10- 0= drop UNTIL swap over- THEN eval 0 noauto! ;
:. needexec needed H@ @ execute ;

\ Lazy-loading commands
: help` ;` "help.ff" needexec ;
: see` ;` "see.ff" needexec ;
[32] [IF]
: -d` "debug.ff" needexec ;
: +longconds` "longconds.ff" needexec ;
[THEN]

\ Turnkey support — -f` loads a file, looks for "main", rewrites vectors.
\ mainxt stores main's XT; _main executes it and exits.
\ _postboot runs doargv + FFHIDE check + hidepvt; nop'd by -f` for turnkey.
variable mainxt pvt
:. _main mainxt @ execute 0 exit
:. _ffhide "FFHIDE" getenv 0- 0<> IF swap c@ '0'- 0= IF hide off THEN THEN 2drop ;
:^ _postboot _ffhide doargv hidepvt` ;
: -f` needs` "main" find 0- 0= drop IF mainxt ! _main ' _top !^ doargv n^ ELSE drop THEN ;
: quit _top ^^ _top ;

\ Boot hook — linsetup does dlopen + SEGV install; wired to ossetup vector.
\ _boot (in ff2.boot) calls ossetup, so this runs at every binary start.
:. linsetup dlsetup SEGVthrow ;
linsetup ' ossetup !^
