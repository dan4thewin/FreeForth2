;;; ff.asm  FreeForth interactive compiler for i386
;;; $Id: ff.asm,v 1.14 2009-09-03 20:35:29 lavarec Exp $

;;; These included comments are for the implementation-curious programmer.
;;; The beginner user will preferably first read the FreeForth tutorial at
;;; http://christophe.lavarenne.free.fr/ff

;;; -------------------------------------------------------
;;; What is this?

;;; FreeForth is an interactive development environment for programmers
;;; fed up with fat/slow/proprietary/blackbox development environments.

;;; It is very small and very fast, completely free and fully open source:
;;; . very small: the executable is less than 16 kilobytes,
;;;   and if you look inside, it's 40% binary code and 60% embedded source
;;; . very fast: being so small, it surely fully runs in i386 cache;
;;;   it instantly compiles compact and efficient native i386 code,
;;;   incrementaly i.e. you can edit/compile/execute code on the fly
;;;   repeatedly, which is ideal for debugging and intensive testing
;;; . completely _free_: its public domain license is the most permissive,
;;;   but you may want to pay for custom developments or support
;;; . fully open source: it's so small and well documented (>100 K of online
;;;   help) that it's easy to fully understand and customize to your needs

;;; It is supported under Linux and Windows, thanks to fasm, with a tiny
;;; compatibility layer for file-I/O and dynamic-link-libraries interface.
;;; It will also be the base for several incremental cross-compilers
;;; for microcontrollers (such as 8051s, PICs, and MSP430s)
;;; and digital signal processors (such as ADSP-218x and ADSP-BF53x).

;;; You're welcome to use FreeForth in any way, at your own risks as usual,
;;; or to contribute in any way to its development. Thanks if you do.

;;; -------------------------------------------------------
;;; Historical notes

;;; FreeForth is the name I've given to a long series of Forth umbilical
;;; development environments that I've been designing and using for years
;;; for developping real-time applications for embedded systems based on
;;; microcontollers and digital signal processors.

;;; It all began with the article about Forth in the Byte magazine of august
;;; 1980. Then Loeliger's book "Threaded Interpretive Languages" (Mc Graw Hill,
;;; ISBN 0-07-038360-X) gave good insights in a Z80 implementation.

;;; With time and experience with lots of other languages, including
;;; interactive (among which Lisp and Smalltalk), and with Forth cross- and
;;; meta-compilers, I wanted, and realised, ever simpler and more interactive
;;; cross-compilers: they now have no interpreter (although well interactive),
;;; no vocabularies, and no clumsy POSTPONE (although defining macros has
;;; never been easier).
;;; But they were still hosted by "standard" Forth systems (thanks mainly
;;; Gforth) and I wanted a consistent development system across "host" and
;;; "target": this FreeForth version is for i386 hosts under Linux and Windows.

;;; This public domain FreeForth version was inspired by RetroForth minimalism:
;;; a minimal bootstrap compiler, assembled with fasm to support operating
;;; system portability, compiles executable-embedded Forth source upto a full
;;; featured interactive Forth development environment. Although this relies
;;; on fasm (which is an excellent macro-assembler), this is a good shortcut
;;; compared with meta-compilation.

;;; But I wasn't pleased with RetroForth registers allocation: popping the
;;; stack is easy with "lodsd" (EAX=*ESI++), but pushing it isn't as easy
;;; and too expensive in code space to be inlined. FreeForth registers
;;; allocation, detailed hereunder, saves lots of both code space and
;;; processor cycles.

;;; The following chapters explain some central ideas behind FreeForth and its
;;; implementation.

;;; -------------------------------------------------------
;;; Language design notes:

;;; FreeForth is a context-free implementation of the Forth language:
;;; . no interpret/compile STATE variable, but instead anonymous definitions
;;; . no prefix compiler-overriders, but instead backquoted macros
;;; . no input conversion BASE variable, but instead literal base markers
;;; Moreover, FreeForth generates efficient subroutine-threaded native code:
;;; . with primitives implemented as macros generating i386 code inline,
;;;   including for the i386-associated floating-point unit
;;; . almost SWAP-free thanks to compile-time renaming of the two registers
;;;   caching the top two DATAstack cells
;;; . with optimized tail-recursion, compiling short jumps where possible
;;; . with a highly flexible literal compiler accepting binary-op suffixes
;;; . with variables and constants generated inline as literals
;;; . with constant-expressions reduction (not yet implemented)
;;; . with immediate-to-direct addressing-mode automatic conversions
;;;   by the memory and arithmetic primitives (not yet implemented)
;;; FreeForth also natively implements and uses throw/catch for its compiler
;;; (or user application) exception handling, with error context display.
;;; FreeForth also accepts input from the command line and from redirected
;;; stdin, and supports executable source files: see the example file hello.
;;; FreeForth also offers inline help documenting its implementation details.

;;; FreeForth is a STATE-free implementation of the Forth language:
;;; in usual Forth systems, the STATE variable tells the main loop
;;; whether to interpret every parsed word (i.e. execute its run-time
;;; semantics), or to compile it (i.e. execute its compile-time semantics).
;;; FreeForth main loop always compiles, but is still interactive thanks
;;; to "anonymous definitions" (aka "adef"): regular "named" definitions
;;; are open by ":" and closed by ";", which automatically opens an adef,
;;; which is closed either also by ";", or by any header-creating word
;;; (":", "create", etc.). When an adef is closed, the compilation pointer
;;; is automatically reset to its value when the adef was open, and the adef
;;; is executed: this gives user interactivity, and opens a way to simpler
;;; compilation optimizations, freed from the usual complexity of STATE
;;; (often "smart") handling.

;;; However, users of usual Forth systems may be surprised by the unusual need
;;; to close a FreeForth adef with a ";" (after trying "1 2 + ." and not seeing
;;; the expected "3" answer, some have thought FreeForth isn't worth another
;;; try). However, as sson as they understand, "1 2 + . ;" indeed displays "3",
;;; and they can even try adefs with control structures (that can't be inter-
;;; preted by usual Forth systems) such as "4 TIMES r . REPEAT ;" which simply
;;; displays "3 2 1 0".

;;; FreeForth is almost PREFIX-free: apart from the main loop, only a few
;;; FreeForth words parse the input source:
;;; . parse primitives: "parse", "wsparse", "lnparse"
;;; . commenting words: "\" until end of line, "(" until ")", and "EOF"
;;; . headers-handling words: ":", "create", "needs", "mark", etc.
;;; . and conditional compilation words: "[IF]", "[ELSE]", "[THEN]", etc.
;;; Usual Forth systems use other prefix words (which parse the input
;;; source to override the main loop default behaviour), which FreeForth
;;; implements more conveniently:
;;; . usual quotes (and dot-quotes) are replaced with the SPACE-free
;;;   string-literal compiler (see next paragraph)
;;; . usual "[']" is replaced by postfixed "'", which replaces the call
;;;   compiled just before it by an inline literal (or throws an exception
;;;   if no call was compiled just before it)
;;; . usual "[COMPILE]" aka "[POSTPONE]" is replaced with backquoted macros:
;;;   macros, i.e. words to be immediately executed at compile time, must be
;;;   defined (mainly by ":") with a final backquote appended to their name;
;;;   after parsing a word from the input source (between delimiters among
;;;   NUL HT LF VT FF CR and space), the main loop first appends a backquote
;;;   to the word before looking for it in the headers (i.e. symbol table):
;;;   if it is found with an appended backquote, the code the header points
;;;   to is immediately executed (this is a "macro" behaviour); otherwise,
;;;   the main loop removes the appended backquote, and looks again for it
;;;   in the headers: if it is found without an appended backquote, a call
;;;   is compiled if the header is marked (mainly by ":") to point to code,
;;;   or an inline literal is compiled if the header is marked (by "create"
;;;   and derivatives) to point to data (or by "constant" to contain a
;;;   constant value); otherwise, the main loop passes the word to the
;;;   literal compiler, which may throw an exception if it fails.
;;; Backquoted macros are very convenient to define new macros: see ff.boot

