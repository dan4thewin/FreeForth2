# Criticism of FreeForth
***Dan Good, 30 June 2024***

I encountered this criticism of FreeForth long after it was written.
As pointed out in a response, conditionals in FreeForth don't follow the
usual Forth conventions.  The FreeForth help file documents this, even
in version 0.8, although the primer wouldn't appear for another 2 years.
However, the segfault and infinite loop really caught my attention.
This doc presents the criticism and my exploration of the issue,
and the changes I decided to make in FreeForth2 as a result.

> ## FreeForth ( From http://lambda-the-ultimate.org/node/2452 )
>
> FreeForth is another good one for learning implementation. It
> includes some very subtle tricks to keep the code terse and fast,
> at the cost of abandoning standards. (Most obviously: you have to
> close even interpreted command lines with a semicolon.)
>
> By Julian Morrison at Fri, 2007-09-14 14:21
>
> ### I don't buy it.
>
> FreeForth looked interesting because it claimed to be a self-hosting,
> incremental, native i386 compiler. That is, it was interesting,
> until I discovered that it is profoundly broken, failing even the
> simplest of smoke tests. My very first attempt at writing a subroutine
> (GCD) eventually uncovered at least three, and possibly more (!)
> bugs.
>
> [Edit: for readability I moved the output up so that it's on the same
> line as it's expression]
>
>     lpsmith@nimrod:~/languages/forth/ff $  ./ff
>     Loading'ff.ff: help normal .now {{{ +longconds f. hid'm
>     FreeForth 0.8 <http://christophe.lavarenne.free.fr/ff>  Try: help
>      0; : show IF ."T" ELSE ."F" THEN ;
>      0; 0 0=  show ;                    \ T
>      1; 1 0=  show ;                    \ T
>      2; 0 0=  IF ."T" ELSE ."F" THEN ;  \ F
>      3; 1 0=  IF ."T" ELSE ."F" THEN ;  \ F
>      4; 0 0 = show ;                    \ F
>      6; 1 0 = show ;                    \ T
>      8; 0 1 = show ;                    \ T
>     10; 1 0 = show ;                    \ F
>     12; 0 0 = IF ."T" ELSE ."F" THEN ;  \ T
>     14; 1 0 = IF ."T" ELSE ."F" THEN ;  \ F
>     16; 0 1 = IF ."T" ELSE ."F" THEN ;  \ F
>     18; 1 1 = IF ."T" ELSE ."F" THEN ;  \ T
>
>     20; : display IF 42 . ELSE 63 . THEN ;
>     20; 0 0 = display ;                \ 63
>     22; 0 0 = IF 42 ELSE 63 THEN . ;   \ 42
>     24; 0 0 = IF 42 . ELSE 63 . THEN ;
>     42 Segmentation fault (core dumped)
>
>     lpsmith@nimrod:~/languages/forth/ff $  ./ff
>     Loading'ff.ff: help normal .now {{{ +longconds f. hid'm
>     FreeForth 0.8 <http://christophe.lavarenne.free.fr/ff>  Try: help
>      0; : display IF 42 . ELSE 63 . THEN ;
>      0; 0 0= IF 42 . ELSE 63 . THEN ;      \ 63
>      1; 0 0= display ;
>     42 42 42 42 42 42 42 42 42 42 42 42 42 42 42 42 42 42 42 42 ... ^C
>
>     lpsmith@nimrod:~/languages/forth/ff $  cd ..
>     lpsmith@nimrod:~/languages/forth $  rm -rf ff
>
> It's obvious that this implementation hasn't been used for anything
> other than the (admittedly cute!) Towers of Hanoi animation that
> is included. Moreover, you can't run many standard Forth programs
> on FreeForth, and furthermore, a few of ways that FreeForth diverges
> from standards are very misguided. The combined result is positively
> underwhelming.
>
> None of the author's claims are believable. How can you possibly
> implement a self-hosting incremental compiler if you don't have
> propositional logic working, missing the ability to reliably jump
> to the correct destination, and lacking an assembler? And how can
> you know that it is fast, if the only working, interesting example
> is not computationally demanding?
>
> By Leon P Smith at Fri, 2008-04-11 08:44
>
> ### How about reading the documentation?
>
> You shouldn't make such claims before reading the documentation.
> FreeForth indeed is different from other implementations, especially
> in the area of flow control, but it is definitely not "profoundly
> broken". How about reading what help IF and help conditionals have
> to say? The only thing your code demonstrates is the fact that you
> expected conditionals in FreeForth to work like in most other Forths
> and didn't bother dig deeper. Look:
>
>
>     0; 0 0- drop IF ."T" ELSE ."F" THEN ;
>     F 0; 1 0- drop IF ."T" ELSE ."F" THEN ;
>     T 0; 0 0 = 2drop IF ."T" ELSE ."F" THEN ;
>     T 0; 0 1 = 2drop IF ."T" ELSE ."F" THEN ;
>     F 0; : show 0- drop IF ."T" ELSE ."F" THEN ;
>     0; 0 0- drop BOOL show ;
>     F 0; 1 0- drop BOOL show ;
>     T 0; 0 0 = 2drop BOOL show ;
>     T 0; 0 1 = 2drop BOOL show ;
>     F 0;
>
> About your other claims, well, from the point of language design
> and implementation FreeForth is one of the most interesting
> minimalistic constructs available for our dissection. You are at a
> loss for dismissing it like that. Besides, being different or even
> weird was always an integral part of what Forth is all about.
>
> By Nike at Thu, 2008-04-24 10:21
>
> ### Sorry about my tone, but I stand by the content.
>
> I apologize for the harsh tone of my original post. However, I stand
> by my assessment. I read the documentation, and I used the help
> command extensively. I spent probably two or three hours trying to
> figure out what I was doing wrong, only to conclude I was doing
> nothing wrong, once I started checking that basic things work,
> something I normally take for granted.
>
> I don't care if the comparison operators don't drop their arguments:
> that's a legit design decision, although sticking with standards
> means you can test your implementation against others, which is a
> big win for quality control.
>
> However, if you call this lack of referential transparency a "feature"
> and not a "bug", then you've proved my "profoundly misguided" point
> for me. Moreover, comparison operators really should push their
> results onto the stack, conceptually even if not in reality. A real
> compiler can optimize away these stack operations pretty easily.
>
> Moreover, I doubt this really is a feature, given the core dump and
> the mysterious infinite loop. There is something seriously wrong
> with words in FreeForth.
>
> I've played with Jones Forth a bit. It's very minimal, and the first
> thing I suggest doing is adding a stack underflow check. However,
> it works, it's instructive, and it is quite worthy of LtU. FreeForth
> is none of these.
>
> By Leon P Smith at Mon, 2008-07-14 23:16

# A Word About Conditionals

The [primer](FreeForth_Primer.md) has this to say:

> _Forthers note FreeForth control structures are quite different from
> other Forth dialects, mainly because conditional jumps test the i386
> processor flags resulting from the last arithmetic or logic operation,
> and don't pop the DATAstack top (whereas most other Forth dialects test
> and pop the DATAstack top item); this requires some extra drop but saves
> code space and run time._
> [...]
> The condition specifiers [...] select _at compile time_ the conditional
> jump assembly instruction which will _at run time_ check the i386
> processor flags resulting from the last arithmetic or logic operation

