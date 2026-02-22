;;; 009-nameddef64: Named definitions (colon compiler) for x86-64
;;; Proves: `: name ... ;` creates callable named words at runtime
;;;
;;; This extends the interactive compiler with:
;;;   - `:` to start a named definition (creates a header)
;;;   - `;` distinguishes anonymous vs named definitions
;;;   - Runtime header creation (headers grow downward from built-in words)
;;;
;;; Test: `: square dup * ; 5 square . cr ;` → 25
;;;
;;; Register allocation:
;;;   rbx = TOS, rdx = NOS, r15 = data stack pointer
;;;   rsp = call stack, rbp = compilation pointer ("here")

format elf64
section '.flat' writeable executable
public _start

h.ct = 8
h.sz = 9
h.nm = 10

;; =====================================================================
;; Compiler state
;; =====================================================================

H       dq 0                    ; header pointer (grows down)
anon    dq 0                    ; start of anonymous def (0 = named def)
tin     dq 0                    ; input parse pointer
tp      dq 0                    ; input limit pointer

;; =====================================================================
;; Runtime primitives (called by compiled code)
;; =====================================================================

_add:   add rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

_sub:   xchg rbx, rdx
        sub rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

_mul:   imul rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

_dup:   sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        ret

_drop:  mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

_swap:  xchg rbx, rdx
        ret

_over:  sub r15, 8
        mov [r15], rdx
        xchg rbx, rdx
        ret

_dot:   push r15                ; . (print TOS + space, drop)
        push rdx
        mov rax, rbx
        test rax, rax
        jns .pos
        push rax
        mov rax, 1
        mov rdi, 1
        lea rsi, [minus_char]
        mov rdx, 1
        syscall
        pop rax
        neg rax
.pos:   lea rdi, [numbuf+20]
        mov rcx, 10
.loop:  xor edx, edx
        div rcx
        add dl, '0'
        dec rdi
        mov [rdi], dl
        test rax, rax
        jnz .loop
        lea rax, [numbuf+20]
        mov byte [rax], ' '
        lea rdx, [numbuf+21]
        sub rdx, rdi
        mov rsi, rdi
        mov rax, 1
        mov rdi, 1
        syscall
        pop rdx
        pop r15
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

_cr:    push rax
        push rdi
        push rsi
        push rdx
        mov rax, 1
        mov rdi, 1
        lea rsi, [nl_char]
        mov rdx, 1
        syscall
        pop rdx
        pop rsi
        pop rdi
        pop rax
        ret

;; =====================================================================
;; Compiler core
;; =====================================================================

_wsparse:
        mov rdi, [tin]
        mov rsi, [tp]
.skip:  cmp rdi, rsi
        jae .eof
        cmp byte [rdi], ' '
        ja .word
        inc rdi
        jmp .skip
.eof:   xor ecx, ecx
        mov [tin], rdi
        ret
.word:  mov rax, rdi
.scan:  inc rdi
        cmp rdi, rsi
        jae .done
        cmp byte [rdi], ' '
        ja .scan
.done:  mov [tin], rdi
        mov rcx, rdi
        sub rcx, rax
        ret

_find:  push r8
        push r9
        mov r8, rax
        mov r9, rcx
        mov rsi, [H]
.b:     lea rsi, [rsi + h.nm]
        movzx ecx, byte [rsi-1]
        jecxz .e
        cmp rcx, r9
        jnz .skip
        mov rdi, r8
        push rsi
        push rcx
        repz cmpsb
        pop rcx
        pop rsi
        jz .found
.skip:  lea rsi, [rsi + rcx + 1]
        jmp .b
.found: lea rsi, [rsi - h.nm]
        mov rax, [rsi]          ; rax = xt
        movzx ecx, byte [rsi + h.ct]  ; ecx = ct
        ;; ZF: ct=0 means runtime word (ZF set), ct!=0 means compile-time
        pop r9
        pop r8
        ret
.e:     mov rcx, r9
        mov rax, r8
        test r9, r9             ; ZF clear (word not found)
        pop r9
        pop r8
        ret

_number:
        push r8
        mov r8, rax
        xor edx, edx
        xor r9d, r9d
        mov rsi, rax
        lea rdi, [rax + rcx]
        cmp byte [rsi], '$'
        je .hex_start
        cmp byte [rsi], '-'
        jne .dec
        mov r9d, 1
        inc rsi
        cmp rsi, rdi
        jae .fail
