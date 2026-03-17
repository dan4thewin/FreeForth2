;;; fflinio.asm  FreeForth Linux I/O
;;; $Id: fflinio.asm,v 1.6 2009-09-03 20:47:46 lavarec Exp $

;;; --------------------------------------------------
;;; FreeForth interface to Linux syscall
;;; exit/accept now in Forth (syscalls.ff / ff2.boot)

CODE "syscall",_syscall         ; args arg# syscall# -- ior
        ;; syscalls can take a variable number of arguments, from 0 to 6.
        ;; The args go in ebx, ecx, edx, esi, edi, ebp, in that order.
        ;; (this is from the Linux Assembly HOWTO)
        ;; /usr/include/asm/unistd.h lists syscall#, see man for arglist
        cmp edx,6               ; check args count
        jbe @f
        call _error
        CDB "syscall#args>6"
@@:     lea ecx,[eax+4*edx]     ; dataSP after syscall return
        push ecx                ; save it
        push ebp                ; save compilation pointer
        push ebx                ; save syscall#
        neg edx
        lea edx,[.0+3*edx]      ; i.e. [.0+edx+2*edx] Thanks Helmar
        jmp edx
.6:     mov ebp,[eax+20]        ; 3-bytes instruction
.5:     mov edi,[eax+16]        ; 3-bytes instruction
.4:     mov esi,[eax+12]        ; 3-bytes instruction
.3:     mov edx,[eax+8]         ; 3-bytes instruction
.2:     mov ecx,[eax+4]         ; 3-bytes instruction
.1:     mov ebx,[eax+0]         ; 2-bytes instruction
        nop                     ; 3rd byte padding
.0:     pop eax                 ; restore syscall#
        int $80                 ; call operating system
        pop ebp                 ; restore compilation pointer
nipeax: mov ebx,eax             ; TOS = syscall result
        pop eax                 ; restore dataSP
        xchg eax,esp            ; 94
        pop edx                 ; 5A restore NOS
        xchg eax,esp            ; 94
        ret

;;; ---------------------------------------------------
;;; sigrestorer — required for raw rt_sigaction (syscall 174)
;;; The kernel needs SA_RESTORER + a restorer function that calls
;;; sys_sigreturn.  Exposed as a constant so Forth SEGV setup can use it.

_segv_restorer:
        mov eax, 173            ; sys_sigreturn
        int $80

WORD "sigrestorer", _segv_restorer, 1

;;; ---------------------------------------------------
;;; FreeForth interface to Linux dynamic-link libraries

saveSP  dd 0

if defined ffdl

extrn dlopen                    ; void* dlopen(const char* filename, int flag);
extrn dlsym                     ; void* dlsym(void* handle, char* symbol);
extrn dlerror                   ; const char* dlerror(void);

CODE "#call",_dlcall            ; #args funh -- funresult
        lea edx,[eax+4*edx]     ; dataSP after funcall
        push edx                ; save it
        xchg eax,esp
        mov [saveSP],eax        ; save callSP
        call ebx                ; eax = funresult
        mov esp,[saveSP]        ; restore callSP
        jmp nipeax

CODE "#lib",_dllib              ; @ # -- libh
        xchg eax,esp
        push eax                ; save callSP
        mov byte[edx+ebx],0     ; append zero-terminator
        pushd $101              ; RTLD_LAZY | RTLD_GLOBAL
        push edx                ; filename, null-terminated
        call dlopen             ; eax = library handle (null on error)
        jmp dlret

CODE "#fun",_dlfun              ; @ # libh -- funh
        xchg eax,esp
        pop ecx                 ; ecx = @
        push eax                ; save callSP
        mov byte[ecx+edx],0     ; append zero-terminator
        push ecx                ; library function name, null-terminated
        push ebx                ; library handle
        call dlsym              ; eax = function handle (null on error)
dlret:  or eax,eax
        jz dlerr
        add esp,8               ; cleanup 2 args from stack
        mov ebx,eax             ; -- handle
        pop eax                 ; restore callSP
        pop edx                 ; restore NOS
        xchg eax,esp
        ret

dlerr:  call dlerror            ; eax = null-terminated error string
        mov esi,eax             ; copy it to counted string at here
        mov edi,ebp
@@:     stosb                   ; first stosb is for string count
        lodsb                   ; last lodsb occurs for null-terminator:
        or al,al
        jnz @b
        sub edi,ebp
        lea eax,[edi-1]         ; don't count string count!
        mov [ebp],al            ; setup string count
        mov ebx,ebp             ; counted error string address
        jmp _throw              ; raise exception

else

;; Static build — FFI stubs return 0 (not available)
;; #lib returns 0 so dlsetup stores 0 in libc and all libc-dependent
;; guards see 0 and skip gracefully.

CODE "#lib",_dllib              ; @ # -- 0
        xchg eax,esp
        pop edx
        xchg eax,esp
        xor ebx,ebx
        ret

CODE "#fun",_dlfun              ; @ # libh -- 0
        xchg eax,esp
        pop ecx                 ; discard @
        pop edx                 ; restore NOS
        xchg eax,esp
        xor ebx,ebx
        ret

CODE "#call",_dlcall            ; argN..arg1 N funh -- 0
        lea edx,[eax+4*edx]     ; skip past N args
        xchg eax,esp
        pop edx                 ; restore NOS
        xchg eax,esp
        xor ebx,ebx
        ret

end if

        ;; \ long* getcwd(char* buf, unsigned long size);
        ;; : getcwd 2 183 syscall ;
        ;; \ void* mmap(void*start, size_t length, int prot, int flags, int fd, off_t offset);
        ;; libc 6 fun: mmap  \ int munmap(void* start, size_t length);
        ;; : mmap 6 90 syscall ;  : munmap 2 91 syscall ;  \ DOESN'T WORK!!!??
        ;; prot: PROT_READ=1 PROT_WRITE=2 PROT_EXEC=4
        ;; flags: MAP_SHARED=1 MAP_PRIVATE=2 MAP_FIXED=10 MAP_ANONYMOUS=20

;;; That's all folks!!
