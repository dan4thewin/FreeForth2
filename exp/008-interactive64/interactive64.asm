;;; 008-interactive64: Interactive FreeForth-style compiler for x86-64
;;; Proves: read-eval-compile loop works interactively from stdin
;;;
;;; Reads lines from stdin, compiles and executes each line ending with ";"
;;; Supports: + - * dup drop swap over . cr
;;; Prints "ok" after each successful compilation+execution
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

H       dq 0                    ; header pointer
anon    dq 0                    ; start of current anonymous def
tin     dq 0                    ; input parse pointer
tp      dq 0                    ; input limit pointer

;; =====================================================================
;; Runtime primitives (called by compiled code)
;; =====================================================================

_add:   add rbx, rdx            ; +
        mov rdx, [r15]
        add r15, 8
        ret

_sub:   xchg rbx, rdx           ; - (NOS - TOS)
        sub rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

_mul:   imul rbx, rdx           ; *
        mov rdx, [r15]
        add r15, 8
        ret

_dup:   sub r15, 8              ; dup
        mov [r15], rdx
        mov rdx, rbx
        ret

_drop:  mov rbx, rdx            ; drop
        mov rdx, [r15]
        add r15, 8
        ret

_swap:  xchg rbx, rdx           ; swap
        ret

_over:  sub r15, 8              ; over (x y -- x y x)
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
        mov rbx, rdx            ; drop TOS
        mov rdx, [r15]
        add r15, 8
        ret

_cr:    push rax                ; cr
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
        mov rax, [rsi]
        xor ecx, ecx
        pop r9
        pop r8
        ret
.e:     mov rcx, r9
        mov rax, r8
        test r9, r9
        pop r9
        pop r8
        ret

_number:
        push r8
        mov r8, rax
        xor edx, edx
        xor r9d, r9d            ; sign flag (0=positive)
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

_semi:  mov byte [rbp], $C3
        inc rbp
        push rbp
        mov rax, [anon]
        call rax
        pop rbp
        ;; Reset compilation pointer for next anonymous def
        mov rax, [anon]
        mov rbp, rax
        ret

;; =====================================================================
;; Compiler main loop — processes input until exhausted
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
        push rax
        push rcx
        call _find
        jnz .notfound
        add rsp, 16
        call _call_compile
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
        ;; continue (don't exit on error in interactive mode)
        jmp _compiler
.done:  ret

;; =====================================================================
;; I/O: Read a line from stdin
;; =====================================================================

;; _readline: read from stdin into inbuf, set tin/tp
;; Returns: ZF set if EOF (zero bytes read)
_readline:
        mov rax, 0              ; sys_read
        mov rdi, 0              ; stdin
        lea rsi, [inbuf]
        mov rdx, 4096
        syscall
        test rax, rax
        jz .eof
        lea rcx, [inbuf]
        mov [tin], rcx
        lea rcx, [rcx + rax]
        mov [tp], rcx
        test rax, rax           ; clear ZF (rax > 0)
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
        ;; Initialize data stack
        lea r15, [dstack_top]
        xor ebx, ebx
        xor edx, edx

        ;; Initialize headers
        lea rax, [heads64]
        mov [H], rax

        ;; Initialize compilation buffer
        lea rbp, [codebuf]
        mov [anon], rbp

.repl:
        ;; Print prompt
        mov rax, 1
        mov rdi, 1
        lea rsi, [prompt]
        mov rdx, 2
        syscall

        ;; Read input
        call _readline
        jz .exit                ; EOF

        ;; Reset compilation pointer
        lea rbp, [codebuf]
        mov [anon], rbp

        ;; Compile and execute
        call _compiler

        ;; Print "ok" after successful line
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

prompt:    db "> "
ok_msg:    db "ok"
           db 10
errmsg:    db "error: "
minus_char db '-'
nl_char    db 10
numbuf     rb 21

        align 8
heads64: GENWORDS64

inbuf      rb 4096
dstack     rb 8192
dstack_top:
codebuf    rb 65536
