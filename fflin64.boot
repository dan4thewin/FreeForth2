( fflin64.boot — FreeForth2 x86-64 Linux-specific boot source )
( Modeled after Christophe Lavarenne's fflin.boot for i386. )
( This file is compiled after ff64.boot; it provides: )
(   - Syscall word library [file I/O, memory, process, directory] )
(   - Dynamic library interface [libc, dlsetup, libc., libc_] )
(   - File loading [needed, needexec, needs`] )
(   - Command-line processing [doargv, -f`] )
(   - Turnkey support [mainxt, _main, _postboot] )
(   - SEGV handler [SEGVact, SEGVhndlr, SEGVthrow — recoverable via throw] )
(   - Boot sequence [ossetup, _boot] )

1 constant [os]`

( zt — zero-terminate a string for syscalls: addr len -- addr )
: zt over+ 0 swap c! ;

( Syscall-based I/O — replaces assembly WORD64 entries )
( x86-64 syscall: read=0, write=1, open=2, close=3 )
( Stack keeps Forth-natural \( addr # \) buffer pair; fd on top )
: read  ( addr # fd -- n ) >r swap r> 3 0 syscall ;
: openr ( addr # -- fd ) zt $1A4  0 rot 3 2 syscall ;
: openw ( addr # -- fd ) zt $1A4 $241 rot 3 2 syscall ;
: openw0 ( addr # -- fd ) zt $1A4 $342 rot 3 2 syscall ;
: close ( fd -- n )  1 3 syscall ;

( Syscall word library — thin Forth wrappers over generic syscall )
( See ff64.help for full documentation. Reference: musl libc. )
( Convention: \( argN...arg2 arg1 N sysnum syscall \) )
(   arg1=closest to TOS → rdi, arg2 → rsi, arg3 → rdx, etc. )

( File I/O — raw syscall wrappers, prefixed _ to avoid shadowing )
( lib/fileops.ff provides higher-level lseek/stat with different interfaces )
: _lseek  ( whence offset fd -- pos )  3 8 syscall ;
: _fstat  ( buf fd -- ior )  2 5 syscall ;
: _stat   ( buf addr -- ior )  2 4 syscall ;
: access  ( mode addr -- ior )  2 21 syscall ;
: dup2    ( newfd oldfd -- fd )  2 33 syscall ;
: fcntl2  ( arg cmd fd -- ior )  3 72 syscall ;
: pipe    ( pipefd[2] -- ior )  1 22 syscall ;
: ioctl3  ( arg req fd -- ior )  3 16 syscall ;
: select  ( timeout exceptfds writefds readfds nfds -- n )  5 23 syscall ;
: ftruncate ( len fd -- ior )  2 77 syscall ;

( Memory management )
: mmap    ( off fd flags prot len addr -- ptr )  6 9 syscall ;
: munmap  ( len addr -- ior )  2 11 syscall ;
: mprotect ( prot len addr -- ior )  3 10 syscall ;
: brk     ( addr -- newbrk )  1 12 syscall ;

( Struct constants — stat )
144 constant _stat.sz
 48 constant st.size

( Process control )
: getpid  ( -- pid )  0 39 syscall ;
: fork    ( -- pid )  0 57 syscall ;
: execve  ( envp argv filename -- ior )  3 59 syscall ;
: wait4   ( rusage options status pid -- pid )  4 61 syscall ;
: kill    ( sig pid -- ior )  2 62 syscall ;
: exit_group ( status -- )  1 231 syscall ;

( Directory / filesystem )
: getcwd  ( size buf -- addr )  2 79 syscall ;
: chdir   ( addr -- ior )  1 80 syscall ;
: mkdir   ( mode addr -- ior )  2 83 syscall ;
: rmdir   ( addr -- ior )  1 84 syscall ;
: unlink  ( addr -- ior )  1 87 syscall ;
: rename  ( newpath oldpath -- ior )  2 82 syscall ;
: link    ( new old -- ior )  2 86 syscall ;
: symlink ( new old -- ior )  2 88 syscall ;
: readlink ( size buf addr -- n )  3 89 syscall ;
: chroot  ( addr -- ior )  1 161 syscall ;

( File metadata )
: _lstat     ( buf addr -- ior )  2 6 syscall ;
: fchmod     ( mode fd -- ior )  2 91 syscall ;
: fchown     ( gid uid fd -- ior )  3 93 syscall ;
: truncate   ( len fd -- ior )  2 77 syscall ;
: flock      ( op fd -- ior )  2 73 syscall ;
: umask      ( mask -- prev )  1 95 syscall ;
: getdents64 ( count buf fd -- n )  3 217 syscall ;

( Time )
: time      ( tloc -- sec )  1 201 syscall ;
: alarm     ( seconds -- prev )  1 37 syscall ;
: nanosleep ( rem req -- ior )  2 35 syscall ;
: times     ( buf -- ior )  1 100 syscall ;

( Process extras )
: getppid     ( -- pid )  0 110 syscall ;
: setpgid     ( pgid pid -- ior )  2 109 syscall ;
: getpgrp     ( pid -- pgid )  1 111 syscall ;
: getpriority ( who which -- pri )  2 140 syscall ;
: setpriority ( pri who which -- ior )  3 141 syscall ;

( Compound words )
: tell  ( fd -- pos ) 1 0 rot _lseek ;
: wait  ( status -- pid ) 0 0 rot -1 wait4 ;

( Miscellaneous )
: uname        ( buf -- ior )  1 63 syscall ;
: gettimeofday ( tz tv -- ior )  2 96 syscall ;
: getrandom    ( flags len buf -- n )  3 318 syscall ;

( Dynamic library interface — fails gracefully in static builds )
variable libc
:. dlsetup libc@ 0<>; drop "libc.so.6" #lib libc! ;
dlsetup
: libc.` wsparse libc@ #fun lit` #call ' call, ;
: libc_ libc@ #fun #call ;

( SEGV handler — recoverable via throw )
( Uses kernel struct kernel_sigaction [32 bytes]: )
(   +0: handler [8]  +8: sa_flags [8]  +16: restorer [8]  +24: sa_mask [8] )
( rt_sigaction syscall 13 — works in both dynamic and static builds )
create _ksa pvt 32 allot
:. SEGVhndlr !"SEGV caught" ;
SEGVhndlr ' _ksa !
$14000004 _ksa 8+ !
sigrestorer _ksa 16+ !
0 _ksa 24+ !
:. SEGVthrow 8 0 _ksa 11 4 13 syscall drop ;
SEGVthrow ;

: envp CS0@ dup @ 2+ 8* + ;
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
":.:lib/x86-64:lib:" tuck ffpath place + >r
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

: needs` ;`  wsparse
: needed 2dup+ dupc@ >r dup>r '`' swap c! 1+ find 2r> c! 0= IF 2drop ;THEN 1-
  2dup openlib 0- 0< IF drop type space !"Can't_open_file." ;THEN
  >r marker pvtmargin tp@ eob over- under r read r> close drop
  over w@ [ "#!" drop w@ ] lit = 2drop
  IF bounds BEGIN c@+ 10- 0= drop UNTIL swap over- THEN eval 0 noauto! ;
:. needexec needed H@ @ execute ;

( -f` — compile-time handler for -f flag in command-line args )
( If loaded file defines "main", rewrite vectors for turnkey mode: )
(   _top becomes _main, doargv becomes nop, argc/argv belong to main )
variable mainxt pvt
:. _main mainxt @ execute 0 exit ;

( see` — on first call, loads see.ff which redefines see` )
: see` ;` "see.ff" needexec ;

( help` — on first call, loads help.ff which redefines help` )
: help` ;` "help.ff" needexec ;

( _postboot — doargv + FFHIDE check + hidepvt; nop'd for turnkey )
:. _ffhide "FFHIDE" getenv 0- 0<> IF swap c@ '0'- 0= IF hide off THEN THEN 2drop ;
:^ _postboot _ffhide doargv _hidepvt ;

( -f` must come after _postboot — it references _postboot for vector nop )
:. _f_main mainxt ! _main ' _top !^ _postboot n^ ;
: -f` ;` wsparse needed "main" find 0- 0<> drop IF drop ;THEN _f_main ;

( quit — reset _top to default, then call it )
: quit _top ^^ _top ;

( Register base features — _feat` appends space-separated names )
:. _feat` ;` $20 features appendc wsparse features append ;
_feat boot
_feat help
_feat dynlink
_feat segv

:. linsetup dlsetup SEGVthrow ;
linsetup ' ossetup !^