Even after reading this, I failed to grasp the full implications. `IF`
captures the conditional.  One `IF` generates different code than another
`IF` based on whichever condition occurs earlier in the definition.
By itself, `0=` generates no code but instead saves the comparison to
be used later by `IF` (or `BOOL`, `UNTIL`, `?`, etc.).  An `IF` without
a condition is the same as `0<> IF`.  Equally important, an operation
must set the processor flags.  Pushing a `0` on the stack leaves the
flags unchanged.  The word `0-` compares the top of stack with zero and
sets the flags.

The code offered by the critic lacks both of these understandings.
Since these mistakes seem easy to make, I've changed FreeForth2 to do
away with the default condition.  Now, every condition must be explicitly
provided or an exception occurs.  I hope this alerts any newcomer to the
subtleties involved.

     0; : show IF ."T" ELSE ."F" THEN ;
    : show IF <-error: is not preceded by a condition

I see nothing misguided about `IF` referencing the processor flags.
This simply surfaces a design decision of the hardware rather than hiding
it away under Boolean semantics.

# A Bug?!?

FreeForth happily lets you do questionable things.  I breathed a great
sigh of relief once I added a segfault handler to FreeForth2.

     0; 0 !
    0 ! ; <-error: SEGV caught

On first seeing the critic's segfault, I thought something in the written
line caused it, but I saw nothing so dire.  I turned my attention to the
infinite loop.  Eventually, I remembered the tail recursion optimization.
The [primer](FreeForth_Primer.md) says:

> Both `;` (semicolon) and `;;` (double semicolon) compile a `ret` assembly
> instruction, unless they are preceded by a `call` assembly instruction,
> that they change into a `jmp` assembly instruction: this is called tail
> recursion optimization. This may be used for simple loops jumping back
> to the definition entry point

