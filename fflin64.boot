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

( Syscall-based I/O — replaces assembly WORD64 entries )
( x86-64 syscall: read=0, write=1, open=2, close=3 )
( Stack keeps Forth-natural ( addr # ) buffer pair; fd on top )
: read  ( addr # fd -- n ) >r swap r> 3 0 syscall ;
: openr ( addr # -- fd ) zt $1A4  0 rot 3 2 syscall ;
: openw ( addr # -- fd ) zt $1A4 $241 rot 3 2 syscall ;
: close ( fd -- n )  1 3 syscall ;

( Syscall word library — thin Forth wrappers over generic syscall )
( See ff64.help for full documentation. Reference: musl libc. )
( Convention: ( argN...arg2 arg1 N sysnum syscall ) )
(   arg1=closest to TOS → rdi, arg2 → rsi, arg3 → rdx, etc. )

( File I/O )
: lseek   ( offset whence fd -- pos )  >r swap r> 3 8 syscall ;
: fstat   ( buf fd -- ior )  2 5 syscall ;
: stat    ( buf addr -- ior )  2 4 syscall ;
: access  ( mode addr -- ior )  2 21 syscall ;
: dup2    ( newfd oldfd -- fd )  2 33 syscall ;
: fcntl2  ( arg cmd fd -- ior )  3 72 syscall ;
: pipe    ( pipefd[2] -- ior )  1 22 syscall ;
: ioctl3  ( arg req fd -- ior )  3 16 syscall ;

( Memory management )
$1  constant PROT_READ
$2  constant PROT_WRITE
$4  constant PROT_EXEC
$1  constant MAP_SHARED
$2  constant MAP_PRIVATE
$20 constant MAP_ANONYMOUS
: mmap    ( off fd flags prot len addr -- ptr )  6 9 syscall ;
: munmap  ( len addr -- ior )  2 11 syscall ;
: mprotect ( prot len addr -- ior )  3 10 syscall ;
: brk     ( addr -- newbrk )  1 12 syscall ;

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
: lstat      ( buf addr -- ior )  2 6 syscall ;
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
: tell  ( fd -- pos ) 0 1 rot lseek ;
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

( FFPATH — search path for needed/openlib )
( Default: lib/64:lib:. — overridable via FFPATH env var )
( Path stored as NUL-separated directory entries; double-NUL terminates )
( Buffers allocated via variable+allot; _ffpath_alloc initializes them )
( from a separate anonymous block [ossetup], per Primer §create+allot. )
variable ffpath pvt 248 allot
variable _openbuf pvt 248 allot
variable _fnbuf pvt 120 allot
variable _fnlen pvt
variable _dlen pvt

( _tryopen — try to open a file, return fd or -1 )
:. _tryopen openr ;

( openlib — search FFPATH for a file )
( addr len -- addr' len' | -1 -1 )
( Absolute/relative paths starting with / or . pass through unchanged )
:. openlib over c@ $2F = 2drop IF ;THEN
  over c@ $2E = 2drop IF ;THEN
  dup _fnlen ! _fnbuf @ swap cmove
  0 _fnbuf @ _fnlen @ + c!
  ffpath @ BEGIN dupc@ 0- 0<> WHILE drop
    dup >r zlen _dlen !
    _openbuf @ _dlen @ cmove
    $2F _openbuf @ _dlen @ + c!
    _fnbuf @ _openbuf @ _dlen @ + 1+ _fnlen @ cmove
    0 _openbuf @ _dlen @ + _fnlen @ + 1+ c!
    _openbuf @ zlen _tryopen
    0- 0>= IF close drop r> drop _openbuf @ zlen ;THEN
    drop r> zlen + 1+
  REPEAT drop drop -1 -1 ;

( _ffpath_alloc — initialize FFPATH buffers with default path )
( Called from ossetup [separate anonymous block], so writes to the )
( allotted area don't overwrite executing code — per Primer pattern: )
(   create X N allot ; X N init ;   -- semicolon separates blocks )
:. _ffpath_alloc
  ffpath 8+ ffpath !
  _openbuf 8+ _openbuf !
  _fnbuf 8+ _fnbuf !
  ffpath @
  "lib/64" drop over 6 cmove 6+ 0 over c! 1+
  "lib" drop over 3 cmove 3+ 0 over c! 1+
  "." drop over 1 cmove 1+ 0 over c! 1+ 0 swap c! ;

( needed — load file if not already loaded )
( Checks if word with backtick suffix exists in dictionary. )
( If found, file already loaded — skip. If not, search FFPATH and load. )
: needed 2dup + dup c@ >r dup >r $60 swap c! 1+
  find 2r> c! 0= IF 2drop ;THEN 1-
  2dup openlib 0- 0< IF 2drop type !"_not_found" ;THEN
  >r >r 2dup marker pvtmargin 2drop r> r> loadfile ;

( needexec — load file via needed, then execute its last definition )
:. needexec needed H@ @ execute ;

( needs` — compile-time: semicolons, reads filename, loads via needed )
: needs` ;` wsparse needed ;

( -f` — compile-time handler for -f flag in command-line args )
( If loaded file defines "main", rewrite vectors for turnkey mode: )
(   _top becomes _main, doargv becomes nop, argc/argv belong to main )
variable mainxt pvt
:. _main mainxt @ execute 0 exit ;

( see` — on first call, loads see.ff which redefines see` )
: see` ;` "see.ff" needexec ;

( help` — on first call, loads help.ff which redefines help` )
: help` ;` "help.ff" needexec ;

( doargv — evaluate command line arguments as FreeForth words )
:. doargv argc 1- 0; 1 _argv swap 2+ _argv over- tuck tib place swap eval. ;

( _postboot — doargv + hidepvt; nop'd for turnkey )
:^ _postboot doargv _hidepvt ;

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

( Boot sequence — ossetup is a vector for platform-specific init )
:^ ossetup _ffpath_alloc ;
:. _boot ossetup _postboot _top ;
_boot ;
