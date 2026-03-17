;;; fflins.asm  FreeForth i386 kernel, static (linker-free) build
;;;
;;; Same as fflin.asm but with ffdl commented out.
;;; Produces a standalone ELF executable — no linker, no libc.
;;; FFI words (#lib, #fun, #call) are stubbed out.
;;;
;;; Build: fasm fflins.asm ffs

;;; -----------------------------------------------------------------------
;;; OSFORMAT specifies the Operating-System specific executable file format

macro OSFORMAT {

;ffdl=1                 ; commented out = static build, no dynamic linking

if defined ffdl

format elf
section '.flat' writeable executable
public _start

else

format elf executable 3
entry _start

end if

}

;;; BSSSECTION: flat executables need no directive — rb at end of
;;; segment gets MemSiz > FileSiz automatically.

macro BSSSECTION { }

;;; -----------------------------------------------------
;;; OSINCLUDE defines OS-specific ASM source to "include"

macro OSINCLUDE { include "fflinio.asm" }

;;; -----------------------------------------------------
;;; all macros ready: compile all:

include "ff.asm"

;;; That's all folks!!
