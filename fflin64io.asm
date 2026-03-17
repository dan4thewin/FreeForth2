;;; fflin64io.asm  FreeForth2 Linux I/O (x86-64)
;;;
;;; Mirrors i386 fflinio.asm: OS interface words separated from the
;;; language kernel (ff64.asm).  Contains syscall dispatcher, signal
;;; handling, and dynamic library interface.

;;; --------------------------------------------------
;;; FreeForth interface to Linux syscall

;; syscall ( args... #args syscall# -- ior )
;; Generic Linux syscall dispatcher. Same Forth interface as i386 fflinio.asm.
;; x86-64 syscall convention: rax=syscall#, args in rdi,rsi,rdx,r10,r8,r9.
;; NOTE: syscall numbers differ between i386 and x86-64!
;; (e.g., write=4 on i386, write=1 on x86-64)
_syscall:
        push rbp                ; save compilation pointer
        mov rax, rbx            ; rax = syscall# (TOS)
        mov rcx, rdx            ; rcx = #args (NOS)
        cmp rcx, 6
        jbe .ok
        ;; Too many args — error
        pop rbp
        mov rbx, -1
        ret
.ok:    ;; r15 points to data stack: [0]=arg1, [8]=arg2, ...
        ;; Load args from data stack based on count
        test rcx, rcx
        jz .call
        mov rdi, [r15]          ; arg1
        cmp rcx, 1
        je .call
        mov rsi, [r15+8]        ; arg2
        cmp rcx, 2
        je .call
        push rdx
        mov rdx, [r15+16]       ; arg3
        cmp rcx, 3
        je .call_rdx
        mov r10, [r15+24]       ; arg4
        cmp rcx, 4
        je .call_rdx
        mov r8, [r15+32]        ; arg5
        cmp rcx, 5
        je .call_rdx
        mov r9, [r15+40]        ; arg6
.call_rdx:
        ;; rdx was saved, adjust stack pointer by #args * 8
        lea r15, [r15 + rcx*8]  ; pop all args from data stack
        syscall
        mov rbx, rax            ; TOS = result
        pop rdx                 ; restore original NOS (was #args)
        mov rdx, [r15]          ; NOS = next item on data stack
        add r15, 8              ; pop the old #args slot
        pop rbp
        ret
.call:  ;; 0-2 args: rdx not used as syscall arg, still holds #args
        lea r15, [r15 + rcx*8]  ; pop all args from data stack
        push rcx                ; save #args
        push rdx                ; save NOS (#args)
        syscall
        pop rdx                 ; discard saved NOS
        pop rcx                 ; discard #args
        mov rbx, rax            ; TOS = result
        mov rdx, [r15]          ; NOS = next item on data stack
        add r15, 8              ; pop the old #args slot
        pop rbp
        ret

;;; ---------------------------------------------------
;;; sigrestorer — required for raw rt_sigaction
;;; The kernel needs SA_RESTORER + a restorer function that calls
;;; sys_rt_sigreturn.  Exposed as a constant so Forth SEGV setup can use it.

_segv_restorer:
        mov rax, 15             ; sys_rt_sigreturn
        syscall

;;; ---------------------------------------------------
;;; FreeForth interface to Linux dynamic-link libraries
;;; x86-64 SysV ABI: args in rdi,rsi,rdx,rcx,r8,r9; result in rax.
;;; Callee-saved (preserved across C calls): rbx,rbp,r12,r13,r14,r15.
;;; Stack must be 16-byte aligned before call instruction.

if defined ffdl

extrn dlopen
extrn dlsym
extrn dlerror

saveSP  dq 0                    ; saved return stack across C calls
dl_errbuf rb 256                ; buffer for dlerror() counted strings

;; #lib ( addr len -- libh )
;; dlopen(filename, RTLD_LAZY|RTLD_GLOBAL=0x101)
_dllib:
        mov byte [rdx + rbx], 0 ; NUL-terminate filename at addr+len
        mov rdi, rdx            ; rdi = filename address (NOS)
        mov rsi, 0x101          ; RTLD_LAZY | RTLD_GLOBAL
        mov [saveSP], rsp
        and rsp, -16
        xor eax, eax
        call dlopen
        mov rsp, [saveSP]
        test rax, rax
        jz dl_err
        mov rbx, rax            ; TOS = library handle
        mov rdx, [r15]          ; NOS = item below addr
        add r15, 8              ; pop addr from data stack
        ret

;; #fun ( addr len libh -- funh )
;; dlsym(handle, symbol_name)
_dlfun:
        mov rdi, rbx            ; rdi = library handle (TOS)
        mov rsi, [r15]          ; rsi = symbol address (3rd item)
        mov byte [rsi + rdx], 0 ; NUL-terminate at addr+len
        mov [saveSP], rsp
        and rsp, -16
        xor eax, eax
        call dlsym
        mov rsp, [saveSP]
        test rax, rax
        jz dl_err
        mov rbx, rax            ; TOS = function handle
        mov rdx, [r15+8]       ; NOS = item below addr+len
        add r15, 16             ; pop addr and len
        ret

dl_err:
        ;; Error: call dlerror(), copy string to dl_errbuf (NOT here), throw.
        ;; Copying to here (rbp) would overwrite compiled code that the catch
        ;; frame's return address points to — causing SEGV on throw return.
        mov [saveSP], rsp
        and rsp, -16
        call dlerror
        mov rsp, [saveSP]
        ;; rax = NUL-terminated error string. Copy to dl_errbuf+1, count at dl_errbuf.
        mov rsi, rax
        lea rdi, [dl_errbuf + 1]
        xor ecx, ecx
dl_ecopy:
        lodsb
        test al, al
        jz .dl_ecopy_done
        stosb
        inc ecx
        cmp ecx, 254           ; max 254 chars
        jge .dl_ecopy_done
        jmp dl_ecopy
.dl_ecopy_done:
        mov byte [dl_errbuf], cl ; store count at first byte
        lea rbx, [dl_errbuf]    ; TOS = counted error string
        jmp _throw

;; #call ( argN ... arg1 N funh -- result )
;; Call C function via x86-64 SysV ABI. Supports up to 6 args.
;; For variadic C functions, al=0 (no SSE args).
_dlcall:
        mov r12, rbx            ; r12 = function pointer (callee-saved)
        mov r13, rdx            ; r13 = N arg count (callee-saved)
        ;; Args sit at [r15], [r15+8], ..., [r15+8*(N-1)]
        test r13, r13
        jz dc_call
        mov rdi, [r15]          ; arg1
        cmp r13, 1
        je dc_call
        mov rsi, [r15+8]       ; arg2
        cmp r13, 2
        je dc_call
        mov rdx, [r15+16]      ; arg3
        cmp r13, 3
        je dc_call
        mov rcx, [r15+24]      ; arg4
        cmp r13, 4
        je dc_call
        mov r8, [r15+32]       ; arg5
        cmp r13, 5
        je dc_call
        mov r9, [r15+40]       ; arg6
dc_call:
        mov [saveSP], rsp
        and rsp, -16
        xor eax, eax            ; no SSE args (for variadic functions)
        call r12
        mov rsp, [saveSP]
        ;; Pop N args, load new TOS/NOS
        lea r15, [r15 + r13*8]  ; skip past N args in data stack
        mov rdx, [r15]          ; new NOS (first item below args)
        add r15, 8              ; pop it from memory stack
        mov rbx, rax            ; TOS = C function result
        ret

else

;; Static build — FFI stubs return 0 (not available)
;; #lib returns 0 instead of throwing, so dlsetup stores 0 in libc
;; and all libc-dependent guards see 0 and skip gracefully.

_dllib:
        ;; ( addr len -- 0 ) return null handle
        mov rdx, [r15]
        add r15, 8
        xor ebx, ebx
        ret

_dlfun:
        ;; ( addr len libh -- 0 ) return null function
        mov rdx, [r15+8]
        add r15, 16
        xor ebx, ebx
        ret

_dlcall:
        ;; ( argN...arg1 N funh -- 0 ) pop args, return 0
        lea r15, [r15 + rdx*8]
        mov rdx, [r15]
        add r15, 8
        xor ebx, ebx
        ret

end if

;;; That's all folks!!
