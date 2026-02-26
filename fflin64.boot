( fflin64.boot — FreeForth2 x86-64 Linux-specific boot source )
( Modeled after Christophe Lavarenne's fflin.boot for i386. )
( This file is compiled after ff64.boot; it provides: )
(   - Dynamic library interface [libc, dlsetup, libc., libc_] )
(   - File loading [needed, needexec, needs`] )
(   - Command-line processing [doargv, -f`] )
(   - Turnkey support [mainxt, _main, _postboot] )
(   - Feature registration [_feat] )
(   - Boot sequence [ossetup, _boot] )

1 constant [os]`

( Dynamic library interface )
variable libc
:. dlsetup libc@ 0<>; drop "libc.so.6" #lib libc! ;
dlsetup
: libc.` wsparse libc@ #fun lit` #call ' call, ;
: libc_ libc@ #fun #call ;

( needed — load file if not already loaded )
( Checks if word with backtick suffix exists in dictionary. )
( If found, file already loaded — skip. If not, create marker and load. )
: needed 2dup + dup c@ >r dup >r $60 swap c! 1+
  find 2r> c! 0= IF 2drop ;THEN 1-
  2dup marker swap loadfile ;

( needexec — load file via needed, then execute its last definition )
:. needexec needed H@ @ execute ;

( needs` — compile-time: semicolons, reads filename, loads via needed )
: needs` ;` wsparse needed ;

( -f` — compile-time handler for -f flag in command-line args )
( If loaded file defines "main", rewrite vectors for turnkey mode: )
(   _top becomes _main, doargv becomes nop, argc/argv belong to main )
variable mainxt pvt
:. _main mainxt @ execute 0 exit ;

( see` — on first call, loads lib/see64.ff which redefines see` )
: see` ;` "lib/see64.ff" needexec ;

( help` — on first call, loads lib/help64.ff which redefines help` )
: help` ;` "lib/help64.ff" needexec ;

( doargv — evaluate command line arguments as FreeForth words )
:. doargv argc 1- 0; 1 _argv swap 2+ _argv over- tuck tib place swap eval. ;

( _postboot — doargv + hidepvt; nop'd for turnkey )
:^ _postboot doargv _hidepvt ;

( -f` must come after _postboot — it references _postboot for vector nop )
:. _f_main mainxt ! _main ' _top ' !^ _postboot ' n^ ;
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

( Boot sequence — ossetup is a vector for platform-specific init )
:^ ossetup ;
:. _boot ossetup _postboot _top ;
_boot ;
