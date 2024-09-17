;;; fflinio.asm  FreeForth Linux I/O
;;; $Id: fflinio.asm,v 1.6 2009-09-03 20:47:46 lavarec Exp $

;;; --------------------------------------------------
;;; FreeForth interface to Linux syscall and file-I/O

if defined ffdl
extrn dlopen                    ; void* dlopen(const char* filename, int flag);
CODE "dlopen",_dlopen
        jmp dlopen
extrn dlsym                     ; void* dlsym(void* handle, char* symbol);
CODE "dlsym",_dlsym
        jmp dlsym
extrn dlerror                   ; const char* dlerror(void);
CODE "dlerror",_dlerror
        jmp dlerror
end if

CODE "exit",_exit               ; n -- ; 1 1 syscall ;
        mov ecx,1
        jmp _sys1

CODE "close",_close             ; fd -- ? ; 1 6 syscall ;
        mov ecx,6
_sys1:  DUP2
        mov edx,1
        mov ebx,ecx
        jmp _syscall

;;; (see man 2 open, values taken from /usr/include/bits/fcntl.h):
;;; . O_RDONLY=0, O_WRONLY=1, O_RDWR=2 (these are the main flags)
;;; . O_CREAT=$40, O_EXCL=$80, O_NOCTTY=$100, O_TRUNC=$200, O_APPEND=$400,
;;;   O_NONBLOCK=O_NDELAY=$800, O_SYNC=O_FSYNC=$1000, O_ASYNC=$2000
;;; "mode" specifies the "rwxrwxrwx" user/group/other rights on the file,
;;; they are conveniently specified in octal (see man 2 open), usually "&644"

;;; openr opens existing file for read-only
CODE "openr",_openr             ; @ # -- fd ; zt &644 r/o rot 3 5 syscall ;
        xor ecx,ecx             ; $00(O_RDONLY)
        jmp _open               ; Note: &644 not needed, but code factorized

;;; openw0 opens (existing if: truncates else: creates) file for read-write
CODE "openw0",_openw0           ; @ # -- fd ; zt &644 rw/cre rot 3 5 syscall ;
        mov ecx,$342            ; $200(TRUNC)+$100(NOCTTY)+$40(CREAT)+$02(RDWR)
        jmp _open

;;; openw opens (and creates if non-existing) file for read-write
CODE "openw",_openw             ; @ # -- fd ; zt &644 rw/cre rot 3 5 syscall ;
        mov ecx,$142            ; $100(O_NOCTTY)+$40(O_CREAT)+$02(O_RDWR)
_open:  mov byte[edx+ebx],0     ; append zero-terminator (another whitespace)
        xchg eax,esp
        pushd 420               ; mode=420=&644
        push ecx                ; flags
        push edx                ; -- mode flags zt
        xchg eax,esp
        mov edx,3
        mov ebx,5
        jmp _syscall

CSTE "stdin",0
VECT "accept",_accept           ; @ # -- n ; 0 read ;
        DUP1 0                  ; stdin=0
;;;     jmp _read
CODE "read",_read               ; @ # fd -- n ; >rswapr> 3 3 syscall ;
        mov ecx,3
        jmp _sys3

CSTE "stdout",1
VECT "type",_type               ; @ # -- ; 1 write drop ;
        DUP1 1                  ; stdout=1
        call _write
        DROP1
        ret

CODE "write",_write             ; @ # fd -- n ; >rswapr> 3 4 syscall ;
        mov ecx,4
_sys3:  xchg [eax],edx          ; -- # @ fd
        DUP2
        mov edx,3
        mov ebx,ecx
;;;     jmp _syscall

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
;;; FreeForth interface to Linux dynamic-link libraries

saveSP  dd 0
CODE "#call",_dlcall            ; #args funh -- funresult
        lea edx,[eax+4*edx]     ; dataSP after funcall
        push edx                ; save it
        xchg eax,esp
        mov [saveSP],eax        ; save callSP
        call ebx                ; eax = funresult
        mov esp,[saveSP]        ; restore callSP
        jmp nipeax

if defined ffdl ;; TODO: try to inline dl* functions to compile with fasm only.

;extrn dlopen                    ; void* dlopen(const char* filename, int flag);
;extrn dlsym                     ; void* dlsym(void* handle, char* symbol);
;extrn dlerror                   ; const char* dlerror(void);
;extrn dlclose                  ; int dlclose (void* handle);
;libs   dd $+4, 16 dup 0        ; libraries handles for dlclose on exit
;libsEnd                        ; libs buffer end address
;CODE "-libs",_libsfree         ; --- ISN'T IT DONE BY THE LOADER ON EXIT? ---
;       mov esi,libs+4
;@@:    lodsd                   ; eax = library handle
;       push esi
;       push eax
;;      extrn dlclose           ; int dlclose (void* handle);
;       call dlclose            ; don't care returned error
;       pop esi
;       cmp esi,libsEnd
;       jnz @b
;       ret

;;; : lib:` :` #lib lit #fun ' call, ;;` ;  \ "libc.so.6" lib: libc
;;; : fun:` :` lit lit #call ' call, ;;` ;  \ 1 "puts" libc fun: puts

        ;; : uselib 1 86 syscall ; \ int uselib(const char* library);
;;; Note: when ffdl undefined, the following line must be commented:
CODE "#lib",_dllib              ; @ # -- libh
        xchg eax,esp
        push eax                ; save callSP
        mov byte[edx+ebx],0     ; append zero-terminator
;       extrn dlopen            ; void* dlopen(const char* filename, int flag);
        pushd $101              ; RTLD_LAZY | RTLD_GLOBAL
        push edx                ; filename, null-terminated
        call _dlopen            ; eax = library handle (null on error)
        jmp dlret

;;; Note: when ffdl undefined, the following line must be commented:
CODE "#fun",_dlfun              ; @ # libh -- funh
        xchg eax,esp
        pop ecx                 ; ecx = @
        push eax                ; save callSP
        mov byte[ecx+edx],0     ; append zero-terminator
;       extrn dlsym             ; void* dlsym(void* handle, char* symbol);
        push ecx                ; library function name, null-terminated
        push ebx                ; library handle
        call _dlsym             ; eax = function handle (null on error)
dlret:  or eax,eax
        jz dlerr
        add esp,8               ; cleanup 2 args from stack
        mov ebx,eax             ; -- handle
        pop eax                 ; restore callSP
        pop edx                 ; restore NOS
        xchg eax,esp
        ret

;       extrn dlerror           ; const char* dlerror(void);
dlerr:  call _dlerror           ; eax = null-terminated error string
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

end if

        ;; \ long* getcwd(char* buf, unsigned long size);
        ;; : getcwd 2 183 syscall ;
        ;; \ void* mmap(void*start, size_t length, int prot, int flags, int fd, off_t offset);
        ;; libc 6 fun: mmap  \ int munmap(void* start, size_t length);
        ;; : mmap 6 90 syscall ;  : munmap 2 91 syscall ;  \ DOESN'T WORK!!!??
        ;; prot: PROT_READ=1 PROT_WRITE=2 PROT_EXEC=4
        ;; flags: MAP_SHARED=1 MAP_PRIVATE=2 MAP_FIXED=10 MAP_ANONYMOUS=20

;;; That's all folks!!
