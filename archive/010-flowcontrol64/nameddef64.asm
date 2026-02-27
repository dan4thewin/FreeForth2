;;; 010-flowcontrol64: Flow control (IF/THEN/ELSE/BEGIN/AGAIN/UNTIL)
;;; Proves: compile-time words can generate forward/backward branches
;;;
;;; Compile-time words (ct=1) are executed during compilation.
;;; They use the data stack to pass patch addresses.
;;;
;;; IF:    test TOS, drop, compile jz <fwd placeholder>, push patch addr
;;; THEN:  pop patch addr, resolve forward jump
;;; ELSE:  compile jmp <fwd placeholder>, resolve IF's jz, push new patch
;;; BEGIN: push here (loop target)
;;; AGAIN: compile jmp <back> to BEGIN's address
;;; UNTIL: test TOS, drop, compile jz <back> (loop while false)
;;;
;;; Also adds: = < > 0= 0<> negate (runtime comparison words)
;;;
;;; Test: `: abs dup 0< IF negate THEN ; -5 abs . cr ;` → 5
;;;       `: countdown BEGIN dup . 1 - dup 0= UNTIL drop cr ; 5 countdown ;`

format elf64
section '.flat' writeable executable
public _start

h.ct = 8
h.sz = 9
h.nm = 10

;; =====================================================================
;; Compiler state
;; =====================================================================

H       dq 0
anon    dq 0
tin     dq 0
tp      dq 0

;; =====================================================================
;; Runtime primitives
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

_negate:
        neg rbx
        ret

_eq:    cmp rdx, rbx            ; = ( a b -- flag )
        sete cl
        movzx ebx, cl
        neg rbx
        mov rdx, [r15]
        add r15, 8
        ret

_lt:    cmp rdx, rbx            ; < ( a b -- flag )
        setl cl
        movzx ebx, cl
        neg rbx
        mov rdx, [r15]
        add r15, 8
        ret

_gt:    cmp rdx, rbx            ; > ( a b -- flag )
        setg cl
        movzx ebx, cl
        neg rbx
        mov rdx, [r15]
        add r15, 8
        ret

_zeq:   test rbx, rbx           ; 0= ( n -- flag )
        mov rbx, 0
        sete bl
        neg rbx
        ret

_zneq:  test rbx, rbx           ; 0<> ( n -- flag )
        mov rbx, 0
        setne bl
        neg rbx
        ret

_zlt:   test rbx, rbx           ; 0< ( n -- flag )
        sar rbx, 63             ; -1 if negative, 0 if positive
        ret

_dot:   push r15
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

_one:   sub r15, 8              ; 1 (push literal 1)
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, 1
        ret

;; =====================================================================
;; Compile-time words (ct=1): executed during compilation
;; These use the data stack (rbx/rdx/r15) to track patch addresses.
;; rbp = compilation pointer.
;; =====================================================================

;; IF: test TOS, drop, compile jz <fwd>. Push patch address.
_if:
        ;; Compile: test rbx, rbx (48 85 DB)
        mov byte [rbp], $48
        mov word [rbp+1], $DB85
        add rbp, 3
        ;; Compile: DROP1 (flag-preserving: use lea instead of add)
        ;;   mov rbx, rdx      → 48 89 D3
        mov byte [rbp], $48
        mov word [rbp+1], $D389
        add rbp, 3
        ;;   mov rdx, [r15]    → 49 8B 17
        mov byte [rbp], $49
        mov word [rbp+1], $178B
        add rbp, 3
        ;;   lea r15, [r15+8]  → 4D 8D 7F 08 (preserves flags!)
        mov dword [rbp], $087F8D4D
        add rbp, 4
        ;; Compile: jz rel32   → 0F 84 xx xx xx xx
        mov byte [rbp], $0F
        mov byte [rbp+1], $84
        add rbp, 2
        ;; Push address of the rel32 placeholder onto data stack
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, rbp
        add rbp, 4              ; skip past the 4-byte placeholder
        ret

;; THEN: resolve forward jump. TOS = patch address.
_then:
        ;; Calculate offset: here - (patch_addr + 4)
        mov rax, rbp
        sub rax, rbx
        sub rax, 4
        mov dword [rbx], eax    ; patch the jump offset
        ;; Drop patch address
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

