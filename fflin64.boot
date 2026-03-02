( fflin64.boot — FreeForth2 x86-64 Linux-specific boot source )
( Modeled after Christophe Lavarenne's fflin.boot for i386. )
( This file is compiled after ff64.boot; it provides: )
(   - Syscall-based I/O [read, openr, openw, close] )
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

( Dynamic library interface — fails gracefully in static builds )
variable libc
:. dlsetup libc@ 0<>; drop "libc.so.6" #lib libc! ;
dlsetup
: libc.` wsparse libc@ #fun lit` #call ' call, ;
: libc_ libc@ #fun #call ;

( SEGV handler — recoverable via throw, replaces assembly early-boot handler )
( x86-64 struct sigaction: handler[8] sa_mask[128] sa_flags[4] pad[4] restorer[8] = 152 bytes )
( codebuf is BSS-zeroed, so allot gives us a zeroed struct — no fill needed )
( Requires libc for sigaction — in static build, assembly SEGV handler remains )
create SEGVact pvt 152 allot
:. SEGVhndlr !"SEGV caught" ;
SEGVhndlr ' SEGVact !
$40000000 SEGVact 136+ !
:. SEGVthrow 0 SEGVact 11 3 "sigaction" libc_ drop ;
libc@ 0- 0<> drop IF SEGVthrow THEN ;

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

( see` — on first call, loads see64.ff which redefines see` )
: see` ;` "see64.ff" needexec ;

( help` — on first call, loads help64.ff which redefines help` )
: help` ;` "help64.ff" needexec ;

( doargv — evaluate command line arguments as FreeForth words )
:. doargv argc 1- 0; 1 _argv swap 2+ _argv over- tuck tib place swap eval. ;

( _postboot — doargv + hidepvt; nop'd for turnkey )
:^ _postboot doargv _hidepvt ;

( -f` must come after _postboot — it references _postboot for vector nop )
:. _f_main mainxt ! _main ' _top !^ _postboot n^ ;
: -f` ;` wsparse needed "main" find 0- 0<> drop IF drop ;THEN _f_main ;

( ^^ — reset vector to its default body: xt -- )
: ^^ dup 6+ swap 1+ d! ;

( quit — reset _top to default, then call it )
: quit _top ' ^^ _top ;

( Register base features — _feat` appends space-separated names )
:. _feat` ;` $20 features appendc wsparse features append ;
_feat boot
_feat help
_feat dynlink
_feat segv

( \ — end-of-line comment; also sets noauto for multiline REPL input )
: \` 2 >in -! lnparse 2drop 1 noauto! ;

( Boot sequence — ossetup is a vector for platform-specific init )
:^ ossetup _ffpath_alloc ;
:. _boot ossetup _postboot _top ;
_boot ;
