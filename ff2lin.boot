\ ff2lin.boot  unified Linux boot (i386 + x86-64)
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
\ syscall wrappers (bifurcated by arch for syscall numbers)

"syscalls.ff" marker
[64] [IF] lib/x86-64/syscalls.ff
[ELSE] lib/x86/syscalls.ff
[THEN]

\ --------------------------------------------------------------------
\ SEGV handler (rt_sigaction struct: handler flags restorer mask)

create _ksa pvt 3 cell* 8+ dup allot _ksa swap 0 fill
:. SEGVhndlr !"SEGV caught" ;
SEGVhndlr ' _ksa !
[64] [IF] $14000004 [ELSE] $44000000 [THEN] _ksa cell+ !
sigrestorer _ksa 2 cell* + !
:. SEGVthrow 8 0 _ksa 11 rt_sigaction drop ;
SEGVthrow ;

here 256 dup allot over "/proc/self/exe" drop readlink dup 256- allot swap
: exe lit lit ;

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

"HOME" getenv swap : homedir lit lit ;

\ --------------------------------------------------------------------
openlib.ff

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
: dis` ;` "dis.ff" needexec ;
[32] [IF]
: -d` "debug.ff" needexec ;
: +longconds` "longconds.ff" needexec ;
[THEN]

\ --------------------------------------------------------------------
\ boot hook (dlopen + SEGV; wired to ossetup for turnkey re-entry)

:. linsetup dlsetup SEGVthrow ;
linsetup ' ossetup !^
