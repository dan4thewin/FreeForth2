;;; fflin64s.asm  FreeForth2 x86-64 kernel, static (linker-free) build
;;;
;;; Same as fflin64.asm but with ffdl commented out.
;;; Produces a standalone ELF64 executable — no linker, no libc.
;;; FFI words (#lib, #fun, #call) are stubbed out.
;;;
;;; Build: fasm fflin64s.asm ff64s

;;; -----------------------------------------------------------------------
;;; OSFORMAT specifies the Operating-System specific executable file format

macro OSFORMAT {

;ffdl=1                 ; commented out = static build, no dynamic linking

if defined ffdl

format elf64
section '.flat' writeable executable
public _start

else

format elf64 executable 3
entry _start

segment readable writeable executable

end if

}

;;; -----------------------------------------------------------------------
;;; OSINCLUDE defines OS-specific ASM source to "include"

macro OSINCLUDE { include "fflin64io.asm" }

;;; -----------------------------------------------------
;;; all macros ready: compile all:

include "ff64.asm"

;;; That's all folks!!
