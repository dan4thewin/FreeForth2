;;; fflin.asm  FreeForth kernel, Linux specific port
;;; $Id: fflin.asm,v 1.3 2006-12-12 01:33:56 lavarenn Exp $

;;; -------------------------------------------------------
;;; Typical compile command (with http://flatassembler.net):
;;; if ffdl ; i.e. with dynamic-link-library support
;;;   fasm fflin.asm ff.o
;;;   gcc ff.o -o ff -s -rdynamic -nostartfiles -ldl
;;;   # or: ld -o ff ff.o -ldl --dynamic-linker /lib/ld-linux.so.2 -s
;;; else
;;;   fasm fflin.asm ff
;;; end if

;;; -----------------------------------------------------------------------
;;; OSFORMAT specifies the Operating-System specific executable file format

macro OSFORMAT {

ffdl=1                  ; withDynamicLinkLibrary support; commented=without

if defined ffdl

format elf
section '.flat' writeable executable
public _start

else

format elf executable           ; no extrn with this format
entry _start

end if

}

;;; BSSSECTION: linkable builds use section '.bss'; flat executables
;;; need no directive — rb at end of segment gets MemSiz > FileSiz.

macro BSSSECTION { section '.bss' }

;;; -----------------------------------------------------
;;; OSINCLUDE defines OS-specific ASM source to "include"

macro OSINCLUDE { include "fflinio.asm" }

;;; -----------------------------------------------------
;;; all macros ready: compile all:

include "ff.asm"

;;; That's all folks!!
