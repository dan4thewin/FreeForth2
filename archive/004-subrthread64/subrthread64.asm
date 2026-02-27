;;; 004-subrthread64: Subroutine threading — compiling CALL instructions
;;; Proves: we can generate relative CALL instructions at runtime,
;;;         which is the basis of FreeForth's subroutine-threaded code.
;;;
;;; FreeForth's POSTPN macro compiles "call <target>" where the target
;;; is encoded as a 32-bit relative offset (E8 xx xx xx xx). This is
;;; the same on x86-64 — the CALL rel32 instruction works identically.
;;;
;;; This experiment:
;;;   1. Has two pre-written subroutines: _add (TOS += NOS, drop NOS)
;;;      and _dot (print TOS as decimal)
;;;   2. Generates code at runtime that calls _add then _dot via POSTPN
;;;   3. Sets up stack with 17 and 25, calls generated code
;;;   4. Should print 42
;;;
;;; Expected output: 42

format elf64
section '.flat' writeable executable
public _start

;; --- Stack macros ---

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

;; --- POSTPN: compile a call instruction ---
;; In FreeForth: HDB $E8; add ebp,5; HDD target,-4; sub [ebp-4],ebp
;; The call instruction is: E8 <relative32>
;; relative32 = target - (address_after_call)

macro POSTPN target {
        mov byte [rbp], $E8             ; call opcode
        add rbp, 5                      ; allocate 5 bytes
        mov dword [rbp-4], target       ; absolute target address (low 32 bits)
        sub [rbp-4], ebp                ; convert to relative: target - rip_after
}

;; --- Subroutines (these are the "primitives" being called) ---

;; _add: TOS = TOS + NOS, drop NOS  (implements Forth "+")
_add:   add rbx, rdx            ; TOS += NOS
        mov rdx, [r15]          ; pop NOS from stack
        add r15, 8
        ret

;; _dot: print TOS as decimal number, then newline, then DROP
_dot:   mov rax, rbx
        lea rdi, [numbuf+20]
        mov rcx, 10
.loop:  xor edx, edx
        div rcx
        add dl, '0'
        dec rdi
        mov [rdi], dl
        test rax, rax
        jnz .loop
        ;; append newline
        lea rsi, [numbuf+20]
        mov byte [rsi], 10
        lea rdx, [numbuf+21]
        sub rdx, rdi
        mov rsi, rdi
        mov rax, 1              ; write
        mov rdi, 1              ; stdout
        syscall
        ;; restore rdx from stack (DROP)
        mov rbx, [r15]          ; this is wrong for DROP but _dot is terminal
        mov rdx, [r15+8]
        add r15, 16
        ret

_start:
        ;; Initialize
        lea r15, [dstack_top]
        xor ebx, ebx
        xor edx, edx

        ;; Set up data stack: 17 25
        DUP1 17
        DUP1 25

        ;; Initialize compilation pointer
        lea rbp, [codebuf]

        ;; Generate: call _add; call _dot; ret
        POSTPN _add
        POSTPN _dot
        mov byte [rbp], $C3    ; ret
        inc rbp

        ;; Call the generated code
        lea rax, [codebuf]
        call rax

        ;; Exit
        mov rax, 60
        xor rdi, rdi
        syscall

numbuf  rb 21
dstack  rb 8192
dstack_top:
codebuf rb 4096
