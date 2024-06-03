> [!NOTE]
> This page preserves the writings of Christophe Lavarenne (1956-2011) about FreeForth.  
> FreeForth2 differs from the original in certain details called out in notes below.

# FreeForth Home

## Bonne Année ! Happy New Year! Feliĉan Novjaron!

Public domain releases for Linux/i386 and Windows/i386:

* (10-12-15) [FreeForth Primer](ffprimer.md) a tutorial for beginners and Forth geeks
* (09-09-03) [FreeForth Code Generation](ffcodegen.md), a case study
* (10-01-04) [FreeForth v1.2 (ff100104.zip)](http://christophe.lavarenne.free.fr/ff/ff100104.zip)
  with new: `malloc` `free` `lseek` (added in ff.ff)

Contents of this page:

*   [Whatzat?](#what-is-this)
*   [Historical Notes](#historical-notes)
*   [Language Design Notes](#language-design-notes)
*   [Compiler Implementation Notes](#compiler-implementation-notes)
*   [Thanks](#thanks)

_Have fun!_

Previous public domain releases for Linux and Windows:

* [1.2 (09-09-03)](http://christophe.lavarenne.free.fr/ff/ff090903.zip)
  with 512K heap and new: `openw0` `` f1/` `` `sqrt` (and signed `` >>` ``)
* [1.1 (09-06-15)](http://christophe.lavarenne.free.fr/ff/ff090615.zip)
  byte reordering (`` bswap` `` `` flip` ``), carry testing (`` C1?` ``  `` C0?` `` ), field-used ff43.ff
* [0.9 (07-01-09)](http://christophe.lavarenne.free.fr/ff/ff070109.zip)
  with serial interface; corrected `?ior`/Win with ff43 interactive assembler for TI's MSP430 micro-controllers
* [0.8 (06-12-31)](http://christophe.lavarenne.free.fr/ff/ff061231.zip)
  with full-blown floating-point wordset, and filename-quote-initial expansion
* [0.7 (06-12-15)](http://christophe.lavarenne.free.fr/ff/ff061215.zip)
  with optional long conditionals, and hanoi example satisfies winxp CreateProcessA constraint (was bugging `shell`)
* [0.6 (06-06-25)](http://christophe.lavarenne.free.fr/ff/ff060625.zip)
  main revisited words: `header` `compiler` `classes`
* [0.5 (06-05-31)](http://christophe.lavarenne.free.fr/ff/ff060531.zip)
  with DLL interface revisited, supports console colors
* [0.4 (06-05-28)](http://christophe.lavarenne.free.fr/ff/ff060528.zip)
  with Retro/Reva/HelFORTH-compatible control structures,

Previous public domain releases for Linux/i386 only:

* [0.3 (06-05-22)](http://christophe.lavarenne.free.fr/ff/ff060522.zip) with access to DLLs
* [0.2 (06-05-14)](http://christophe.lavarenne.free.fr/ff/ff060514.zip) mostly in FreeForth
* [0.1 (06-05-08)](http://christophe.lavarenne.free.fr/ff/ff060508.zip) mostly in assembler

## What is this?

FreeForth is an interactive development environment for programmers fed up with fat/slow/proprietary/blackbox
development environments.

It is _very_ small and _very_ fast, completely _free_ and fully _open source_:

*   _very_ small: the executable is less than 16 kilobytes, and if you look inside, it's 40% binary code and 60%
embedded source text
*   _very_ fast: being so small, it surely fully runs inside the i386 on-chip cache memory (the fastest one); it
instantly compiles compact and efficient native i386 code, _incrementally_ i.e. you can edit/compile/execute code on
the fly repeatedly, which is ideal for debugging and intensive testing
*   completely _free_: its public domain license is the most permissive, although you may want to pay me for custom
developments or support
*   fully _open source_: it's so small and well documented (>100 K of online help) that it's easy to fully understand
and customize to your needs

It is now supported under Linux and Windows, thanks to [fasm](http://flatassembler.net), with a tiny compatibility
layer for file-I/O and dynamic-link-libraries interface.

It will also be the base for several incremental cross-compilers for microcontrollers (such as 8051s, PICs, and
MSP430s) and digital signal processors (such as ADSP-218x and ADSP-BF53x).

You're welcome to use FreeForth in any way, at your own risks as usual, or to contribute in any way to its
development. Thanks if you do.

## Historical Notes

"FreeForth" is the name I've given to a long series of Forth umbilical development environments that I've been
designing and using for years for developing real-time applications for embedded systems based on microcontrollers
and digital signal processors.

It all began with the article about Forth in the Byte magazine of august 1980. Then Loeliger's book "Threaded
Interpretive Languages" (Mc Graw Hill, ISBN 0-07-038360-X) gave good insights in a Z80 implementation.

With time and experience with lots of other languages, including interactive (among which Lisp and Smalltalk), and
with Forth cross- and meta-compilers, I wanted, and realized, ever simpler and more interactive cross-compilers:
they now have no interpreter (although well interactive), no vocabularies, and no clumsy POSTPONE (although defining
macros has never been easier). But they were still hosted by "standard" Forth systems (thanks Gforth and W32for)
and I wanted a consistent development system across "host" and "target": this FreeForth version is for i386 hosts
under Linux and Windows.

This public domain FreeForth version was inspired by RetroForth minimalism: a minimal bootstrap compiler, assembled
with fasm to support operating system portability, compiles executable-embedded Forth source up to a full featured
interactive Forth development environment. Although this relies on fasm (which is an excellent macro-assembler),
this is a good shortcut compared with meta-compilation.

But I wasn't pleased with RetroForth registers allocation: popping the stack is easy with "lodsd" (EAX=\*ESI++),
but pushing it isn't as easy and too expensive in code space to be inlined. FreeForth registers allocation, detailed
hereunder, saves lots of both code space and processor cycles.

I also wanted to keep the number of source files to a minimum to support both Linux and Windows (I avoid using Windows,
but I recognize that some others can't):

Common files:
*   [LICENSE](http://christophe.lavarenne.free.fr/ff/LICENSE)
    the public-domain granting license
*   [README](http://christophe.lavarenne.free.fr/ff/README)
    short presentation of the other files, and installation instructions
*   [ff.asm](http://christophe.lavarenne.free.fr/ff/ff.asm)
    main assembler source, defines FreeForth core compiler
*   [ff.boot](http://christophe.lavarenne.free.fr/ff/ff.boot)
    FreeForth source, main core boot code embedded in FreeForth-executable
*   [ff.ff](http://christophe.lavarenne.free.fr/ff/ff.ff)
    FreeForth source, utilities automatically compiled at boot
*   [ff.help](http://christophe.lavarenne.free.fr/ff/ff.help)
    text file, provides online help with source code for almost all words
*   [bed.ff](http://christophe.lavarenne.free.fr/ff/bed.ff)
    FreeForth source, RetroForth-like minimalist block-editor
*   [hanoi](http://christophe.lavarenne.free.fr/ff/hanoi)
    FreeForth example source of a small demonstration program, text-console based interactive game with animation,
    non-recursive implementation of the classical "Hanoi Tours" problem, conditionally compilable into four versions
    with increasing animation effects

Linux-specific files:
*   [fflinio.asm](http://christophe.lavarenne.free.fr/ff/fflinio.asm)
    assembler source, file-I/O and dll-interface
*   [fflin.boot](http://christophe.lavarenne.free.fr/ff/fflin.boot)
    FreeForth source, complementary boot code embedded in FreeForth-executable
*   [fflin.asm](http://christophe.lavarenne.free.fr/ff/fflin.asm)
    top assembler source, defines macros configuring ff.asm for Linux
*   [ff](http://christophe.lavarenne.free.fr/ff/ff)
    ELF executable, compiled from fflin.asm
*   [hello](http://christophe.lavarenne.free.fr/ff/hello)
    example of "#!"-auto-executable FreeForth-script file

Windows-specific files:
*   [ffwinio.asm](http://christophe.lavarenne.free.fr/ff/ffwinio.asm)
    assembler source, file-I/O and dll-interface
*   [ffwin.boot](http://christophe.lavarenne.free.fr/ff/ffwin.boot)
    FreeForth source, complementary boot code embedded in FreeForth-executable
*   [ffwin.asm](http://christophe.lavarenne.free.fr/ff/ffwin.asm)
    top assembler source, defines macros configuring ff.asm for Windows
*   [ff.exe](http://christophe.lavarenne.free.fr/ff/ff.exe)
    Windows console-executable, compiled from ffwin.asm

Development environments:
*   [ff43.ff](http://christophe.lavarenne.free.fr/ff/ff43.ff)
    FreeForth source, interactive assembler for TI's MSP430 micro-controllers

The following chapters explain some central ideas behind FreeForth and its implementation; you'll also find most
of this text at the beginning of ff.asm.

## Language Design Notes

FreeForth is a _context-free_ implementation of the Forth language:

*   no interpret/compile STATE variable, but instead _anonymous definitions_
*   no prefix compiler-overriders, but instead _backquoted macros_
*   no input conversion BASE variable, but instead literal _base markers_

Moreover, FreeForth generates efficient "subroutine-threaded" native code:

*   with primitives implemented as macros generating i386 code inline
*   almost SWAP-free thanks to compile-time renaming of the two registers caching the top two DATAstack cells
*   with optimized tail-recursion, compiling short jumps where possible
*   with a highly flexible _literal compiler_ accepting binary-op suffixes
*   with variables and constants generated inline as literals
*   with constant-expressions reduction (not yet implemented)
*   with immediate-to-direct addressing-mode automatic conversions by the memory and arithmetic primitives (not
yet implemented)

FreeForth also natively implements and uses "throw"/"catch" for its compiler (or user application) exception handling,
with error context display. FreeForth also accepts input from the command line and from redirected stdin, and supports
executable source files: see the example file [hello](http://christophe.lavarenne.free.fr/ff/hello). FreeForth
also offers _online help_ documenting its implementation details.

FreeForth is a STATE-free implementation of the Forth language: in usual Forth systems, the STATE variable tells
the main loop whether to interpret every parsed word (i.e. execute its _run-time semantics_), or to compile
it (i.e. execute its _compile-time semantics_). FreeForth main loop always compiles, but is still interactive
thanks to "anonymous definitions" (aka "adef"): regular "named" definitions are open by `:` and closed by `;`
which automatically opens an adef, which is closed either also by ; or by any header-creating word (`:` `create`
etc.). When an adef is closed, the compilation pointer is automatically reset to its value when the adef was open,
and the adef is executed: this gives user interactivity, and opens a way to simpler compilation optimizations,
freed from the usual complexity of STATE (often "smart") handling.

However, users of usual Forth systems may be surprised by the unusual need to close a FreeForth adef with a `;`
(after trying `1 2 + .` and not seeing the expected `3` answer, some have thought FreeForth isn't worth another
try). However, as soon as they understand, `1 2 + . ;` (with a final `;`) indeed displays `3`, and they can even
try adefs with control structures (which can't be interpreted by usual Forth systems) such as `4 TIMES r . REPEAT ;`
which simply displays `3 2 1 0`.

> [!TIP]
> FreeForth2 automatically terminates an anonymous definition with ` ;` at the end of the line.
> To continue an anonymous definition onto the next line, use `\`.

FreeForth is almost PREFIX-free: apart from the main loop, only a few FreeForth words parse the input source:

*   parse primitives: `parse` `wsparse` `lnparse`
*   commenting words: `\` until end of line, `(` until `)`, and `EOF` until end of file
*   headers-handling words: : `create` `needs` `mark` etc.
*   and conditional compilation words: `[IF]` `[ELSE]` `[THEN]` etc.

Usual Forth systems use other prefix words (which parse the input source to override the main loop default behavior),
which FreeForth implements more conveniently:

*   usual quotes (and dot-quotes) are replaced with the SPACE-free _literal compiler_ (see next paragraph)
*   usual \['\] is replaced by postfixed `'` which replaces the call compiled just before it by an inline literal
(or throws an exception if no call was compiled just before it)
*   usual \[COMPILE\] aka \[POSTPONE\] is replaced with backquoted macros: macros, i.e. words to be immediately
executed at compile time, must be defined (mainly by `:`) with a final backquote appended to their name; after
parsing a word from the input source (between delimiters among NUL HT LF VT FF CR and space), the main loop
first appends a backquote to the word before looking for it in the headers (i.e. symbol table): if it is found
with an appended backquote, the code the header points to is immediately executed (this is a "macro" behavior);
otherwise, the main loop removes the appended backquote, and looks again for it in the headers: if it is found
without an appended backquote, a call is compiled if the header is marked (mainly by `:`) to point to code, or an
inline literal is compiled if the header is marked (by `create` and derivatives) to point to data (or by `constant`
to contain a constant value); otherwise, the main loop passes the word to the _literal compiler_, which may throw
an exception if it fails.

Backquoted macros are very convenient to define new macros: see
[ff.boot](http://christophe.lavarenne.free.fr/ff/ff.boot)

> [!TIP]
> FreeForth2 permits space characters within strings.

FreeForth _literal compiler_ is SPACE-free for strings, and BASE-free for numbers. It interprets the literal final
character as follows:

*   a final `"` marks a string:
    *   if the initial is a `,` the string is inlined with neither preceding call nor count (useful to inline any
        binary code or data)
    *   if the initial is a `"` a call to quotes-runtime is compiled
    *   if the initial is a `.` a call to dot-quote-runtime is compiled
    *   if the initial is a `!` a call to exception-runtime is compiled
    
    then the source string is converted (see \_number and "String-codings" \[in ff.asm\] for special characters)
    and compiled into a literal counted-string; when later executed, the quotes-runtime will push on the DATAstack
    the compiled string base address and count, whereas the dot-quotes-runtime will display the compiled string
    (with `type`), then both will resume execution after the compiled string, whereas the exception-runtime will pass
    the counted-string address to `throw` to raise an exception to be `catch`ed, either by user code, or by default
    by the top-level loop to display it as error message
*   a final binary operator character (among `+-\*/%&|^` as in C) attempts to convert the rest of the string as a
    number (see next item), and compiles the corresponding 386 instruction(s) with immediate addressing and with
    the converted number as immediate argument
*   otherwise, the _literal compiler_ attempts to convert the full string into a number, starting by default with
    a decimal conversion base, which may be overridden as follows:
    *   `$` changes conversion base to 16 (hexadecimal)
    *   `&` changes conversion base to 8 (octal)
    *   `%` changes conversion base to 2 (binary)
    *   `#` changes conversion base to the number converted so far
    
    For example, all the following literals represent the same number: `18` `$12` `&22` `%10010` `3#200` `12#16`
    `%10&2`  
    More complex base changes are possible, as already implemented for date and/or time conversion:
    `2006-5-6\_17:42:15` (see \_number \[in ff.asm\])

FreeForth compiler generates efficient "subroutine-threaded" code with primitives implemented as macros generating
native 386 code inline: see the following "Compiler implementation notes".

FreeForth offers both a minimalist set of flow-control words (`:` `;` `?`), which may be used on its own, and a
richer set of generalized flow-control words supporting nestable control-structures and exception handling. These
flow-control words are very flexible and efficient, but somewhat unusual, so be sure to read the online help on the
"conditionals" and "flow-control" topics before using them.

For those who are used to RetroForth/Reva/HelFORTH minimal control-structures, a compatibility wordset may be
conditionally compiled in ff.ff

Yes, an _online help_ documents all usable words, and even gives their source code (these comment mainly the boot
source file, which is otherwise comment-less for executable-embedding compacity).

FreeForth is also designed with interactive umbilical cross-compilation in mind, with "host" and "target" compiler
contexts switchings simpler than usual implementations (not yet implemented).

## Compiler Implementation Notes

We recognize that Forth is a virtual-machine with LIFO sequentially-accessed registers, mostly implemented
on real-machines with index-accessed registers: native instructions of most processors include bitfields for
"register-indexes", that most Forth implementations use with almost always the same register(s). Instead, FreeForth
uses this "free" resource by allocating two real registers to the two DATAstack top cells, and by swapping these two
registers indexes at compile-time (so-called "register renaming") instead of swapping their contents at run-time:
this is an easy and efficient optimization, which encourages the almost "free" use of swap to implicitly select
"the other" register, and which implied new pop-less conditional jumps (see "conditionals" and "flow-control"
online help topics) which also allow a good reduction of push/pops operations around them.

Registers allocation:

*   `esp` is the regular CALLstack pointer, or alternate DATAstack pointer.
*   `eax` is the regular DATAstack pointer, or alternate CALLstack pointer.
*   Alternate pointers are used to efficiently push and pop the DATAstack.  
    `xchg eax,esp` is used to switch between regular and alternate pointers.
*   `ebx` is the regular top of stack (T), or alternate second of stack (S).
*   `edx` is the regular second of stack (S), or alternate top of stack (T).
*   Alternate T and S are used to efficiently replace every runtime `swap` with compile
    time exchange of register names in generated instructions.  
    `xchg ebx,edx` is used to restore the regular registers T and S.
*   Regular pointers and registers MUST be (and are) restored by the compiler before
    every call or ret (this is mainly done by `rst`).
*   `ebp` is the compilation pointer.

The memory map is allocated as follows:

    [binary code and data> heap <headers][source code> blocks][ ]  < stacks ]
    :                 ebp^      ^H    tib:  tin^>  tp^     eob: ;   eax^ esp^

*   Space is already allocated by the operating system's loader for the stack, with esp already pointing at its
    "bottom"; 4Kbytes are reserved for the CALLstack, and eax is initialized pointing at the bottom of the DATAstack.
*   Compiled binary code and data are appended just after fasm-generated code.
*   Headers are separately compiled backwards, just before fasm's headers.
*   Boot source code, and then user command lines, are stored at `tib`.
*   `needs` reads its source file's entire contents just after the current source code stored at `tib` and evaluates
    it (`tib` is a "file stack").
*   The blocks editor (see bed.ff) alternatively uses the memory located 128K bytes after `tib` as 512-bytes blocks,
    each seen as 8 lines of 64 characters each.

Each header is structured as follows:

*   offset 0: 4 bytes: pointer to code or data, or constant value
*   offset 4: 1 byte: header type: 0=code, 1=data/cste, 2-7=user
*   offset 5: 1 byte: name size
*   offset 6: size bytes: name string
*   offset 6+size: null byte (zero-terminator for operating-system calls)

There is no need for the usual "link" field and "last" variable, because headers are stored backwards, then the
`H` variable, which is the headers-space allocation pointer, also points on the base address of the last defined
header (as "last" used to), and to skip over a header (to the previously defined one), just add 7 and its name
size to its base address.  Headers generation by fasm is postponed by the WORD assembler macro (and derivatives)
by redefining the GENWORDS assembler macro such that, when it is executed at the assembler source end, all headers
are generated forwards (from low to high memory) but in reverse order, from last to first defined, which corresponds
to the desired backwards layout (from high to low memory) in the order from first to last defined.

Headers are generated just after all other assembled code and data, followed by the boot source code, directly
included in the executable file for easy access required prior to loading from a separate file. Headers and boot
source are moved at startup from there to their final location: headers before `tib`, and boot source after `tib`,
ready for initial compilation. The boot source last definition is anonymous, and compiled into a single jump to the
main loop `boot` definition, and therefore may be safely overwritten by following compilations. The `boot` definition
takes care of executing the command line before displaying the welcome banner and entering the user interaction loop.

## Thanks

Chuck Moore [(http://www.colorforth.com)](http://www.colorforth.com) invented the Forth languages, and put them in
the public domain, for the great fun of lots of fans, including me. My experience working with him and sponsoring
his work on OKAD during 1995 and 1996 to produce the v21 was also great fun... until he shot me and my associate
sponsors in the back, and spat at me nasty xenophobian arguments. It was great deception about the man. He never
apologized. Other fans, you're warned now...

Rod Crawford, who likes hot spices so much, after our discussions about FreeForth anonymous definitions, published
in EuroForml'88 "Who needs the interpreter anyway?" introducing some of the idea.

Francis Cannard _est tombé dans le Forth quand il était petit, et ne s'en est jamais remis depuis :-)_ Since 1991,
we've shared many thoughts, trips, companies, successes, and failures. He instigated my desire to bear to life one
more FreeForth, this one. He finally convinced me of the interest to use two stack top cache registers instead of one.

Anton Ertl [(http://www.complang.tuwien.ac.at/~anton)](http://www.complang.tuwien.ac.at/~anton) grows up Gforth,
which I've been using since late 2000 to port to Linux my ADSP-218x and ADSP-BF53x FreeForth umbilical development
environments, in-flash token-threaded virtual machines, and real-time DSP-embedded operating systems, that I've
presented to [EuroForth2004](http://christophe.lavarenne.free.fr/ef2004.pdf).

Charles Childers [(http://retroforth.org)](http://retroforth.org) makes so simple a Forth implementation based on
FASM, which inspired this new FreeForth.

Tomasz Grysztar [(http://flatassembler.net)](http://flatassembler.net) makes FASM so good, including at macros,
and well documented.

- - -

[CL](http://christophe.lavarenne.free.fr/index.html)101215
