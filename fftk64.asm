;;; fftk64.asm — FreeForth2 x86-64 turnkey binary
;;;
;;; Embeds a pre-compiled code image (cmpl64) at the same section
;;; offset as ff64.asm's .flat section, preserving all addresses.
;;; Reads bootxt from the image and jumps to _boot.
;;;
;;; Build:
;;;   ./ff64 -f lib/x86-64/mkimage.ff       (produces cmpl64, cmpl64.cfg)
;;;   fasm fftk64.asm fftk64.o
;;;   ld -m elf_x86_64 -lc -ldl --dynamic-linker=/lib64/ld-linux-x86-64.so.2 -o fftk64 fftk64.o

format elf64
section '.flat' writeable executable
public _start

cmpl64: file "cmpl64"

;;  .flat header layout (must match ff64.asm):
;;    +0  H          +8  anon       +16 callmark   +24 tin
;;   +32  tp        +40  xfp        +48 CS0        +56 bootxt
;;   +64  SC (byte) +65  cond_jmp

_start:
        ;; Load DS0 (dstack_top) from config file
        mov r15, [ds0_val]

        ;; Set compilation pointer past all fftk64 code/data
        lea rbp, [fftk64_codebuf]
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

;; Force linker to include dl* symbols (needed by #lib/#fun/#call)
extrn dlopen
extrn dlsym
extrn dlerror

_dummy:
        call dlopen
        call dlsym
        call dlerror

        align 8
ds0_val:  file "cmpl64.cfg"

;; New compilation goes here — past all fftk64 code/data
        align 8
fftk64_codebuf rb 65536