;;; FreeForth literal compiler is SPACE-free for strings, and BASE-free
;;; for numbers. It interprets the literal final character as follows:
;;; . a final (double) quotes marks a string:
;;;   - if the initial is a comma, the string is inlined with neither
;;;     preceding call nor count (useful to inline any binary code or data)
;;;   - if the initial is a quotes, a call to quotes-runtime is compiled
;;;   - if the initial is a dot, a call to dot-quote-runtime is compiled
;;;   - if the initial is a '!', a call to exception-runtime is compiled
;;;   then the source string is converted (see _number and "String-codings"
;;;   for special characters) and compiled into a literal counted-string;
;;;   when later executed, the quotes-runtime will push on the DATAstack the
;;;   compiled string base address and count, whereas the dot-quotes-runtime
;;;   will display the compiled string (with type), then both will resume
;;;   execution after the compiled string, whereas the exception-runtime will
;;;   pass the counted-string address to "throw" to raise an exception to be
;;;   "catch"ed, either by user code, or by default by the top-level loop
;;;   to display it as error message
;;; . a final binary operator character (among +-*/%&|^ as in C) attempts
;;;   to convert the rest of the string as a number (see next item), and
;;;   compiles the corresponding i386 instruction(s) with immediate addressing
;;;   and with the converted number as immediate argument
;;; . otherwise, the literal compiler attempts to convert the full string
;;;   into a number, starting by default with a decimal conversion base,
;;;   which may be overriden as follows:
;;;   - "$" changes conversion base to 16 (hexadecimal)
;;;   - "&" changes conversion base to  8 (octal)
;;;   - "%" changes conversion base to  2 (binary)
;;;   - "#" changes conversion base to the number converted so far
;;;   For example: 18 = $12 = &22 = %10010 = 3#60 = 12#16 = %10&2
;;;   More complex base changes are possible, as already implemented
;;;   for date and/or time conversion: 2006-5-6_17:42:15 (see _number)

;;; FreeForth compiler generates efficient "subroutine-threaded" code with
;;; primitives implemented as macros generating native 386 code inline:
;;; see the following "Compiler implementation notes".

;;; FreeForth offers both a minimalist set of flow-control words (":" ";" "?"),
;;; which may be used on its own, and a richer set of generalized flow-control
;;; words supporting nestable control-structures and exception handling.
;;; These flow-control words are very flexible and efficient, but somewhat
;;; unusual, so be sure to read the online help on the "conditionals" and
;;; "flow-control" topics before using them.

;;; For those used to RetroForth/Reva/HelFORTH minimal control-structures,
;;; a compatibility wordset may be conditionally compiled in ff.ff

;;; Yes, an online help documents all usable words, and even gives their
;;; source code (these comment mainly the boot source file, which is otherwise
;;; comment-less for executable-embedding compacity).

;;; FreeForth is also designed with interactive umbilical cross-compilation
;;; in mind, with "host" and "target" compiler contexts switchings simpler
;;; than usual implementations (not yet implemented).

;;; -------------------------------------------------------
;;; Compiler implementation notes:

;;; We recognize Forth is a virtual-machine with LIFO sequentially-accessed
;;; registers, mostly implemented on real-machines with index-accessed
;;; registers: native instructions of most processors include fields for
;;; "register-indexes", that most Forth implementations use with almost
;;; always the same register(s).
;;; Instead, FreeForth uses this "free" resource by allocating two real
;;; registers to the two DATAstack top cells, and by swapping these two
;;; registers indexes at compile-time (so-called "register renaming")
;;; instead of swapping their contents at run-time: this is an easy and
;;; efficient optimization, which encourages the almost "free" use of "swap"
;;; to implicitely select "the other" register, and which implied new pop-less
;;; conditional jumps (see "conditionals" and "flowcontrol" online help topics)
;;; which also allow a good reduction of push/pops operations around them.

;;; Registers allocation:
;;; . esp is the regular CALLstack pointer, or alternate DATAstack pointer.
;;; . eax is the regular DATAstack pointer, or alternate CALLstack pointer.
;;; . Alternate pointers are used to efficiently push and pop the DATAstack;
;;;   "xchg eax,esp" is used to switch between regular and alternate pointers.
;;; . ebx is the regular top of DATAstack (T), or alternate second of stack (S)
;;; . edx is the regular second of DATAstack (S), or alternate top of stack (T)
;;; . Alternate T and S are used to efficiently replace every runtime "swap"
;;;   with compile time exchange of register names in generated instructions;
;;;   "xchg ebx,edx" is used to restore the regular registers T and S.
;;; . Regular pointers and registers MUST be (and are) restored by the compiler
;;;   before every call or ret: this is mainly done by "rst".
;;; . ebp is the compilation pointer (saved as "frame pointer" by system calls)

;;; The memory map is allocated as follows:
;;;
;;; [binary code and data> heap <headers][source code> blocks][ ]  < stacks ]
;;; :                 ebp^      ^H    tib:  tin^>  tp^     eob: ;   eax^ esp^
;;;
;;; Space is already allocated by the operating system's loader for the stack,
;;; with esp already pointing at its "bottom"; 4Kbytes are reserved for the
;;; CALLstack, and eax is initialized pointing at the DATAstack "bottom".
;;; Compiled binary code and data are appended just after fasm-generated code.
;;; Headers are separately compiled backwards, just before fasm's headers.
;;; Boot source code, and later user command lines, are stored at tib.
;;; "needs" reads its source file's entire contents just after the current
;;; source code stored at tib and evaluates it (tib is a "file stack").
;;; The blocks editor (see bed.ff) alternatively uses the memory located
;;; 128K bytes after tib, as 512-bytes blocks, each seen as 8 lines of 64
;;; characters each.

;;; Each header is structured as follows:
;;; . offset 0: 4 bytes: pointer to code or data, or constant value
;;; . offset 4: 1 byte: header type: 0=code, 1=data/cste, 2-7=user
;;; . offset 5: 1 byte: name size
;;; . offset 6: size bytes: name string
;;; . offset 6+size: null byte (zero-terminator for operating-system calls)
;;; There is no need for the usual "link" field and "last" variable,
;;; because headers are stored backwards, then the H variable, which
;;; is the headers-space allocation pointer, also points on the base
;;; address of the last defined header (as "last" used to), and to
;;; skip over a header (to the previously defined one), just add 7
;;; and its name size to its base address.
;;; Headers generation by fasm is postponed by the WORD macro (and derivatives)
;;; by redefining the GENWORDS macro such that, when it is executed at the
;;; assembler source end, all headers are generated forwards (from low to
;;; high memory) but in reverse order, from last to first defined, which
;;; corresponds to the desired backwards layout (from low to high memory)
;;; in the order from first to last defined.

