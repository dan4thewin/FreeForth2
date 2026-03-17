;;; fflin64.asm  FreeForth2 x86-64 kernel, Linux specific port
;;;
;;; Mirrors the i386 fflin.asm pattern: defines OS-specific macros
;;; and includes ff64.asm.  Two build modes:
;;;
;;; With ffdl=1 (dynamic linking, default):
;;;   fasm fflin64.asm ff64.o
;;;   ld -m elf_x86_64 -lc -ldl --dynamic-linker=... ff64.o -o ff64
;;;
;;; Without ffdl (static, linker-free):
;;;   fasm fflin64s.asm ff64s
;;;   (no linker step — FASM emits a complete executable)

;;; -----------------------------------------------------------------------
;;; OSFORMAT specifies the Operating-System specific executable file format

macro OSFORMAT {

ffdl=1                  ; withDynamicLinkLibrary support; commented=without

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
