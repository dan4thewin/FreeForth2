format elf
section '.flat' writeable executable
public _start

cmpl:   file "cmpl-"

;; perform eax init same as ff.asm
;; overwrite values at beginning of image with
;; values specific to this build or run
;; 0x804b591
_start:
        mov [cmpl+8],esp        ; save for argv
        lea eax,[esp-4096]      ; allocate CALLstack
        mov ecx,-4
        add ecx,eax
        mov [cmpl+$c],ecx       ; depth fix
        mov ecx,[cmpl+$10]      ; start
        mov [cmpl+$18],dword 0  ; zero libc value, must run dlopen
        xor ebx,ebx
        xor edx,edx
        jmp ecx

;; convince linker to provide dl*
extrn dlerror
extrn dlopen
extrn dlsym

_dummy:
        call dlerror
        call dlopen
        call dlsym

; section '.bss'
; bss     rb 1024*512
; tib     rb 1024*256
; eob     rb 1024