;; ELSE: compile jmp <fwd>, resolve IF, push new patch address
_else:
        ;; Compile: jmp rel32 → E9 xx xx xx xx
        mov byte [rbp], $E9
        inc rbp
        ;; Save new patch address
        mov rax, rbp
        add rbp, 4
        ;; Resolve the IF (TOS = IF's patch address)
        mov rcx, rbp
        sub rcx, rbx
        sub rcx, 4
        mov dword [rbx], ecx
        ;; Replace TOS with new patch address
        mov rbx, rax
        ret

;; BEGIN: push here (loop target address)
_begin:
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, rbp            ; TOS = current compilation pointer
        ret

;; AGAIN: compile unconditional jump back to BEGIN address
_again:
        ;; Compile: jmp rel32 → E9 xx xx xx xx
        mov byte [rbp], $E9
        inc rbp
        ;; Calculate backward offset: target - (here + 4)
        mov rax, rbx
        lea rcx, [rbp + 4]
        sub rax, rcx
        mov dword [rbp], eax
        add rbp, 4
        ;; Drop target address
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

;; UNTIL: test TOS, drop, compile jz <back> (loop while false)
_until:
        ;; Compile: test rbx, rbx (48 85 DB)
        mov byte [rbp], $48
        mov word [rbp+1], $DB85
        add rbp, 3
        ;; Compile: DROP1 (flag-preserving)
        mov byte [rbp], $48
        mov word [rbp+1], $D389
        add rbp, 3
        mov byte [rbp], $49
        mov word [rbp+1], $178B
        add rbp, 3
        mov dword [rbp], $087F8D4D
        add rbp, 4
        ;; Compile: jz rel32 → 0F 84 xx xx xx xx
        mov byte [rbp], $0F
        mov byte [rbp+1], $84
        add rbp, 2
        ;; Calculate backward offset: target - (here + 4)
        mov rax, rbx
        lea rcx, [rbp + 4]
        sub rax, rcx
        mov dword [rbp], eax
        add rbp, 4
        ;; Drop target address
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

;; WHILE: like IF but used inside BEGIN...WHILE...REPEAT
;; (same as IF — pushes patch address)
_while:
        jmp _if                 ; identical behavior

;; REPEAT: compile jmp <back to BEGIN>, then resolve WHILE
_repeat:
        ;; TOS = WHILE's patch addr, NOS = BEGIN's target
        ;; First: compile jmp back to BEGIN (NOS)
        mov byte [rbp], $E9
        inc rbp
        mov rax, rdx            ; BEGIN address
        lea rcx, [rbp + 4]
        sub rax, rcx
        mov dword [rbp], eax
        add rbp, 4
        ;; Now resolve WHILE's forward jump (TOS)
        mov rax, rbp
        sub rax, rbx
        sub rax, 4
        mov dword [rbx], eax
        ;; Drop both addresses
        mov rbx, [r15]
        mov rdx, [r15+8]
        add r15, 16
        ret

;; =====================================================================
;; Compiler core (from exp 009, with ct support)
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
        movzx ecx, byte [rsi + h.ct]
        ;; If ct=0: test sets ZF (found, runtime). If ct!=0: ZF clear.
        ;; Caller checks: jnz = not found OR compile-time
        ;; We need a different signaling: return with a flag
        ;; Let's use: rcx=0 → runtime word found, rcx>0 → compile-time found
        ;; rcx<0 (from sentinel) → not found
        ;; Actually, let's use the sign: ct=0xFF (sentinel) = -1 = not found
        cmp cl, $FF
        je .e_notfound
        ;; Found: rax=xt, ecx=ct (0=runtime, nonzero=compile-time)
        pop r9
        pop r8
        clc                     ; CF clear = found
        ret
.e:
.e_notfound:
        mov rcx, r9
        mov rax, r8
        pop r9
        pop r8
        stc                     ; CF set = not found
        ret

_number:
        push r8
        push rdx                ; save NOS (data stack)
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
        pop rdx                 ; restore NOS
        pop r8
        cmp rax, rax            ; ZF set = success
        ret
.fail:  mov rax, r8
        pop rdx                 ; restore NOS
        pop r8
        test rax, rax           ; ZF clear (word addr is never 0)
        ret

_call_compile:
        mov byte [rbp], $E8
        lea rcx, [rbp+5]
        sub eax, ecx
        mov dword [rbp+1], eax
        add rbp, 5
        ret

_lit_compile:
        mov dword [rbp], $08EF8349
        add rbp, 4
        mov byte [rbp], $49
        mov word [rbp+1], $1789
        add rbp, 3
        mov byte [rbp], $48
        mov word [rbp+1], $DA89
        add rbp, 3
        mov rcx, rax
        mov eax, eax
        cmp rax, rcx
        jne .big
        mov byte [rbp], $BB
        mov dword [rbp+1], eax
        add rbp, 5
        ret
.big:   mov byte [rbp], $48
        mov byte [rbp+1], $BB
        mov qword [rbp+2], rcx
        add rbp, 10
        ret

_header:
        push rdi
        push rsi
        push rcx
        mov rsi, rax
        mov rdi, [H]
        dec rdi
        sub rdi, rcx
        mov byte [rdi - 1], cl
        mov byte [rdi - 2], r9b
        lea rax, [rdi - h.nm]
        mov [rax], r8
        mov [H], rax
        push rcx
        rep movsb
        pop rcx
        mov byte [rdi], 0
        pop rcx
        pop rsi
        pop rdi
        ret

_colon:
        mov rax, [anon]
        test rax, rax
        jz .no_anon
        call _semi_exec
.no_anon:
        call _wsparse
        test ecx, ecx
        jz .missing_name
        mov r8, rbp
        xor r9d, r9d
        call _header
        mov qword [anon], 0
        ret
.missing_name:
        push rax
        mov rax, 1
        mov rdi, 1
        lea rsi, [err_noname]
        mov rdx, err_noname_len
        syscall
        pop rax
        ret

_semi:
        mov byte [rbp], $C3
        inc rbp
        mov rax, [anon]
        test rax, rax
        jnz .anonymous
        mov [anon], rbp
        ret
.anonymous:
_semi_exec:
        mov byte [rbp], $C3
        inc rbp
        push rbp
        mov rax, [anon]
        call rax
        pop rbp
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

        cmp ecx, 1
        jne .notsc
        cmp byte [rax], ';'
        jne .notsc
        call _semi
        jmp _compiler
.notsc:
        cmp ecx, 1
        jne .notcol
        cmp byte [rax], ':'
        jne .notcol
        call _colon
        jmp _compiler
.notcol:
        push rax
        push rcx
        call _find
        jc .notfound
        ;; Found: rax=xt, ecx=ct
        add rsp, 16
        test ecx, ecx
        jnz .execnow
        call _call_compile
        jmp _compiler
.execnow:
        call rax                ; execute compile-time word
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
;; Header generation macros
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

;; Runtime words (ct=0)
WORD64 "cr", _cr, 0, 2
WORD64 "over", _over, 0, 4
WORD64 "swap", _swap, 0, 4
WORD64 "drop", _drop, 0, 4
WORD64 "dup", _dup, 0, 3
WORD64 "negate", _negate, 0, 6
WORD64 "0<", _zlt, 0, 2
WORD64 "0<>", _zneq, 0, 3
WORD64 "0=", _zeq, 0, 2
WORD64 ">", _gt, 0, 1
WORD64 "<", _lt, 0, 1
WORD64 "=", _eq, 0, 1
WORD64 "1", _one, 0, 1
WORD64 "*", _mul, 0, 1
WORD64 "-", _sub, 0, 1
WORD64 "+", _add, 0, 1
WORD64 ".", _dot, 0, 1

;; Compile-time words (ct=1)
WORD64 "REPEAT", _repeat, 1, 6
WORD64 "WHILE", _while, 1, 5
WORD64 "UNTIL", _until, 1, 5
WORD64 "AGAIN", _again, 1, 5
WORD64 "BEGIN", _begin, 1, 5
WORD64 "ELSE", _else, 1, 4
WORD64 "THEN", _then, 1, 4
WORD64 "IF", _if, 1, 2

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
headbuf    rb 65536
heads64:   GENWORDS64

inbuf      rb 4096
dstack     rb 8192
dstack_top:
codebuf    rb 65536
