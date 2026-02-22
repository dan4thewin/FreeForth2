;;; 007-minicompiler64: Minimal FreeForth-style compiler loop for x86-64
;;; Proves: the complete compile-and-execute cycle works on x86-64
;;;
;;; This is a minimal but real compiler that:
;;;   1. Reads whitespace-delimited words from a hardcoded input buffer
;;;   2. Looks up each word in a dictionary of primitives
;;;   3. If found: compiles a CALL to its runtime entry
;;;   4. If not found: tries to parse as a number and compile a literal
;;;   5. ";" closes the definition, executes it, and resets
;;;
;;; The compiler loop uses registers only (no Forth data stack).
;;; The data stack (r15, rbx, rdx) is only touched by generated code.
;;;
;;; Register allocation:
;;;   rbx = TOS, rdx = NOS, r15 = data stack pointer
;;;   rsp = call stack, rbp = compilation pointer ("here")
;;;
;;; Built-in words: + - * dup drop swap . cr
;;; Test: "3 4 + . cr ;" → "7 \n"
;;;       "10 3 - . cr ;" → "7 \n"
;;;       "6 7 * . cr ;" → "42 \n"

format elf64
section '.flat' writeable executable
public _start

h.ct = 8
h.sz = 9
h.nm = 10

;; =====================================================================
;; Stack operation macros (for the compiler itself, not generated code)
;; =====================================================================

macro DROP1 {
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
}

macro DUP1 arg {
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
  if arg eq
  else if (arg eqtype 0) & (arg = 0)
        xor ebx, ebx
  else
        mov rbx, arg
  end if
}

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

_mul:   imul rbx, rdx            ; *
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
;; Compiler core (register-only, no Forth data stack usage)
;; =====================================================================

;; wsparse: parse next word. Returns rax=addr, rcx=len (0 at end)
;; Does NOT use the Forth data stack at all.
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
.word:  mov rax, rdi            ; start of word
.scan:  inc rdi
        cmp rdi, rsi
        jae .done
        cmp byte [rdi], ' '
        ja .scan
.done:  mov [tin], rdi
        mov rcx, rdi
        sub rcx, rax            ; length
        ret

;; find: look up word. rax=addr, rcx=len
;; Returns: rax=xt, ZF set if found. Preserves rcx on not-found.
_find:  push r8
        push r9
        mov r8, rax             ; save word addr
        mov r9, rcx             ; save word len
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
        xor ecx, ecx           ; ZF set
        pop r9
        pop r8
        ret
.e:     mov rcx, r9             ; restore word len
        mov rax, r8             ; restore word addr
        or ecx, ecx             ; clear ZF (ecx was 0 from jecxz, now restored)
        test r9, r9             ; r9 > 0 so ZF clear
        pop r9
        pop r8
        ret

;; number: try to parse as decimal (or $hex). rax=addr, rcx=len
;; Returns: rax=number, ZF set on success.
_number:
        push r8
        mov r8, rax             ; save addr
        xor edx, edx            ; accumulator
        xor r9d, r9d            ; sign flag (0=positive)
        mov rsi, rax
        lea rdi, [rax + rcx]
        ;; check for $hex prefix
        cmp byte [rsi], '$'
        je .hex_start
        ;; check for leading minus
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
        sub al, 32              ; lowercase
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
        xor edx, edx            ; ZF set = success
        ret
