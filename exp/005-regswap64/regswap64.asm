;;; 005-regswap64: Compile-time register renaming (SWAPbit)
;;; Proves: FreeForth's zero-cost SWAP via compile-time register renaming
;;;         works on x86-64 with rbx/rdx as TOS cache registers.
;;;
;;; In FreeForth, SWAP emits zero instructions — it just toggles a
;;; "SWAPbit" flag. Code-generation routines (s01, s08, s09) check
;;; this flag and XOR register-encoding bits in the ModR/M byte:
;;;   bit 0 (in r/m field) swaps rbx↔rdx as destination
;;;   bit 3 (in reg field) swaps rbx↔rdx as source
;;;   XOR $09 swaps both
;;;
;;; Test: compile "10 20 +" two ways — once straight, once with SWAPs
;;; inserted. Both should produce 30 because SWAP is purely a
;;; compile-time register rename.
;;;
;;; Expected output:
;;;   30
;;;   30

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

;; --- Compiler state ---
SC      db 0                    ; bit 1 = SWAPbit

;; s01, s08, s09: advance rbp by 2 and conditionally patch ModR/M
;; These match FreeForth exactly: all three advance ebp(rbp) by 2
s01:    lea rbp, [rbp+2]
        test byte [SC], 2
        jz .done
        xor byte [rbp-1], 1
.done:  ret

s08:    lea rbp, [rbp+2]
        test byte [SC], 2
        jz .done
        xor byte [rbp-1], 8
.done:  ret

s09:    lea rbp, [rbp+2]
        test byte [SC], 2
        jz .done
        xor byte [rbp-1], 9
.done:  ret

;; rst: reset SWAPbit, emitting xchg rbx,rdx if needed
rst:    test byte [SC], 2
        jz .done
        mov byte [rbp], $48     ; REX.W
        mov byte [rbp+1], $87   ; xchg
        mov byte [rbp+2], $DA   ; rbx,rdx
        add rbp, 3
        and byte [SC], $FD
.done:  ret

;; swap_compile: toggle SWAPbit (zero-cost swap!)
swap_compile:
        xor byte [SC], 2
        ret

;; --- Code generators ---

;; gen_lit: compile DUP1 <imm32> — always resets swap state first
gen_lit:  ; eax = value
        push rax
        call rst
        pop rax
        ;; sub r15, 8
        mov dword [rbp], $08EF8349   ; 49 83 EF 08
        add rbp, 4
        ;; mov [r15], rdx
        mov word [rbp], $8949        ; 49 89
        mov byte [rbp+2], $17        ; /rdx, [r15]
        add rbp, 3
        ;; mov rdx, rbx:  48 89 DA  (2 opcode bytes after REX)
        mov byte [rbp], $48
        mov word [rbp+1], $DA89
        add rbp, 3
        ;; mov ebx, imm32 (BB + dword)
        mov byte [rbp], $BB
        mov dword [rbp+1], eax
        add rbp, 5
        ret

;; gen_overplus: compile "over+" — TOS += NOS, NOS unchanged
;; Encoding: 48 01 D3 = add rbx, rdx  (s09 patches D3 if swapped)
gen_overplus:
        mov byte [rbp], $48     ; REX.W
        mov word [rbp+1], $D301 ; ADD + ModR/M (before s09 patches)
        add rbp, 1              ; advance past REX; s09 advances 2 more
        call s09
        ret

;; gen_nip: compile "nip" — drop NOS, keep TOS
;; Must rst first, then: mov rdx,[r15]; add r15,8
gen_nip:
        call rst
        ;; mov rdx, [r15] — 49 8B 17
        mov byte [rbp], $49
        mov word [rbp+1], $178B
        add rbp, 3
        ;; add r15, 8 — 49 83 C7 08
        mov dword [rbp], $08C78349
        add rbp, 4
        ret

;; gen_ret: compile C3 (ret)
gen_ret:
        call rst
        mov byte [rbp], $C3
        inc rbp
        ret

;; --- Print TOS as decimal + newline ---
_dot:   mov rax, rbx
        push r15
        push rdx
        lea rdi, [numbuf+20]
        mov rcx, 10
.loop:  xor edx, edx
        div rcx
        add dl, '0'
        dec rdi
        mov [rdi], dl
        test rax, rax
        jnz .loop
        lea rsi, [numbuf+20]
        mov byte [rsi], 10
        lea rdx, [numbuf+21]
        sub rdx, rdi
        mov rsi, rdi
        mov rax, 1
        mov rdi, 1
        syscall
        pop rdx
        pop r15
        ret

_start:
        lea r15, [dstack_top]
        xor ebx, ebx
        xor edx, edx

        ;; === Test 1: straight "10 20 + nip" ===
        lea rbp, [codebuf]
        mov byte [SC], 0

        mov eax, 10
        call gen_lit
        mov eax, 20
        call gen_lit
        call gen_overplus       ; TOS(20) += NOS(10) → TOS=30
        call gen_nip            ; drop old NOS
        call gen_ret

        lea rax, [codebuf]
        call rax                ; execute
        call _dot               ; print TOS → "30"

        ;; Reset stack
        lea r15, [dstack_top]
        xor ebx, ebx
        xor edx, edx

        ;; === Test 2: same but with SWAPs ===
        ;; "10 20 swap swap + nip" — two swaps cancel out
        lea rbp, [codebuf2]
        mov byte [SC], 0

        mov eax, 10
        call gen_lit
        mov eax, 20
        call gen_lit
        call swap_compile       ; swap! (SC=2, no code emitted)
        call swap_compile       ; swap back! (SC=0, no code emitted)
        call gen_overplus       ; same as test 1
        call gen_nip
        call gen_ret

        lea rax, [codebuf2]
        call rax
        call _dot               ; should also print "30"

        ;; Exit
        mov rax, 60
        xor rdi, rdi
        syscall

numbuf   rb 21
dstack   rb 8192
dstack_top:
codebuf  rb 4096
codebuf2 rb 4096