The [help](/ff.help) file adds:

> this may be switched off/on permanently by storing a null/non-null value
> into "tailrec", or may be inhibited just once by storing a null value into
> "callmark"

Finally, a disassembly using gdb revealed the problem.

     0; : display 0<> IF 42 . ELSE 53 . THEN ;
     0; 1 0- display ; / prints "42 " endlessly

    0x804d7d4       je     0x804d7e5    ; display - jump to ELSE if Z flag set
    0x804d7d6       xchg   esp,eax
    0x804d7d7       push   edx
    0x804d7d8       push   0x2a
    0x804d7da       pop    edx          ; 42 to TOS
    0x804d7db       xchg   edx,ebx      ; rearrange registers (preamble)
    0x804d7dd       xchg   esp,eax
    0x804d7de       call   0x804c816    ; call .
    0x804d7e3       jmp    0x804d7f2    ; jump to after THEN
    0x804d7e5       xchg   esp,eax
    0x804d7e6       push   edx
    0x804d7e7       push   0x35
    0x804d7e9       pop    edx          ; 53 to TOS
    0x804d7ea       xchg   edx,ebx      ; rearrange registers (preamble)
    0x804d7ec       xchg   esp,eax
    0x804d7ed       jmp    0x804c816    ; jump to .
    0x804d7f2       xchg   esp,eax      ; anonymous function
    0x804d7f3       push   edx
    0x804d7f4       push   0x1
    0x804d7f6       pop    edx          ; 1 to TOS
    0x804d7f7       or     edx,edx      ; 0-
    0x804d7f9       xchg   edx,ebx      ; rearrange registers (preamble)
    0x804d7fb       xchg   esp,eax
    0x804d7fc       jmp    0x804d7d4    ; jump to display

The jump meant to skip over the `ELSE` clause lands at the beginning of
the anonymous function that calls `display`, running it again resulting
in an endless loop.

Without the tail recursion optimization `jmp 0x804c816` would instead be
`call 0x804c816` followed by `ret` and the forward jump lands on the `ret`.

The segfault likewise results from a jump to where a `ret` should have
been, landing in empty space after the anonymous function and eventually
finding garbage.

     0; 0 0 = IF 42 . ELSE 63 . THEN ;

    0x805012f       jmp    0x805013d
    0x8050131       push   edx
    0x8050132       push   0x3f
    0x8050134       pop    edx
    0x8050135       xchg   edx,ebx
    0x8050137       xchg   esp,eax
    0x8050138       jmp    0x804e7e2
    0x805013d       add    BYTE PTR [eax],al
    0x805013f       add    BYTE PTR [eax],al
    0x8050141       add    BYTE PTR [eax],al
    0x8050143       add    BYTE PTR [eax],al
    0x8050145       add    BYTE PTR [eax],al
    0x8050147       add    BYTE PTR [eax],al

With the earlier FreeForth versions, avoid the bug by either disabling
the optimization globally, `0 tailrec!`, or locally with `0 callmark!`:

    $ ./ff
    Loading'ff.ff: help normal .now {{{ +longconds f. hid'm
    FreeForth 0.8 <http://christophe.lavarenne.free.fr/ff>  Try: help
     0; : ret;` 0 callmark! ;` ;
     0; 0 0 = IF 42 . ELSE 63 . THEN ret;
    42  2;

Freeforth2 fixes the bug by disabling the optimization for a call
immediately preceding a THEN, REPEAT, UNTIL, or END.

# Passing Judgement

The critic thinks that due to the existence of the bug it's impossible to
do meaningful work with FreeForth.  I rather think Christophe Lavarenne
never encountered the bug given the way he coded.

    0; : show IF ."T" ELSE ."F" THEN ;

This first line from the critic's code uses the idiomatic dot-string.
This inlines the string to type after a call to `dotstr` (see
[ff.asm](/ff.asm)) and does not trigger the bug.

Instead of writing

    0; : display IF 42 . ELSE 63 . THEN ;

had the critic written

    0; : display IF 42 ELSE 64 THEN . ;

then the tail recursion optimization would work as intended.

I see only a few cases in the FreeForth 1.2 code base of a definition
ending in `THEN` but none are preceded by a call.

While the bug presents a hazard to a newcomer, I see no reason it would
have impeded Mr. Lavarenne in his endeavors.  Nevertheless, I'm glad
it's fixed in FreeForth2.

## PS

As I'm adding the fix to the `longconds` code, I see that the
RetroForth/Reva/HelFORTH compatibility words already have it.
I'll consider that posthumous approval.