.fail:  mov rax, r8             ; restore
        pop r8
        or eax, 1               ; ZF clear = failure (won't change rax much)
        ret

;; call_compile: compile call to target. rax=target address
_call_compile:
        mov byte [rbp], $E8     ; call rel32
        lea rcx, [rbp+5]       ; address after call instruction
        sub eax, ecx            ; relative offset (32-bit)
        mov dword [rbp+1], eax
        add rbp, 5
        ret

;; lit_compile: compile DUP1 <imm>. rax=value
_lit_compile:
        ;; sub r15, 8    → 49 83 EF 08
        mov dword [rbp], $08EF8349
        add rbp, 4
        ;; mov [r15], rdx → 49 89 17
        mov byte [rbp], $49
        mov word [rbp+1], $1789
        add rbp, 3
        ;; mov rdx, rbx  → 48 89 DA
        mov byte [rbp], $48
        mov word [rbp+1], $DA89
        add rbp, 3
        ;; Check if fits in 32-bit zero-extended
        mov rcx, rax
        mov eax, eax            ; zero-extend to check
        cmp rax, rcx
        jne .big
        ;; mov ebx, imm32 → BB <dword>
        mov byte [rbp], $BB
        mov dword [rbp+1], eax
        add rbp, 5
        ret
.big:   ;; mov rbx, imm64 → 48 BB <qword>
        mov byte [rbp], $48
        mov byte [rbp+1], $BB
        mov qword [rbp+2], rcx
        add rbp, 10
        ret

;; =====================================================================
;; Compiler main loop
;; =====================================================================

_semi:  mov byte [rbp], $C3     ; compile ret
        inc rbp
        push rbp                ; save compilation pointer
        mov rax, [anon]
        call rax                ; execute generated code
        pop rbp
        mov rax, [anon]         ; reset compilation pointer
        mov rbp, rax
        ret

_compiler:
        call _wsparse           ; rax=addr, rcx=len
        test ecx, ecx
        jz .done

        ;; check for ";"
        cmp ecx, 1
        jne .notsc
        cmp byte [rax], ';'
        jne .notsc
        call _semi
        jmp _compiler
.notsc:
        ;; save word addr/len across find
        push rax                ; word addr
        push rcx                ; word len
        call _find              ; rax=xt if found (ZF set)
        jnz .notfound

        ;; found: rax = xt. Compile call.
        add rsp, 16             ; discard saved addr/len
        call _call_compile
        jmp _compiler

.notfound:
        pop rcx                 ; word len
        pop rax                 ; word addr
        push rcx                ; re-save len for error case
        push rax                ; re-save addr for error case
        call _number            ; rax=number if success (ZF set)
        jz .gotnum
        ;; error: unknown word
        pop rax                 ; word addr
        pop rcx                 ; word len
        jmp .error

.gotnum:
        add rsp, 16             ; discard saved addr/len
        call _lit_compile
        jmp _compiler

.error:
        ;; print error message with the word
        ;; At this point rax = word addr (possibly corrupted), rcx = word len
        push rcx                ; save word len
        push rax                ; save word addr
        mov rax, 1
        mov rdi, 1
        lea rsi, [errmsg]
        mov rdx, 7
        syscall
        pop rsi                 ; word addr
        pop rdx                 ; word len
        ;; fix addr: _number may have OR'd bit 0
        and rsi, -2
        mov rax, 1
        mov rdi, 1
        syscall
        mov rax, 1
        mov rdi, 1
        lea rsi, [nl_char]
        mov rdx, 1
        syscall
        mov rax, 60
        mov rdi, 1
        syscall

.done:  ret

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

        ;; === Test 1: "3 4 + . cr ;" ===
        lea rax, [test1]
        mov [tin], rax
        lea rax, [test1end]
        mov [tp], rax

        lea rbp, [codebuf]
        mov [anon], rbp

        call _compiler

        ;; === Test 2: "10 3 - . cr ;" ===
        lea rax, [test2]
        mov [tin], rax
        lea rax, [test2end]
        mov [tp], rax

        lea rbp, [codebuf]
        mov [anon], rbp

        call _compiler

        ;; === Test 3: "6 7 * . cr ;" ===
        lea rax, [test3]
        mov [tin], rax
        lea rax, [test3end]
        mov [tp], rax

        lea rbp, [codebuf]
        mov [anon], rbp

        call _compiler

        ;; Exit
        mov rax, 60
        xor rdi, rdi
        syscall

;; =====================================================================
;; Data
;; =====================================================================

test1:     db "3 4 + . cr ;"
test1end:
test2:     db "10 3 - . cr ;"
test2end:
test3:     db "6 7 * . cr ;"
test3end:

errmsg:    db "error: "
minus_char db '-'
nl_char    db 10
numbuf     rb 21

        align 8
heads64: GENWORDS64

dstack     rb 8192
dstack_top:
codebuf    rb 65536