;;; Headers are generated just after all other assembled code and data,
;;; followed by the boot source code, directly included in the executable
;;; file for easy access required prior to loading from a separate file.
;;; Headers and boot source are moved at startup from there to their final
;;; location: headers before tib, and boot source after tib, ready for
;;; boot compilation. The boot source last definition is anonymous,
;;; and compiled into a single jump to the main loop "boot" definition,
;;; and therefore may be safely overwritten by following compilations.
;;; The boot definition takes care of executing the command line before
;;; displaying the welcome banner and entering the user interaction loop.

;;; -------------------------------------------------------
;;; Thanks to:

;;; Chuck Moore (http://www.colorforth.com) invented the Forth languages,
;;; and put them in the public domain, for the great fun of lots of fans,
;;; including me. My experience working with him and sponsoring his work
;;; on OKAD during 1995 and 1996 to produce the v21 was also great fun...
;;; until he shot me and my associate sponsors in the back, and spat at
;;; me nasty xenophobian arguments. It was great deception about the man.
;;; He never apologized. Other fans, you're warned now...

;;; Rod Crawford, who likes hot spices so much, after our discussions
;;; about FreeForth anonymous definitions, published in EuroForml'88
;;; "Who needs the interpreter anyway?" introducing some of the idea.

;;; Francis Cannard est tombe' dans le Forth quand il etait petit, et ne
;;; s'en est jamais remis depuis :-) Since 1991, we've shared many thoughts,
;;; trips, companies, successes, and failures. He instigated my desire
;;; to bear to life one more FreeForth, this one. He finally convinced me
;;; of the interest to use two stack top cache registers instead of one.

;;; Anton Ertl (http://www.complang.tuwien.ac.at/~anton) grows up Gforth,
;;; which I've been using since late 2000 to port to Linux my ADSP-218x
;;; and ADSP-BF53x FreeForth umbilical development environments, in-flash
;;; token-threaded virtual machines, and real-time DSP-embedded operating
;;; systems.

;;; Charles Childers (http://retroforth.org) makes so simple a Forth
;;; implementation based on FASM, which inspired this new FreeForth.

;;; Tomasz Grysztar (http://flatassembler.net) makes FASM so good, including
;;; at macros, and well documented.


;;; -------------------------------------------------------
;;; macro-generation of Operating-System specific format

OSFORMAT

;;; -------------------------------------------------------
;;; headers (compiler symbol table) generating macros

macro CDB [string] {            ; compile counted string
    common local .eostr
        db .eostr-$-1           ; string count
        db string               ; string proper
.eostr  db 0                    ; append zero-terminator
}
macro WORD name, xt, ct {       ; generate a header entry:
    macro GENWORDS \{           ; redefines GENWORDS
        dd xt                   ; code or data address, or literal
        db ct                   ; 0:code, 1:data/lit, etc?
        CDB name                ; name counted string
        GENWORDS                ; calls GENWORDS _previous_ definition
    \}
}
macro GENWORDS {                ; last called, first definition of GENWORDS
        dd 0                    ; don't-care xt
        db 0                    ; don't-care ct
        CDB ""                  ; empty counted string marks end of headers
}
macro CODE name, entry {        ; subroutine entry
        WORD name, entry, 0     ; code address
entry:                          ; subroutine code starts here
}
macro DATA name, addr, init {   ; data variable
        WORD name, addr, 1      ; data address
addr    dd init                 ; initialized data buffer
}
macro CSTE name, value {        ; literal constant
        WORD name, value, 9     ; literal value
}
macro VECT name, entry {        ; vectorizable subroutine entry
        CODE name, entry
        push dword $+6          ; 68(push long)
        ret                     ; C3(ret)
}

;;; -------------------------------------------------------
;;; stack handling macros

macro DROP1 {                   ; n --
        mov ebx,edx             ; 89D3
        xchg eax,esp            ; 94
        pop edx                 ; 5A
        xchg eax,esp            ; 94
}
macro DUP1 arg {                ; n -- n arg
        xchg eax,esp            ; 94
        push edx                ; 52
        xchg eax,esp            ; 94
        mov edx,ebx             ; 89DA
    if arg eq
    else if (arg eqtype 0) & (arg = 0)
        xor ebx,ebx             ; 31DB
    else if (arg eqtype 0) & (arg xor 2*arg < $FF)
        push arg                ; 6A nn
        pop ebx                 ; 5B
    else
        mov ebx,arg
    end if
}
macro DUP2 {                    ; x y -- x y x y
        xchg eax,esp            ; 94
        push edx                ; 52
        push ebx                ; 53
        xchg eax,esp            ; 94
}

;;; -------------------------------------------------------
;;; compilation pointer macros

macro HD arg, size, opt {       ; -- ; place arg at here
    if opt eq
        mov size[ebp],arg       ; ebp is the compilation pointer
    else
        mov size[ebp+opt],arg
    end if
}
macro HDB arg, opt { HD arg, byte, opt } ; C645ooaa
macro HDW arg, opt { HD arg, word, opt } ; 66C745ooaaaa
macro HDD arg, opt { HD arg,dword, opt } ; C745ooaaaaaaaa

macro POSTPN target {           ; target may be literal or register (unchanged)
        HDB $E8                 ; call opcode
        add ebp,5               ; allocate call instruction
        HDD target,-4           ; laydown call target address
        sub [ebp-4],ebp         ; convert absolute to relative
}


;;; -------------------------------------------------------
;;; Put these first to simplify turnkey generation

DATA "H",H,H0                   ; headers
DATA "anon",anon,ebp0
DATA "CS0",CS0,0                ; CALLstack base address, set later
DATA "DS0",DS0,0                ; DATAstack base address, set later
DATA "`bssend",bssend,0
DATA "`bootxt",bootxt,0
DATA "libc",_libc,0

;;; -------------------------------------------------------
;;; basic code generation support

DATA "SC",SC,0                  ; compiler flags: SWAPbit and CALLbit
CODE "rst",_rst                 ; -- ; reset SC=0
        call toS0               ; E81B000000
;;;     jmp toC0
CODE ">C0",toC0                 ; test&reset CALLbit to setup esp=CALLsp
        btr [SC],0              ; 0FBA35.SC.00
        jnc @f                  ; 7305
toC:    HDB $94                 ; C6450094  94(xchg eax,esp)
        inc ebp                 ; 45
@@:     ret
CODE ">C1",toC1                 ; test&set CALLbit to setup esp=DATAsp
        bts [SC],0              ; 0FBA2D.SC.00
        jnc toC                 ; 73F0
        ret
CODE ">S0",toS0                 ; test&reset SWAPbit to setup ebx=TOS
        btr [SC],1              ; 0FBA35.SC.01
        jnc @f                  ; 7309
toS:    HDW $DA87               ; 66C7450087DA   87DA(xchg ebx,edx)
        add ebp,2               ; 83C502
@@:     ret
CODE ">S1",toS1                 ; test&set SWAPbit to setup edx=TOS
        bts [SC],1              ; 0FBA2D.SC.01
        jnc toS                 ; 73EC
        ret
CODE ">SC",toSC                 ; SC -- ; setup SC
        xor bl,byte[SC]         ; 321D.SC.   bl = difference
        xor byte[SC],bl         ; 301D.SC.   SC = new value
        test bl,2               ; F6C302     change SWAPbit?
        jz @f                   ; 7405
        call toS                ; E8D5FFFFFF xchg ebx,edx
@@:     test bl,1               ; F6C301     change CALLbit?
        DROP1
        jnz toC
        ret

;;; reg= 0:eax 1:ecx 2:edx 3:ebx 4:esp 5:ebp 6:esi 7:edi
CODE "c04",c04                  ; eax/esp
        mov ch,4                ; B504
        test byte[SC],1         ; F605.SC.01 CALLbit?
        jmp s01.1               ; EB0C
CODE "s1",s1
        dec ebp                 ; 4D
CODE "s01",s01                  ; dest reg[2:0] only ebx/edx
        mov ch,1                ; B501
.0:     test byte[SC],2         ; F605.SC.02 SWAPbit?
.1:     lea ebp,[ebp+2]         ; 8D6D02 ,^M~m^B"
        jz @f                   ; 7403
        xor byte[ebp-1],ch      ; 306D01
@@:     ret
CODE "s08",s08                  ; source reg[5:3] only ebx/edx
        mov ch,8                ; B508
        jmp s01.0               ; EBEC
CODE "s09",s09                  ; source[5:3] and dest[2:0] regs ebx/edx
        mov ch,9                ; B509
        jmp s01.0               ; EBE7

;;; -------------------------------------------------------
;;; basic stack handling macros

CODE "over`",_over              ; x y -- x y x
        call _under
CODE "swap`",_swap              ; x y -- y x
        xor byte[SC],2          ; 8035.SC.02 toggle SWAPbit
        ret
CODE "under`",_under            ; x y -- x x y
        call toC1
        HDB $52                 ; 52(push edx)
        jmp s1
CODE "drop`",_drop              ; x --
        call _swap
CODE "nip`",_nip                ; x y -- y
        call toC1
        HDB $5A                 ; 5A(pop edx)
        jmp s1

;;; -------------------------------------------------------
;;; control structures

;;; 72:jb/jae 74:jz/jnz 76:jbe/ja 78:js/jns 7C:jl/jge 7E:jle/jg (long:+0F10)
;;; E2:loop/jecxz(byte) E8:call/jmp(long) EB:jmp(byte)

xfp     dd 0                    ; exception frame pointer
CODE "catch",_catch             ; xt -- exception ; 0=none
        push eax                ; 50        save dataSP
        push edx                ; 52        save NOS
        push [xfp]              ; FF35.xfp. save frame pointer
        mov [xfp],esp           ; 8925.xfp. save callSP
        mov ecx,ebx             ; 89D9
        DROP1                   ; 89D3 945A94
        call ecx                ; FFD1      execute protected code
        pop [xfp]               ; 8F05.xfp. restore frame pointer
        add esp,8               ; 83C408    ignore other saved data
        DUP1 0                  ; 945294 89DA 31DB   -- 0
        ret

_error: pop ebx
CODE "throw",_throw             ; message --
        mov esp,[xfp]           ; 8B25.xfp. restore callSP
        pop [xfp]               ; 8F05.xfp. restore frame pointer
        pop edx                 ; 5A        restore NOS (TOS = exception)
        pop eax                 ; 50        restore dataSP
        ret

;;; -------------------------------------------------------
;;; number input

accu dd 0
CODE "number.",_numberdot       ; @ # base -- @ # | n 0
        push ebp                ; ebp use as current base
        mov ebp,ebx             ; base = TOS
        DROP1
        jmp @f
VECT "number",_number           ; @ # -- @ # | n 0
        push ebp                ; ebp use as current base
        mov ebp,10              ; default base = decimal
@@:     push eax
        mov esi,edx             ; esi = string base address
        lea edi,[edx+ebx]       ; edi = string limit address
        xor ecx,ecx             ; accu0 = 0
        mov [accu],ecx          ; accu1 = 0
        lodsb                   ; al = initial
        push eax                ; save initial (maybe sign)
        cmp al,'-'              ; skip initial sign
        jne @f
        lodsb
@@:     cmp al,"'"              ; single quoted ascii
        jne .e
        movzx ecx,byte[esi]
        jmp .s
.7:     mov ebp,8               ; octal
        jmp .4
.6:     mov ebp,2               ; binary
        jmp .4
.5:     mov ebp,16              ; hexadecimal
        jmp .4
.z:     mov ebp,10
        jmp .4
.8:     jecxz .z                ; #: initial=decimal
        mov ebp,ecx             ; #: base=accu
.d:     xor ecx,ecx             ; ecx = accumulator
.4:     lodsb                   ; al = next digit
.e:     cmp al,$7F              ; reject $7F..$FF
        jae .0
        movzx eax,al
        push eax                ; save eax = digit
        movzx eax,byte[.ct+eax] ; eax = byte method index
        mov eax,[.jt+4*eax]     ; eax = byte method address
        xchg eax,[esp]          ; restore eax = digit
        ret
.jt     dd .0,.1,.2,.3,.4,.5,.6,.7,.8,.9,.10,.11,.12
.3:     sub al,'a'-'A'          ; abcdefghijklmnopqrstuvwxyz
.2:     sub al,'A'-'0'-$A       ; ABCDEFGHIJKLMNOPQRSTUVWXYZ
.1:     sub al,'0'              ; 0123456789
        cmp eax,ebp             ; reject digit >= base
        jae .0
        imul ecx,ebp            ; accumulator *= base
        add ecx,eax             ; accumulator += digit
        cmp esi,edi             ; string limit address reached?
        jb .4
        add ecx,[accu]
.s:     cmp byte[esp],'-'       ; saved initial
        jne @f
        neg ecx                 ; negative sign
@@:     mov edx,ecx
        xor ebx,ebx             ; -- n 0 ; conversion succeeded
.9:                             ; whitespace (for wsparse)
.0:     pop eax                 ; error
        pop eax
        pop ebp
        ret

.10:    xchg ecx,[accu]         ; gregorian date: y-m-d
        jecxz .4                ; ecx = year, accu = month
        xchg ecx,[accu]
        cmp ecx,3               ; month
        jge @f
        add ecx,12              ; move origin at march 1st
        dec [accu]
@@:     inc ecx
        push edx
        mov eax,31+30+31+30+31  ; 5 month period
        mul ecx                 ; eax = 153m
        mov ecx,5
        div ecx                 ; eax = 153m/5
        sub eax,123             ; eax = 153m/5-123
        xchg eax,[accu]         ; eax = y
        imul ecx,eax,1461
        shr ecx,2               ; ecx = 365y+y/4
        add [accu],ecx
        mov ecx,100
        xor edx,edx
        div ecx                 ; eax = y/100
        sub [accu],eax
        shr eax,2               ; eax = y/400
        add [accu],eax
        pop edx
        xor eax,eax
        jmp .d
.11:    cmp [accu],730484       ; separator between date and time
        jl @f                   ; less when using year-2000
        sub [accu],730485       ; translate origin to 2000-03-01 (wednesday)
@@:     mov al,24               ; eax = 24: y-m-d_h:m:s
        jmp @f
.12:    mov al,60               ; eax = 60: h:m:s
@@:     add ecx,[accu]
        imul ecx,eax            ; shift accu, ready for next add
        mov [accu],ecx
        jmp .d

;;;         0  1  2  3   4  5  6  7   8  9  A  B   C  D  E  F
;;;    00: NULSOHSTXETX EOTENQACKBEL BS HT LF VT  FF CR SO SI ; 0:error
.ct     db  9, 0, 0, 0,  0, 0, 0, 0,  0, 9, 9, 9,  9, 9, 0, 0 ; 1:digit
;;;    10: DLEDC1DC2DC3 DC4NAKSYNETB CANEM SUBESC FS GS RS US ; 2:upper
        db  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0 ; 3:lower
;;;    20:     !  "  #   $  %  &  '   (  )  *  +   ,  -  .  / ; 4:skip
        db  9, 0, 0, 8,  5, 6, 7, 4,  0, 0, 0, 0,  4,10, 0, 4 ; 5:$hex
;;;    30:  0  1  2  3   4  5  6  7   8  9  :  ;   <  =  >  ? ; 6:%bin
        db  1, 1, 1, 1,  1, 1, 1, 1,  1, 1,12, 0,  0, 0, 0, 0 ; 7:&oct
;;;    40:  @  A  B  C   D  E  F  G   H  I  J  K   L  M  N  O ; 8:#base
        db  0, 2, 2, 2,  2, 2, 2, 2,  2, 2, 2, 2,  2, 2, 2, 2 ; 9:whitespace
;;;    50:  P  Q  R  S   T  U  V  W   X  Y  Z  [   \  ]  ^  _ ; 10:-date
        db  2, 2, 2, 2,  2, 2, 2, 2,  2, 2, 2, 0,  0, 0, 0,11 ; 11:_24
;;;    60:  `  a  b  c   d  e  f  g   h  i  j  k   l  m  n  o ; 12::60
        db  0, 3, 3, 3,  3, 3, 3, 3,  3, 3, 3, 3,  3, 3, 3, 3 ;
;;;    70:  p  q  r  s   t  u  v  w   x  y  z  {   |  }  ~ DEL;
        db  3, 3, 3, 3,  3, 3, 3, 3,  3, 3, 3, 0,  0, 0, 0, 0 ;

;;; -------------------------------------------------------
;;; literal compiler: this is rich but quite simple

CODE "litcomp",literalcompiler  ; @ # -- ; from _wsparse
        mov edi,.f              ; finals
        mov ecx,(.x - .f)
        dec ebx                 ; -- @ #-1
        push eax
        mov al,[ebx+edx]        ; al = final
        repnz scasb             ; ecx = remaining finals
        pop eax
        neg ecx
        jmp [.def+4*ecx]
.f      db """","_+-*/%&|^,@!",0 ; interpreted finals
.x      dd litquote, litnip
        dd litadd,litsub,litmul,litdiv,litmod
        dd litand,litior,litxor
        dd litcomma,litfetch,litstore
.def    dd litnum               ; default

skipstr:                        ; -- @ #
        DUP2
        pop edi                 ; edi = return address
        pop edx                 ; edx = caller's return address
        movzx ebx,byte[edx]     ; ebx = string count
        inc edx                 ; edx now points on string initial
        lea ecx,[edx+ebx+1]     ; skip over string and its zero-terminator
        jmp edi
litstr:                         ; -- @ # ; _quote compiles call litstr
        call skipstr
        jmp ecx                 ; resume execution after string
dotstr:                         ; -- ; _dotquote compiles call dotstr
        call skipstr
        push ecx                ; push return address
        jmp _type
litquote:                       ; @ # -- ; embed a string literal
        cmp byte[edx],','       ; initial comma
        jz memcomma
        call _rst
        cmp byte[edx],""""      ; initial quotes
        jnz @f
        POSTPN litstr
        jmp strcomma
@@:     cmp byte[edx],"."       ; initial dot
        jnz @f
        POSTPN dotstr
        jmp strcomma
@@:     cmp byte[edx],"!"       ; initial exclamation mark
        jnz @f
        POSTPN _error
        jmp strcomma
@@:     cmp byte[edx],"s"       ; mimic s" and S" from standard forth
        jz @f
        cmp byte[edx],"S"
        jnz notfnd
@@:     inc edx
        dec ebx
        cmp byte[edx],""""
        jnz notfnd
        cmp byte[edx+1],$20     ; discard first space
        jnz @f
        inc edx
        dec ebx
@@:     POSTPN litstr
;;;     jmp _strcomma
strcomma:                       ; @ # -- ; embed a literal string
        mov edi,ebp             ; edi points on dst string byte count
        inc ebp                 ; allocate string size
        call memcomma
        lea ecx,[ebp-1]
        sub ecx,edi             ; ecx = string size
        mov [edi],cl
        mov byte[ebp],0         ; append zero-terminator
        inc ebp
        ret

memcomma:                       ; @ # -- ; embed encoded data
        add ebx,edx             ; ebx = src string end address
        inc edx                 ; skip initial
.e:     cmp edx,ebx
        jz drop2
        mov cl,[edx]
        inc edx
        cmp cl,'\'              ; prefix \ escapes next (mainly for "_\^~)
        jne @f
        mov cl,[edx]
        inc edx
        jmp .n
@@:     cmp cl,'^'              ; prefix ^ toggles next.bit6
        jne @f
        mov cl,[edx]
        inc edx
        xor cl,$40
        jmp .n
@@:     cmp cl,'~'              ; suffix ~ toggles last.bit7
        jne @f
        xor byte[ebp-1],$80
        jmp .e
@@:     cmp cl,""""             ; ignore every " quotes
        jz .e
        cmp cl,'_'              ; substitute underscore with space
        jne .n
        mov cl,' '
.n:     HDB cl
        inc ebp
        jmp .e
;;;      0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F  String-coding:
;;; 00: ^@ ^A ^B ^C ^D ^E ^F ^G ^H ^I ^J ^K ^L ^M ^N ^O  prefix ^ toggles bit6
;;; 10: ^P ^Q ^R ^S ^T ^U ^V ^W ^X ^Y ^Z ^[ ^\ ^] ^^ ^_
;;; 20:  _  ! \"  #  $  %  &  '  (  )  *  +  ,  -  .  /  replace spaces with _
;;; 30:  0  1  2  3  4  5  6  7  8  9  :  ;  <  =  >  ?  ignore every " quotes
;;; 40:  @  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O
;;; 50:  P  Q  R  S  T  U  V  W  X  Y  Z  [ \\  ] \^ \_  prefix special with \
;;; 60:  `  a  b  c  d  e  f  g  h  i  j  k  l  m  n  o
;;; 70:  p  q  r  s  t  u  v  w  x  y  z  {  |  } \~ ^?  suffix ~ toggles bit7

lit8:   lea esi,[ebx+ebx]       ; check byte/long literal:
        xor esi,ebx             ; 2n^n to clear all sign bits
        cmp esi,$FF             ; jbe:byte ja:long
        ret
litand: HDW $E381               ; 81E3(and ebx,long) 83E3(and ebx,byte)
        jmp litadd.0
litior: HDW $CB81               ; 81CB(or ebx,long) 83CB(or ebx,byte)
        jmp litadd.0
litxor: HDW $F381               ; 81F3(xor ebx,long) 83F3(xor ebx,byte)
        jmp litadd.0
litadd: HDW $C381               ; 81C3(add ebx,long) 83C3(add ebx,byte)
.0:     call s01
.1:     call litnumd            ; -- n
        call lit8               ; jbe:byte ja:long
        ja comma                ; long immediate
        xor byte[ebp-2],2       ; byte signed immediate
ccomma: HDB bl                  ; 885D00
        inc ebp                 ; 45
        jmp drop1
litsub: HDW $EB81               ; 81EB(sub ebx,long) 83EB(sub ebx,byte)
        jmp litadd.0
litmul: HDW $DB69               ; 69DB(imul ebx,long) 6BDB(imul ebx,byte)
        call s09                ; imul:s09 add:s01
        jmp litadd.1
litdiv: call litnumd            ; -- n
        call toS0               ; ebx = TOS
        HDD $B9999352           ; 52(push edx)93(xchg eax,ebx)99(cdq)
        HDD ebx,4               ; B9(mov ecx,long)
        add ebp,8
        call lit8               ; jbe:byte ja:long
        ja @f                   ; long immediate
        sub ebp,2
        HDB $6A,-3              ; 6A(push byte)
        HDB $59,-1              ; 59(pop ecx)
@@:     mov ebx,$5A93F9F7       ; F7F9(idiv ecx)93(xchg eax,ebx)5A(pop edx)
        jmp comma
litmod: call litdiv             ; keep rem in edx instead of quo in ebx:
        HDB $5B,-1              ; 5A(pop edx) -> 5B(pop ebx)
        or byte[SC],2           ; TOS = edx
        ret

litcomma:                       ; @ # -- ; postpone HDB,HDW,HDD
        call litnumd            ; -- n
        cmp ebx,$FF
        ja @f
        bswap ebx
        mov bx,$45C6            ; C64500xx(mov byte[ebp],byte)
        HDD ebx
        add ebp,4
;       jmp drop1
drop1:  DROP1                   ; n --
        ret
@@:     cmp ebx,$FFFF
        ja @f
        HDD $45C766             ; 66C74500(mov word[ebp],word)
        HDW bx,4
        add ebp,6
        jmp drop1
@@:     HDD $0045C7             ; C74500(mov dword[ebp],long)
        HDD ebx,3
        add ebp,7
        jmp drop1

litnumd:                        ; @ # -- n ; called from other lit*
        call _number            ; -- @ # | n 0
        or ebx,ebx
        jz drop1
litdata:                        ; @ # -- xt ; called from lit@!
        call _find              ; -- @ # | xt 0
        jnz notfnd
        mov cl,byte[esi+4]
        and ecx,7               ; firewall!
        cmp ecx,1               ; 9 or 1=data, 8 or 0=code
        jnz notfnd
        jmp drop1               ; -- xt
litfetch:                       ; @ # --
        call litdata            ; -- xt
        call _over
        HDW $1D8B               ; 8B1D(mov ebx,[])
        call s08
        jmp comma
litstore:                       ; @ # --
        call litdata            ; -- xt
        HDW $1D89               ; 891D(mov [],ebx)
        call s08
        call comma
        jmp _drop

notfnd: inc ebx                 ; restore final
        pop ecx                 ; don't return from litnumd/litdata caller
VECT "notfound",_notfound       ; @ # -- ;
        call _error
        CDB "???"

litnip:
        call litnumd            ; -- n
        jmp _lit.1              ; don't call _over

litnum: inc ebx                 ; -- @ # ; restore final
        call _number            ; -- @ # | n 0
        or ebx,ebx
        jnz _notfound
        DROP1
;;;     jmp _lit
CODE "lit`",_lit                ; n -- ; -- n ; compile n as a literal
        call _over              ; over
.1:     call lit8               ; jbe:byte ja:long
        ja @f
        HDD $5B006A             ; 6A(push byte)5B(pop ebx)
        HDB bl,1                ; saves 2 bytes, status-flags unmodified
        inc ebp
        call s01
        jmp _drop1
@@:     HDB $BB                 ; BB(mov ebx,long)
        call s1
comma:  HDD ebx
        add ebp,4
_drop1: DROP1                   ; --
        ret

;;; -------------------------------------------------------
;;; compiler kernel

DATA "callmark",callmark,0      ; saves last-call address
CODE "call,",_call
        call _rst               ; xt -- ; compile a call to runtime entry
CODE "dcall,",_dcall            ; direct call - no reset
        POSTPN ebx
        mov [callmark],ebp      ; save last-call address for ;;
        jmp _drop1

DATA "tailrec",tailrec,-1       ; enables tail-recursion when non-zero
CODE ";;`",_semisemi            ; --
        cmp dword[tailrec],0
        jz .ret
        cmp ebp,[callmark]      ; preceded by a call?
        jnz .ret
        cmp dword[ebp-4],-$83   ; test for short jump offset
        jl @f                   ;
        sub ebp,3               ;
        add byte[ebp-1],3       ; offset correction
        HDB $EB,-2              ; EB(jmp byte)
        jmp _anon.0
@@:     HDB $E9,-5              ; E9(jmp long)
        jmp _anon.0
.ret:   call _rst               ; ebp=[P]
        HDB $C3                 ; C3(ret)
        inc ebp                 ;
        ret

VECT ";`",_semi                 ; -- ; who needs the interpreter anyway!
        call _rst
        mov ecx,[anon]
        cmp ecx,ebp             ; empty?
        jz _anon.0
        call _semisemi          ; close def
        jecxz _anon             ; anonymous?
        mov ebp,ecx             ; de-allocate
        call ecx                ; execute
CODE "anon:`",_anon             ; --
        mov [anon],ebp          ; start new anonymous definition
.0:     mov [callmark],0        ; disable tail-recursion optimization
        mov byte[SC],0          ; reset SC
        ;; here we could check heap space and warn if small
        ret

CODE ":`",_colon                ; <name> -- ; start named definition
        mov ecx,[anon]
        jecxz @f                ; if anonymous,
        call _semi              ; then execute it.
        xor ecx,ecx             ; ecx = 0
        mov [anon],ecx          ; mark non-anonymous
@@:     call _rst
        call _wsparse.check     ; -- @ #
        DUP2
        xor ebx,ebx             ; ebx = 0
        mov edx,ebp             ; -- @ # ebp 0
CODE "header",_header           ; @ # xt ct -- ; creates a new header
        mov ecx,[eax]           ; ecx = #
        mov esi,[eax+4]         ; esi = @
        lea eax,[eax+8]
        mov edi,[H]             ; edi = headers base
        dec edi                 ; allocate zero-terminator
        sub edi,ecx             ; allocate name
        mov [edi-1],cl          ; store #
        mov [edi-2],bl          ; store ct
        lea ebx,[edi-6]         ; allocate xt[4],ct[1],#[1]
        mov [H],ebx             ; update H
        mov [ebx],edx           ; store xt
        rep movsb               ; copy string, ends with ecx = 0
        mov [edi],cl            ; store zero-terminator
;;      jmp drop2
drop2:  xchg eax,esp            ; x y --
        pop ebx
        pop edx
        xchg eax,esp
        ret

DATA "which",which,0            ; holds last found hfa
VECT "find",_find               ; @ # -- @ # | xt 0
        mov esi,[H]             ; esi = headers pointer
.b:     lea esi,[esi+6]         ; skip over xt[4],ct[1],sz[1]
        movzx ecx,byte[esi-1]   ; ecx = string length
        jecxz .e                ; null length = headers end: stack unchanged
        cmp ecx,ebx             ; if string length differs,
        jnz @f                  ; skip string comparison:
        mov edi,edx             ;   cmpsb modifies edi, not edx
        repz cmpsb              ;   compare strings
@@:     lea esi,[esi+ecx+1]     ; skip to initial of next string
        jnz .b                  ; until match:
        sub esi,ebx             ; back to string initial +1(zero-terminator)
        lea esi,[esi-7]         ; back over xt[4],ct[1],sz[1],zt,  esi = hfa
        mov [which],esi         ; save hfa
        mov edx,[esi]           ; edx = xt
        xor ebx,ebx             ; ebx = 0 = found
.e:     ret                     ; z=found(esi=hfa) nz=notfound(ecx=0)

CSTE "tib",tib                  ; terminal input buffer
CSTE "eob",eob                  ; end-of-buffer
DATA ">in",tin,tib              ; input stream parse pointer
DATA "tp",tp,tp0                ; input stream limit pointer
CODE "wsparse",_wsparse         ; -- @ # ; white-space-parse
        DUP2                    ; -- * *
        mov edi,[tin]           ; edi = input stream parse pointer
        mov ecx,[tp]            ; ecx = input stream limit pointer
        xor esi,esi             ; zero esi, use as within-quote flag
@@:     movzx ebx,byte[edi]     ; skip whitespaces
        inc edi
        cmp edi,ecx
        ja @f                   ; for same behaviour as repz scasb in parse
        and bl,$7F
        cmp byte[_number.ct+ebx],9 ; whitespace?
        jz @b
@@:     dec edi                 ; edi = pointer on initial
        mov edx,edi             ; edx = pointer on initial
@@:     movzx ebx,byte[edi]     ; look for whitespace
        inc edi
        cmp edi,ecx
        ja @f                   ; for same behaviour as repnz scasb in parse
        and bl,$7F
        cmp bl,34               ; quote?
        jnz .0
        xor esi,1               ; yes - toggle flag
.0:     cmp esi,1               ; if within-quote,
        jz @b                   ; repeat loop
        cmp byte[_number.ct+ebx],9 ; whitespace?
        jnz @b
@@:     mov [tin],edi           ; save changed input stream pointer
        lea ebx,[edi-1]         ; ebx after final
        sub ebx,edx             ; ebx = string length
@@:     ret                     ; ebx=0 when input stream end reached
.check: call _wsparse           ; -- @ #
        jnz @b
.error: call _error
        CDB "unexpected end of source"

CODE "parse",_parse             ; separator -- @ #
        DUP1
        xchg eax,ebx            ; eax=separator ebx=dataSP
        mov edi,[tin]           ; edi = input stream parse pointer
        mov ecx,[tp]            ; ecx = input stream limit pointer
        sub ecx,edi             ; ecx = remaining input stream length
        inc ecx
        repz scasb              ; skip separators
        dec edi                 ; edi = pointer on initial
        inc ecx
        mov edx,edi             ; edx = pointer on initial
        repnz scasb             ; look for separator
        mov [tin],edi           ; save changed input stream pointer
        mov eax,ebx             ; eax=dataSP
        lea ebx,[edi-1]         ; ebx after final
        sub ebx,edx             ; ebx = string length
        ret                     ; ebx=0 when input stream end reached

@@:     xchg eax,esp            ; x y --
        pop ebx
        pop edx
        xchg eax,esp
CODE "lnparse",_lnparse         ; -- @ # ; end-of-line = LF or CR,LF
        DUP1 10
        call _parse
        jz @f                   ; at EOF; prevents ebx<0 if file ends with CR
        cmp byte[edx+ebx-1],13  ; trim carriage-return
        jnz @f
        dec ebx
        jz @b                   ; if empty line, skip it
@@:     ret

VECT "compiler",_compiler       ; --
        call _wsparse           ; -- @ # ; z=ebx==0
        jz drop2                ; end of input stream
        lea edi,[ebx+edx]
        push dword[edi]         ; save following bytes
        push edi
        mov byte[edi],'`'       ; append a backquote
        inc ebx
        call _find              ; -- @ # | found.xt 0 esi=hfa z=found
        pop edi
        pop dword[edi]          ; restore following bytes
        jnz @f
        DROP1                   ; -- found.xt
        movzx ecx,byte[esi+4]   ; ecx = ct
        and ecx,7               ; firewall!
        call [_classes+8*ecx]
        jmp _compiler
@@:     dec ebx                 ; restore initial string size
        call _find              ; -- @ # | found.xt 0 esi=hfa z=found
        jnz @f
        DROP1                   ; -- found.xt
        movzx ecx,byte[esi+4]   ; ecx = ct
        and ecx,7               ; firewall!
        call [_classes+4+8*ecx]
        jmp _compiler
@@:     call literalcompiler    ; --
        jmp _compiler

icall:  push ebx                ; immediate call: execute found.xt
        DROP1
ilit:   ret                     ; immediate literal: leave found.xt on stack
ccerr:  call _error
        CDB "undefined compiler class"
CSTE "classes",_classes         ; compiler classes table: immediate,postponed
_classes dd icall,_call         ; 0: call
        dd ilit,_lit            ; 1: literal
        dd ccerr,ccerr          ; 2: FPU-macro (see `f:` in ff.ff)
        dd 5 dup (ccerr,ccerr)  ; 3-7: undefined (add more if needed)

;;; -------------------------------------------------------
;;; memory/string utilities

;;; cmove/place are defined as macros in ff.boot for their quite frequent use.
;;; erase/fill/move/$-/search, less frequently used, are defined here:

CODE "erase",_erase             ; @ # --
        DUP1 0                  ; @ # 0 --
CODE "fill",_fill               ; @ # byte --
        xchg eax,esp            ; 94
        xchg eax,ebx            ; 93/92
        mov  ecx,edx            ; 89D1/89D9
        pop  edi                ; 5F
        rep  stosb              ; F3AA
        xchg eax,ebx            ; 93/92
        pop ebx
        pop edx
        xchg eax,esp
        ret

CODE "move",_move               ; @src @dst # -- ; safe memory-block-move
        xchg eax,esp
        pop esi                 ; esi = @src
        mov edi,edx             ; edi = @dst
        mov ecx,ebx             ; ecx = #
        cmp esi,edi
        jae @f
        dec ebx
        add esi,ebx             ; esi = @src+#-1
        add edi,ebx             ; edi = @dst+#-1
        std                     ; by decreasing addresses
@@:     rep movsb
        cld
        pop ebx
        pop edx
        xchg eax,esp
        ret

CODE "$-",_stringsub            ; @1 @2 # -- n ; n=0:match
        xchg eax,esp            ; 94
        pop esi                 ; 5E esi = @1
        mov edi,edx             ; 89D7/89DF edi = @2
        mov ecx,ebx             ; 89D9/89D1 ecx = #
        repz cmpsb              ; F3A6 esi and edi after last comparison
        movzx ebx,byte[esi-1]   ; 0FB65EFF/0FB656FF
        movzx edx,byte[edi-1]   ; 0FB657FF/0FB65FFF
        sub ebx,edx             ; 29D3/29DA -- n
        pop edx                 ; 5A/5B restore NOS
        xchg eax,esp            ; 94
        ret

CODE "$-.",_stringsubdot        ; @1 @2 # -- n ; n=0:match
        xchg eax,esp            ; 94
        pop esi                 ; 5E esi = @1
        mov edi,edx             ; 89D7/89DF edi = @2
        mov ecx,ebx             ; 89D9/89D1 ecx = #
.rc:    repz cmpsb              ; loop, stop at mismatch(nz) or match(ecx=0,z)
        movzx ebx,byte[esi-1]   ; last char compared from @1
        movzx edx,byte[edi-1]   ; last char compared from @2
        jz .se                  ; if z:match break
        cmp dl,'A'              ; non-matching, is char within A..z?
        jl .se                  ; if <'A' break
        cmp dl,'z'
        jg .se                  ; if >'z' break
        xor dl,$20              ; flip case
        cmp ebx,edx             ; match?
        jnz .me                 ; if nz:no_match break
        cmp dl,'A'              ; match, is flipped char in A..z? catch [\]^_`
        jl .me                  ; if <'A' break
        cmp dl,'z'
        jg .me                  ; if >'z' break
        jecxz .se               ; if ecx==0 break
        jmp .rc                 ; resume loop with next char
.me:    movzx edx,byte[edi-1]   ; restore unflipped char
.se:    sub ebx,edx             ; n for $-.
        pop edx                 ; 5A/5B restore NOS
        xchg eax,esp            ; 94
        ret

CODE "search",_search           ; @ # @k #k -- @r #r ; z:match, nz:fail
        mov ecx,[eax]           ; ecx=#
        mov edi,[eax+4]         ; edi=@
        xchg eax,esp
        push eax                ; save callSP
        sub ecx,ebx
        inc ecx                 ; for initial in very last position
        jle .fail
        mov al,[edx]            ; al=kInitial
.loop:  repnz scasb             ; look for kInitial
        jnz .fail
        push edi                ; edi after matched initial
        push ecx                ; ecx=remainingBytes
        dec edi                 ; back over initial
        mov ecx,ebx             ; ecx=#k
        mov esi,edx             ; esi=@k
        repz cmpsb              ; z:match
        pop ecx
        pop edi                 ; resume after initial
        jnz .loop
        lea edx,[edi-1]         ; back over initial
        lea ebx,[ebx+ecx]       ; remaining count
        pop eax                 ; restore callSP
        xchg eax,esp
        lea eax,[eax+8]         ; -- @found #remaining ; z:match
        ret
.fail:  pop eax                 ; restore callSP
        pop ebx                 ; restore @ and #
        pop edx                 ; -- @ # ; nz:failed
        xchg eax,esp
        ret

;; count a nul terminated string, keep the address
;; eg. "HOME" 1_ libc. getenv zlen type
CODE "zlen",zlen                ; @ -- @ #
        DUP1
        mov edi,edx
        xor ecx,ecx
        not ecx
        push eax
        xor eax,eax
        repne scasb
        pop eax
        not ecx
        dec ecx
        mov ebx,ecx
        ret

CODE "depth",_depth             ; -- n
        DUP1
        mov ebx,[DS0]
        sub ebx,eax
        sar ebx,2
        ret

;;; -------------------------------------------------------
;;; startup code: relocate headers from ebp^ to ^H

;;; memory map:
;;; [binary code and data> heap <headers][source code> blocks][ ]  < stacks ]
;;; :                 ebp^      ^H    tib:  tin^>  tp^     eob: ;   eax^ esp^

_start: ;; relocate headers and boot source: H->[headers]tib:[boot]<-tp
        mov esi,heads
        mov edi,H0
        mov ecx,(headers_size+boot_size)/4
        rep movsd
        ;; clear uninitialized bytes (only for convenience):
        xor eax,eax             ; nulls
        mov edi,ebp0            ; before headers
        mov ecx,(heap_size-headers_size)/4
        rep stosd
        mov edi,tp0             ; after boot source
        mov ecx,(bss_size-heap_size-boot_size)/4
        rep stosd
        ;; initialize compiler pointer registers:
        mov ebp,ebp0            ; compilation pointer
        lea eax,[esp-4096]      ; allocate CALLstack
        mov [CS0],esp           ; save for argv
        mov [DS0],-4
        add [DS0],eax           ; relocate DATAstack base address
        mov [bssend],_bssend-4
        xor ebx,ebx
        xor edx,edx
        ;; compile boot source:
if 1    ;; 0 allows ff.boot debugging, 1 saves 160 bytes
        jmp _compiler
else    ;; this allows debugging of boot source:
        ;; refs: _compiler _catch _type dotstr _read
        ;; refs: tin tib anon SC eob tp
.0:     DUP1                    ; tin and tp initially on both ends of boot
        mov ebx,_compiler
        call _catch             ; first call returns on boot compilation error
        or ebx,ebx              ; -- 0 | @ # error ; counted string address
        jz .3                   ; error=0 when no error
        mov [eax],ebx           ;  -- error * *
        mov edx,[tin]           ; look back,
        lea ebx,[edx-1]
.1:     dec edx
        cmp edx,tib             ; for tib address,
        jz .2
        cmp byte[edx-1],10      ; or for newline.
        jnz .1
.2:     sub ebx,edx             ; -- error @ #
        call _type              ; -- error ; display error context
        call dotstr
        CDB " <-Error: "        ; point on word which triggered the error
        xchg eax,esp            ; 94
        push edx                ; 52
        xchg eax,esp            ; 94
        lea edx,[ebx+1]
        movzx ebx,byte[ebx]     ; -- error+1 #
        call _type              ; -- ; display error message
        mov [anon],ebp          ; reset anon
        mov byte[SC],0          ; reset SC
.3:     call dotstr
        CDB 10,"Ok> "           ; display prompt (lowercas o in boot)
        DUP2                    ; accept user input into tib:
        mov edx,tib
        mov [tin],edx           ; setup >in
        mov ebx,eob-tib         ; -- tib eob-tib
        call _accept            ; -- n ; number of bytes accepted
        or ebx,ebx              ; exit if input empty
        jz @f
        add ebx,tib
        mov [tp],ebx            ; setup tp
        DROP1                   ; --
        jmp .0
@@:     call dotstr
        CDB "^J"                ; cleanly,
        ret                     ; return to shell.
end if

;;; ----------------------------------------------------------------------
;;; include Operating-System interface

OSINCLUDE


;;; ----------------------------------------------------------------------
;;; memory map:

;;; [binary code and data> heap <headers][source code> blocks][ ]  < stacks ]
;;; :                 ebp^      ^H    tib:  tin^>  tp^     eob: ;   eax^ esp^

        align 4
heads:  GENWORDS                ; generate all postponed headers
        align 4
    headers_size = $-heads
boot:   file "ff.boot"          ; boot source code, initially moved to tib
        OSFILE                  ; embed also OS-specific boot code
        align 4
    boot_size = $-boot

;if defined ffdl
section '.bss'
;    ebp0 = bss                  ; headers_size+boot_size are "lost"
;else
    ebp0 = heads                ; headers_size+boot_size are recovered
;end if

bss     rb 1024*512             ; code and data -> heap <- headers
tib     rb 1024*256             ; terminal input and blocks buffer
eob     rb 1024                 ; temporary scratch area
_bssend:                        ; segmentation fault after this address.

    bss_size = $-bss
    heap_size = tib-bss

    H0 = tib-headers_size       ; initial head of headers
    tp0 = tib+boot_size         ; initial end of (boot) source

;;; That's all folks!!