.dec:   cmp rsi, rdi
        jae .ok
        movzx eax, byte [rsi]
        sub al, '0'
        cmp al, 9
        ja .fail
        imul rdx, 10
        movzx eax, al
        add rdx, rax
        inc rsi
        jmp .dec
.hex_start:
        inc rsi
        cmp rsi, rdi
        jae .fail
.hloop: cmp rsi, rdi
        jae .ok
        movzx eax, byte [rsi]
        sub al, '0'
        cmp al, 9
        jbe .hadd
        sub al, 'A'-'0'-10
        cmp al, 15
        jbe .hadd
        sub al, 32
        cmp al, 15
        ja .fail
.hadd:  shl rdx, 4
        movzx eax, al
        add rdx, rax
        inc rsi
        jmp .hloop
.ok:    test r9d, r9d
        jz .noneg
        neg rdx
.noneg: mov rax, rdx
        pop r8
        xor edx, edx
        ret
.fail:  mov rax, r8
        pop r8
        or eax, 1
        ret

_call_compile:
        mov byte [rbp], $E8
        lea rcx, [rbp+5]
        sub eax, ecx
        mov dword [rbp+1], eax
        add rbp, 5
        ret

_lit_compile:
        ;; sub r15, 8
        mov dword [rbp], $08EF8349
        add rbp, 4
        ;; mov [r15], rdx
        mov byte [rbp], $49
        mov word [rbp+1], $1789
        add rbp, 3
        ;; mov rdx, rbx
        mov byte [rbp], $48
        mov word [rbp+1], $DA89
        add rbp, 3
        ;; Check if fits in 32-bit
        mov rcx, rax
        mov eax, eax
        cmp rax, rcx
        jne .big
        ;; mov ebx, imm32
        mov byte [rbp], $BB
        mov dword [rbp+1], eax
        add rbp, 5
        ret
.big:   ;; mov rbx, imm64
        mov byte [rbp], $48
        mov byte [rbp+1], $BB
        mov qword [rbp+2], rcx
        add rbp, 10
        ret

;; =====================================================================
;; Header creation
;; =====================================================================

;; _header: create a new dictionary header
;;   rax = name addr, rcx = name len, r8 = xt, r9b = ct
;; Headers grow downward from [H].
_header:
        push rdi
        push rsi
        push rcx
        mov rsi, rax            ; rsi = name source
        mov rdi, [H]            ; rdi = current H
        dec rdi                 ; allocate NUL terminator
        sub rdi, rcx            ; allocate name bytes
        ;; rdi now points to start of name field
        ;; Store name length and ct BEFORE the name
        mov byte [rdi - 1], cl  ; h.sz = name length
        mov byte [rdi - 2], r9b ; h.ct = compile-time byte
        lea rax, [rdi - h.nm]   ; rax = new header start (xt field)
        mov [rax], r8           ; store xt
        mov [H], rax            ; update H
        ;; Copy name
        push rcx
        rep movsb               ; copy name bytes
        pop rcx
        mov byte [rdi], 0       ; NUL terminator (rdi advanced past name)
        pop rcx
        pop rsi
        pop rdi
        ret

;; =====================================================================
;; Colon and semicolon
;; =====================================================================

;; _colon: start a named definition
;;   Parses the next word as the name, creates a header with xt=rbp
_colon:
        ;; If anonymous code pending, execute it first
        mov rax, [anon]
        test rax, rax
        jz .no_anon
        call _semi_exec         ; execute pending anonymous code
.no_anon:
        ;; Parse the definition name
        call _wsparse
        test ecx, ecx
        jz .missing_name
        ;; Create header: name=rax/rcx, xt=rbp, ct=0
        mov r8, rbp             ; xt = current compilation pointer
        xor r9d, r9d            ; ct = 0 (runtime word)
        call _header
        ;; Mark as named definition
        mov qword [anon], 0
        ret
.missing_name:
        ;; Error: : without a name
        push rax
        mov rax, 1
        mov rdi, 1
        lea rsi, [err_noname]
        mov rdx, err_noname_len
        syscall
        pop rax
        ret

;; _semi: close current definition
;;   Named def: compile ret, advance past it, start new anonymous zone
;;   Anonymous def: compile ret, execute, recycle space
_semi:
        mov byte [rbp], $C3     ; compile ret
        inc rbp
        mov rax, [anon]
        test rax, rax
        jnz .anonymous
        ;; Named definition: body stays, start new anonymous zone
        mov [anon], rbp
        ret
.anonymous:
        ;; Fall through to execute
