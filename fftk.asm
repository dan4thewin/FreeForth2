format elf
section '.flat' writeable executable
public _start

cmpl:   file "cmpl"

;; perform header, ebp, and eax init same as ff.asm
;; overwrite values at beginning of image with
;; values specific to this build or run
_start:
        mov esi,heads           ; relocate headers
        mov edi,H0
        mov ecx,headers_size/4
        rep movsd
        mov ebp,ebp0            ; compilation pointer
        lea eax,[esp-4096]      ; allocate CALLstack
        mov [cmpl],dword H0     ; set H to H0
        mov [cmpl+4],dword ebp0 ; set anon to ebp0
        mov [cmpl+8],esp        ; save for argv
        mov ecx,-4
        add ecx,eax
        mov [cmpl+12],ecx        ; depth fix
        mov ecx,[cmpl+16]       ; _boot
        mov [cmpl+20],dword 0   ; zero libc value, must run dlopen
        xor ebx,ebx
        xor edx,edx
        jmp ecx

;; convince linker to provide dl*
extrn dlopen
extrn dlsym
extrn dlerror

_dummy:
        call dlopen
        call dlsym
        call dlerror

;; no inline boot code for this version
        align 4
heads:  file "dict"
        align 4
    headers_size = $-heads

section '.bss'
    ebp0 = heads

bss     rb 1024*488
tib     rb 1024*256
eob     rb 1024
bssend:

    H0 = tib-headers_size
