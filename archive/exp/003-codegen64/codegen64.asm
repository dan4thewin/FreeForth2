;;; 003-codegen64: Runtime x86-64 code generation
;;; Proves: we can generate x86-64 machine code at runtime into a
;;;         writeable+executable buffer and call it — the core of
;;;         FreeForth's compile-and-execute model.
;;;
;;; This experiment:
;;;   1. Allocates a code buffer (writeable+executable section)
;;;   2. Uses rbp as the compilation pointer ("here") — just like FreeForth
;;;   3. Generates code for: DUP1 42, then RET
;;;   4. Sets up r15 data stack, then calls the generated code
;;;   5. Prints TOS (should be 42)
;;;
;;; Expected output: 42

format elf64
section '.text' executable
public _start

;; --- Stack macros (from experiment 002) ---

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

;; --- Code generation helpers ---
;; rbp = compilation pointer (advances as we emit bytes)

macro EMIT_BYTE val {
        mov byte [rbp], val
        inc rbp
}

macro EMIT_WORD val {
        mov word [rbp], val
        add rbp, 2
}

macro EMIT_DWORD val {
        mov dword [rbp], val
        add rbp, 4
}

macro EMIT_QWORD val {
        mov qword [rbp], val
        add rbp, 8
}

;; --- Number printing ---
print_num:
        mov rax, rbx
        lea rdi, [numbuf+20]
        mov rcx, 10
.loop:  xor edx, edx
        div rcx
        add dl, '0'
        dec rdi
        mov [rdi], dl
        test rax, rax
        jnz .loop
        ;; write newline too
        lea rdx, [numbuf+20]
        sub rdx, rdi
        mov rsi, rdi
        mov rax, 1
        mov rdi, 1
        syscall
        ;; newline
        mov rax, 1
        mov rdi, 1
        lea rsi, [nl_char]
        mov rdx, 1
        syscall
        ret

_start:
        ;; Initialize data stack
        lea r15, [dstack_top]
        xor ebx, ebx           ; TOS = 0
        xor edx, edx           ; NOS = 0

        ;; Initialize compilation pointer
        lea rbp, [codebuf]

        ;; --- Generate code for "DUP1 42" ---
        ;; DUP1 42 in x86-64 with r15 data stack:
        ;;   49 83 EF 08       sub r15, 8
        ;;   49 89 17           mov [r15], rdx
        ;;   48 89 DA           mov rdx, rbx
        ;;   BB 2A000000        mov ebx, 42    (32-bit mov, zero-extends)

        ;; sub r15, 8
        EMIT_BYTE $49
        EMIT_BYTE $83
        EMIT_BYTE $EF
        EMIT_BYTE $08

        ;; mov [r15], rdx
        EMIT_BYTE $49
        EMIT_BYTE $89
        EMIT_BYTE $17

        ;; mov rdx, rbx
        EMIT_BYTE $48
        EMIT_BYTE $89
        EMIT_BYTE $DA

        ;; mov ebx, 42  (zero-extends to rbx)
        EMIT_BYTE $BB
        EMIT_DWORD 42

        ;; ret
        EMIT_BYTE $C3

        ;; --- Call the generated code ---
        ;; Save rbp (compilation pointer) since generated code doesn't touch it
        lea rax, [codebuf]
        call rax

        ;; rbx should now be 42
        call print_num          ; prints "42\n"

        ;; Exit
        mov rax, 60
        xor rdi, rdi
        syscall

section '.data' writeable
nl_char db 10
numbuf  rb 21

section '.bss' writeable
dstack     rb 8192
dstack_top:

;; Writeable AND executable buffer for generated code
;; In the real FreeForth, the code/data/headers all live in one flat section
section '.codebuf' writeable executable
codebuf rb 4096
