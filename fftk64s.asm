;;; fftk64s.asm — FreeForth2 x86-64 static turnkey binary
;;;
;;; Like fftk64.asm but produces a standalone ELF64 executable —
;;; no linker, no libc, no dynamic linking.  FFI words (#lib/#fun/#call)
;;; will not work in this binary.
;;;
;;; Build:
;;;   ./ff64s -f myapp.ff -f lib/x86-64/mkimage.ff  (produces cmpl64, cmpl64.cfg)
;;;   fasm fftk64s.asm fftk64s                       (or: make fftk64s)
;;;
;;; IMPORTANT: mkimage must run under ff64s (not ff64) so that
;;; absolute addresses in the image match the static ELF layout.

format elf64 executable 3
entry _start

segment readable writeable executable

cmpl64: file "cmpl64"

;;  .flat header layout (must match ff64.asm):
;;    +0  H          +8  anon       +16 callmark   +24 tin
;;   +32  tp        +40  xfp        +48 CS0        +56 bootxt
;;   +64  SC (byte) +65  cond_jmp

_start:
        ;; Load DS0 (dstack_top) from config file
        mov r15, [ds0_val]

        ;; Set compilation pointer past all fftk64s code/data
        lea rbp, [fftk64s_codebuf]
        mov [cmpl64+8], rbp         ; anon = rbp

        ;; Clear TOS/NOS registers
        xor ebx, ebx
        xor edx, edx

        ;; Reset compiler state
        mov qword [cmpl64+16], 0    ; callmark = 0
        mov qword [cmpl64+40], 0    ; xfp = 0
        mov byte [cmpl64+64], 0     ; SC = 0
        mov byte [cmpl64+65], 0     ; cond_jmp = 0

        ;; Save initial stack pointer (argc/argv derived via CS0 in Forth)
        mov [cmpl64+48], rsp        ; CS0 = rsp

        ;; Jump to _boot (stored in bootxt at offset 56)
        mov rcx, [cmpl64+56]
        jmp rcx

        align 8
ds0_val:  file "cmpl64.cfg"

        align 8
fftk64s_codebuf rb 65536