_semi_exec:
        mov byte [rbp], $C3     ; compile ret (in case called directly)
        inc rbp
        push rbp
        mov rax, [anon]
        call rax                ; execute the anonymous code
        pop rbp
        ;; Reset: recycle anonymous space
        mov rax, [anon]
        mov rbp, rax
        ret

;; =====================================================================
;; Compiler main loop
;; =====================================================================

_compiler:
        call _wsparse
        test ecx, ecx
        jz .done

        ;; Check for ";"
        cmp ecx, 1
        jne .notsc
        cmp byte [rax], ';'
        jne .notsc
        call _semi
        jmp _compiler
.notsc:
        ;; Check for ":"
        cmp ecx, 1
        jne .notcol
        cmp byte [rax], ':'
        jne .notcol
        call _colon
        jmp _compiler
.notcol:
        ;; Try dictionary lookup
        push rax
        push rcx
        call _find
        jnz .notfound
        ;; Found: rax=xt, ecx=ct
        add rsp, 16
        ;; ct=0 → compile call. ct!=0 → execute immediately
        test ecx, ecx
        jnz .execnow
        call _call_compile
        jmp _compiler
.execnow:
        call rax
        jmp _compiler
.notfound:
        pop rcx
        pop rax
        push rcx
        push rax
        call _number
        jz .gotnum
        pop rax
        pop rcx
        jmp .error
.gotnum:
        add rsp, 16
        call _lit_compile
        jmp _compiler
.error:
        push rcx
        push rax
        mov rax, 1
        mov rdi, 1
        lea rsi, [errmsg]
        mov rdx, 7
        syscall
        pop rsi
        pop rdx
        and rsi, -2
        mov rax, 1
        mov rdi, 1
        syscall
        mov rax, 1
        mov rdi, 1
        lea rsi, [nl_char]
        mov rdx, 1
        syscall
        jmp _compiler
.done:  ret

;; =====================================================================
;; I/O
;; =====================================================================

_readline:
        mov rax, 0
        mov rdi, 0
        lea rsi, [inbuf]
        mov rdx, 4096
        syscall
        test rax, rax
        jz .eof
        lea rcx, [inbuf]
        mov [tin], rcx
        lea rcx, [rcx + rax]
        mov [tp], rcx
        test rax, rax
.eof:   ret

;; =====================================================================
;; Header generation macros (built-in words)
;; =====================================================================

macro WORD64 name, xt_val, ct_val, namelen {
    macro GENWORDS64 \{
        dq xt_val
        db ct_val
        db namelen
        db name
        db 0
        GENWORDS64
    \}
}

macro GENWORDS64 {
        dq 0
        db -1
        db 0
        db 0
}

;; Define primitives (last defined = first searched)
WORD64 "cr", _cr, 0, 2
WORD64 "over", _over, 0, 4
WORD64 "swap", _swap, 0, 4
WORD64 "drop", _drop, 0, 4
WORD64 "dup", _dup, 0, 3
WORD64 "*", _mul, 0, 1
WORD64 "-", _sub, 0, 1
WORD64 "+", _add, 0, 1
WORD64 ".", _dot, 0, 1

;; =====================================================================
;; Entry point
;; =====================================================================

_start:
        lea r15, [dstack_top]
        xor ebx, ebx
        xor edx, edx

        lea rax, [heads64]
        mov [H], rax

        lea rbp, [codebuf]
        mov [anon], rbp

.repl:
        mov rax, 1
        mov rdi, 1
        lea rsi, [prompt]
        mov rdx, 2
        syscall

        call _readline
        jz .exit

        ;; Don't reset rbp here — named defs persist in codebuf
        ;; anon is set by _semi/_colon to manage space

        call _compiler

        mov rax, 1
        mov rdi, 1
        lea rsi, [ok_msg]
        mov rdx, 3
        syscall

        jmp .repl

.exit:
        mov rax, 60
        xor rdi, rdi
        syscall

;; =====================================================================
;; Data
;; =====================================================================

prompt:       db "> "
ok_msg:       db "ok"
              db 10
errmsg:       db "error: "
err_noname:   db "error: : without name"
              db 10
err_noname_len = $ - err_noname
minus_char    db '-'
nl_char       db 10
numbuf        rb 21

        align 8
headbuf    rb 65536             ; header space (grows down from heads64)
heads64:   GENWORDS64

inbuf      rb 4096
dstack     rb 8192
dstack_top:
codebuf    rb 65536
