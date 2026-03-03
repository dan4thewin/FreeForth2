;;; fftk64.asm — FreeForth2 x86-64 turnkey binary
;;;
;;; Embeds a pre-compiled code image (cmpl64) at the same section
;;; offset as ff64.asm's .flat section, preserving all addresses.
;;; Reads bootxt from the image and jumps to _boot.
;;;
;;; Build:
;;;   ./ff64 -f lib/64/mkimage.ff       (produces cmpl64, cmpl64.cfg)
;;;   fasm fftk64.asm fftk64.o
;;;   ld -m elf_x86_64 -lc -ldl --dynamic-linker=/lib64/ld-linux-x86-64.so.2 -o fftk64 fftk64.o

format elf64
section '.flat' writeable executable
public _start

cmpl64: file "cmpl64"

_start:
        ;; Load DS0 (dstack_top) from config file
        mov r15, [ds0_val]

        ;; Set compilation pointer past all fftk64 code/data
        lea rbp, [fftk64_codebuf]
        mov [cmpl64+8], rbp         ; update anon to match

        ;; Clear TOS/NOS registers
        xor ebx, ebx
        xor edx, edx

        ;; Reset compiler state
        mov qword [cmpl64+16], 0    ; callmark = 0
        mov qword [cmpl64+48], 0    ; xfp = 0
        mov byte [cmpl64+88], 0     ; SC = 0
        mov byte [cmpl64+89], 0     ; cond_jmp = 0

        ;; Save argc/argv for Forth access
        mov rax, [rsp]
        mov [cmpl64+56], rax        ; ff_argc
        lea rax, [rsp+8]
        mov [cmpl64+64], rax        ; ff_argv

        ;; Jump to _boot (stored in bootxt at offset 72)
        mov rcx, [cmpl64+72]
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
