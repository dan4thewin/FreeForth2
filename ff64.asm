;;; ff64.asm — FreeForth2 x86-64 kernel
;;;
;;; A subroutine-threaded Forth compiler for Linux x86-64.
;;; Ported from Christophe Lavarenne's i386 FreeForth2.
;;;
;;; Key features:
;;;   - 18 inline code generators with SWAPbit-aware register selection
;;;   - swap emits zero code (compile-time register rename via s01/s08/s09)
;;;   - Dedicated data stack pointer (r15) instead of xchg eax,esp trick
;;;   - Command-line -f <file> support for loading boot files

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
filebuf_ptr dq 0
SC      db 0                    ; SWAPbit in bit 1: 0=rbx is TOS, 2=rdx is TOS
cond_jmp db 0                   ; ?# : pending conditional jump opcode (0=none)

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

_swap:  xchg rbx, rdx           ; runtime swap (still available)
        ret

;; Compile-time swap: just toggle SWAPbit, emit nothing
_swap_ct:
        xor byte [SC], 2        ; toggle bit 1
        ret

;; rst: if SWAPbit set, emit xchg rbx,rdx and clear it
_rst:   test byte [SC], 2
        jz .done
        mov byte [rbp], $48     ; xchg rbx, rdx = 48 87 DA
        mov word [rbp+1], $DA87
        add rbp, 3
        and byte [SC], $FD      ; clear bit 1
.done:  ret

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

_two:   sub r15, 8              ; 2 (push literal 2)
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, 2
        ret

;; Return stack words
;; Note: rsp has the return address from calling >r/r>/r@, so we work
;; around it: pop ret addr, do the operation, push ret addr back.
_tor:   pop rax                 ; >r ( x -- ) R:( -- x )
        push rbx
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        jmp rax

_rfrom: pop rax                 ; r> ( -- x ) R:( x -- )
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        pop rbx
        jmp rax

_rfetch: pop rax                ; r@ ( -- x ) R:( x -- x )
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, [rsp]
        jmp rax

;; String/memory operations
_zlen:  mov rax, rbx            ; zlen ( addr -- len )
        xor ecx, ecx
.loop:  cmp byte [rax], 0
        je .done
        inc rax
        inc ecx
        jmp .loop
.done:  mov rbx, rcx
        ret

_cmove: push rsi                ; cmove ( src dst n -- )
        push rdi
        mov rcx, rbx            ; n
        mov rdi, rdx            ; dst
        mov rsi, [r15]          ; src
        rep movsb
        pop rdi
        pop rsi
        mov rbx, [r15+8]
        mov rdx, [r15+16]
        add r15, 24
        ret

_fill:  push rdi                ; fill ( addr n char -- )
        mov rax, rbx            ; char
        mov rcx, rdx            ; n
        mov rdi, [r15]          ; addr
        rep stosb
        pop rdi
        mov rbx, [r15+8]
        mov rdx, [r15+16]
        add r15, 24
        ret

_erase: push rdi                ; erase ( addr n -- )
        mov rcx, rbx            ; n
        mov rdi, rdx            ; addr
        xor eax, eax
        rep stosb
        pop rdi
        mov rbx, [r15]
        mov rdx, [r15+8]
        add r15, 16
        ret

;; Emit a single character
_emit:  push rax                ; emit ( char -- )
        push rdi
        push rsi
        push rdx
        mov [numbuf], bl        ; reuse numbuf as temp
        mov rax, 1
        mov rdi, 1
        lea rsi, [numbuf]
        mov rdx, 1
        syscall
        pop rdx
        pop rsi
        pop rdi
        pop rax
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

;; Memory access words
_fetch: mov rbx, [rbx]          ; @ ( addr -- val )
        ret

_store: mov [rbx], rdx          ; ! ( val addr -- )
        mov rbx, [r15]
        mov rdx, [r15+8]
        add r15, 16
        ret

_cfetch: movzx rbx, byte [rbx]  ; c@ ( addr -- char )
        ret

_cstore: mov [rbx], dl          ; c! ( char addr -- )
        mov rbx, [r15]
        mov rdx, [r15+8]
        add r15, 16
        ret

_addstore:                      ; +! ( n addr -- )
        add [rbx], rdx
        mov rbx, [r15]
        mov rdx, [r15+8]
        add r15, 16
        ret

;; More arithmetic
_div:   mov rcx, rbx            ; / ( a b -- a/b ) — rcx = divisor
        mov rax, rdx            ; rax = dividend (NOS)
        cqo                     ; sign-extend rax into rdx:rax
        idiv rcx
        mov rbx, rax            ; quotient
        mov rdx, [r15]
        add r15, 8
        ret

_mod:   mov rcx, rbx            ; mod ( a b -- a-mod-b )
        mov rax, rdx            ; rax = dividend (NOS)
        cqo
        idiv rcx
        mov rbx, rdx            ; remainder
        mov rdx, [r15]
        add r15, 8
        ret

_divmod: mov rcx, rbx           ; /mod ( a b -- rem quot )
        mov rax, rdx            ; rax = dividend (NOS)
        cqo
        idiv rcx
        mov rbx, rax            ; quotient in TOS
        mov rdx, rdx            ; remainder already in rdx (NOS)
        ret

;; Bitwise operations
_and:   and rbx, rdx            ; and ( a b -- a&b )
        mov rdx, [r15]
        add r15, 8
        ret

_or:    or rbx, rdx             ; or ( a b -- a|b )
        mov rdx, [r15]
        add r15, 8
        ret

_xor:   xor rbx, rdx            ; xor ( a b -- a^b )
        mov rdx, [r15]
        add r15, 8
        ret

_not:   not rbx                 ; not ( a -- ~a )
        ret

;; More stack manipulation
_rot:   xchg rdx, [r15]         ; rot ( a b c -- b c a )
        xchg rbx, rdx
        ret

_nip:   mov rdx, [r15]          ; nip ( a b -- b )
        add r15, 8
        ret

_tuck:  sub r15, 8              ; tuck ( a b -- b a b )
        mov [r15], rbx
        ret

_depth: sub r15, 8              ; depth ( -- n )
        mov [r15], rdx
        mov rdx, rbx
        lea rbx, [dstack_top]
        sub rbx, r15
        sar rbx, 3              ; divide by 8 (cell size)
        ret

;; Memory compilation words
_here:  sub r15, 8              ; here ( -- addr )
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, rbp
        ret

_allot: add rbp, rbx            ; allot ( n -- )
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

_comma: mov [rbp], rbx          ; , ( x -- ) compile 8-byte cell
        add rbp, 8
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

_ccomma: mov [rbp], bl          ; c, ( c -- ) compile byte
        add rbp, 1
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

;; Shift operations
_lshift: mov rcx, rbx           ; lshift ( a n -- a<<n )
        mov rbx, rdx
        shl rbx, cl
        mov rdx, [r15]
        add r15, 8
        ret

_rshift: mov rcx, rbx           ; rshift ( a n -- a>>n )
        mov rbx, rdx
        sar rbx, cl
        mov rdx, [r15]
        add r15, 8
        ret

;; =====================================================================
;; SWAPbit register-swap functions: s01, s08, s09
;;
;; These implement FreeForth's signature compile-time optimization.
;; rbx (register 3, binary 011) and rdx (register 2, binary 010)
;; differ by exactly one bit. By XORing the ModR/M byte of emitted
;; instructions, we swap which register plays TOS vs NOS.
;;
;; s01: XOR bit 0 of ModR/M — swap the r/m field (destination)
;; s08: XOR bit 3 of ModR/M — swap the reg field (source)
;; s09: XOR bits 0 and 3     — swap both fields
;;
;; Each function checks the SWAPbit (bit 1 of SC). If clear, it does
;; nothing. If set, it XORs [rbp-1] (the last emitted ModR/M byte).
;; =====================================================================

_s09:   mov ch, $09
        jmp _sx
_s08:   mov ch, $08
        jmp _sx
_s01:   mov ch, $01
_sx:    test byte [SC], 2
        jz .done
        xor byte [rbp-1], ch
.done:  ret

;; =====================================================================
;; Inline code generators (ct=2) — SWAPbit-aware
;;
;; Each generator emits machine code at rbp using the "default" register
;; assignment (rbx=TOS, rdx=NOS), then calls s01/s08/s09 to flip the
;; register bits if the SWAPbit is set.
;;
;; The SWAPbit is preserved through all operations except swap itself.
;; Before CALL and RET instructions, _rst syncs the registers by
;; emitting xchg rbx,rdx if needed and clearing the SWAPbit.
;; =====================================================================

;; Helper: emit DROP_NOS with SWAPbit awareness (7 bytes)
;; Default: mov rdx,[r15]; add r15,8   (pop into NOS=rdx)
;; Swapped: mov rbx,[r15]; add r15,8   (pop into NOS=rbx)
_emit_drop_nos_s:
        mov byte [rbp], $49
        mov word [rbp+1], $178B     ; mov rdx, [r15] (default)
        add rbp, 3
        call _s08                   ; swap reg field: rdx↔rbx
        mov dword [rbp], $087F8D4D  ; lea r15, [r15+8] (flags-preserving)
        add rbp, 4
        ret

;; Helper: emit DUP_NOS with SWAPbit awareness (7 bytes)
;; Default: sub r15,8; mov [r15],rdx   (push NOS=rdx)
;; Swapped: sub r15,8; mov [r15],rbx   (push NOS=rbx)
_emit_dup_nos_s:
        mov dword [rbp], $F87F8D4D  ; lea r15, [r15-8] (flags-preserving)
        add rbp, 4
        mov byte [rbp], $49
        mov word [rbp+1], $1789     ; mov [r15], rdx (default)
        add rbp, 3
        jmp _s08                    ; swap reg field: rdx↔rbx

;; dup ( x -- x x ): push NOS, copy TOS to NOS (10 bytes)
;; Default: sub r15,8; mov [r15],rdx; mov rdx,rbx
;; Swapped: sub r15,8; mov [r15],rbx; mov rbx,rdx
_dup_inline:
        call _emit_dup_nos_s
        mov byte [rbp], $48
        mov word [rbp+1], $DA89     ; mov rdx, rbx (default)
        add rbp, 3
        jmp _s09                    ; swap both: rdx↔rbx in both fields

;; drop ( x -- ): move NOS to TOS, pop new NOS (10 bytes)
;; Default: mov rbx,rdx; mov rdx,[r15]; add r15,8
;; Swapped: mov rdx,rbx; mov rbx,[r15]; add r15,8
_drop_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $D389     ; mov rbx, rdx (default)
        add rbp, 3
        call _s09                   ; swap both fields
        jmp _emit_drop_nos_s

;; swap ( a b -- b a ): toggle SWAPbit — ZERO bytes emitted!
;; This is the core of FreeForth's optimization: swap is free.
_swap_inline:
        xor byte [SC], 2           ; toggle SWAPbit
        ret

;; over ( a b -- a b a ): push NOS, swap regs (10 bytes)
;; Default: sub r15,8; mov [r15],rdx; xchg rbx,rdx
;; Swapped: sub r15,8; mov [r15],rbx; xchg rbx,rdx
;; Note: xchg is always the same — it swaps both registers regardless.
_over_inline:
        call _emit_dup_nos_s
        mov byte [rbp], $48         ; xchg rbx, rdx (always same)
        mov word [rbp+1], $DA87
        add rbp, 3
        ret

;; nip ( a b -- b ): pop NOS, keep TOS (7 bytes)
;; Default: mov rdx,[r15]; add r15,8
;; Swapped: mov rbx,[r15]; add r15,8
_nip_inline:
        jmp _emit_drop_nos_s

;; + ( a b -- a+b ): add NOS to TOS, pop (10 bytes)
;; Default: add rbx,rdx; mov rdx,[r15]; add r15,8
;; Swapped: add rdx,rbx; mov rbx,[r15]; add r15,8
_add_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $D301     ; add rbx, rdx (default)
        add rbp, 3
        call _s09                   ; swap both fields
        jmp _emit_drop_nos_s

;; - ( a b -- a-b ): subtract TOS from NOS (13 bytes)
;; Default: sub rdx,rbx; mov rbx,rdx; DROP_NOS
;; Swapped: sub rbx,rdx; mov rdx,rbx; DROP_NOS_S
_sub_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $DA29     ; sub rdx, rbx (default)
        add rbp, 3
        call _s09
        mov byte [rbp], $48
        mov word [rbp+1], $D389     ; mov rbx, rdx (default)
        add rbp, 3
        call _s09
        jmp _emit_drop_nos_s

;; * ( a b -- a*b ): multiply TOS by NOS (11 bytes)
;; Default: imul rbx,rdx; mov rdx,[r15]; add r15,8
;; Swapped: imul rdx,rbx; mov rbx,[r15]; add r15,8
_mul_inline:
        mov dword [rbp], $DAAF0F48  ; imul rbx, rdx (default)
        add rbp, 4
        call _s09                   ; swap both fields
        jmp _emit_drop_nos_s

;; negate ( n -- -n ): two's complement negation (3 bytes)
;; Default: neg rbx (48 F7 DB)
;; Swapped: neg rdx (48 F7 DA) — XOR $01 on ModR/M
_negate_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $DBF7     ; neg rbx (default)
        add rbp, 3
        jmp _s01                    ; swap r/m field only

;; not ( a -- ~a ): bitwise complement (3 bytes)
;; Default: not rbx (48 F7 D3)
;; Swapped: not rdx (48 F7 D2) — XOR $01 on ModR/M
_not_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $D3F7     ; not rbx (default)
        add rbp, 3
        jmp _s01                    ; swap r/m field only

;; and ( a b -- a&b ): bitwise AND, pop (10 bytes)
;; Default: and rbx,rdx (48 21 D3); DROP_NOS
;; Swapped: and rdx,rbx (48 21 DA); DROP_NOS_S
_and_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $D321     ; and rbx, rdx
        add rbp, 3
        call _s09
        jmp _emit_drop_nos_s

;; or ( a b -- a|b ): bitwise OR, pop (10 bytes)
;; Default: or rbx,rdx (48 09 D3); DROP_NOS
_or_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $D309     ; or rbx, rdx
        add rbp, 3
        call _s09
        jmp _emit_drop_nos_s

;; xor ( a b -- a^b ): bitwise XOR, pop (10 bytes)
;; Default: xor rbx,rdx (48 31 D3); DROP_NOS
_xor_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $D331     ; xor rbx, rdx
        add rbp, 3
        call _s09
        jmp _emit_drop_nos_s

;; @ ( addr -- val ): fetch 64-bit value from memory (3 bytes)
;; Default: mov rbx,[rbx] (48 8B 1B)
;; Swapped: mov rdx,[rdx] (48 8B 12) — XOR $09 on ModR/M
_fetch_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $1B8B     ; mov rbx, [rbx]
        add rbp, 3
        jmp _s09

;; c@ ( addr -- char ): fetch byte, zero-extend (3 bytes)
;; Default: movzx ebx,byte [rbx] (0F B6 1B)
;; Swapped: movzx edx,byte [rdx] (0F B6 12) — XOR $09
;; Note: no REX prefix needed — 32-bit result zero-extends to 64-bit
_cfetch_inline:
        mov byte [rbp], $0F
        mov word [rbp+1], $1BB6     ; movzx ebx, byte [rbx]
        add rbp, 3
        jmp _s09

;; rot ( a b c -- b c a ): rotate third to top (6 bytes)
;; Default: xchg rdx,[r15] (49 87 17); xchg rbx,rdx (48 87 DA)
;; Swapped: xchg rbx,[r15] (49 87 1F); xchg rbx,rdx (48 87 DA)
;; Note: second xchg is always the same (symmetric operation).
_rot_inline:
        mov byte [rbp], $49
        mov word [rbp+1], $1787     ; xchg rdx, [r15]
        add rbp, 3
        call _s08                   ; swap reg field: rdx↔rbx
        mov byte [rbp], $48
        mov word [rbp+1], $DA87     ; xchg rbx, rdx (always same)
        add rbp, 3
        ret

;; tuck ( a b -- b a b ): push TOS under NOS (7 bytes)
;; Default: sub r15,8 (49 83 EF 08); mov [r15],rbx (49 89 1F)
;; Swapped: sub r15,8; mov [r15],rdx (49 89 17) — XOR $08
_tuck_inline:
        mov dword [rbp], $F87F8D4D  ; lea r15, [r15-8] (flags-preserving)
        add rbp, 4
        mov byte [rbp], $49
        mov word [rbp+1], $1F89     ; mov [r15], rbx (default)
        add rbp, 3
        jmp _s08                    ; swap reg field: rbx↔rdx

;; =====================================================================
;; FLAGS-BASED CONDITIONALS (FreeForth approach)
;;
;; Comparison words set CPU FLAGS and store a conditional jump opcode
;; in cond_jmp. IF/UNTIL/WHILE read it and emit the conditional jump.
;; =====================================================================

;; 0- ( -- ): emit test TOS,TOS to set FLAGS without modifying stack
_0minus_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $DB85     ; test rbx, rbx
        add rbp, 3
        jmp _s09

;; Binary flags-based comparisons: emit cmp NOS,TOS and store condition.
_lt_flags:
        mov byte [cond_jmp], $7C
        jmp _emit_cmp_s
_gt_flags:
        mov byte [cond_jmp], $7F
        jmp _emit_cmp_s
_eq_flags:
        mov byte [cond_jmp], $74
        jmp _emit_cmp_s
_neq_flags:
        mov byte [cond_jmp], $75
        jmp _emit_cmp_s
_le_flags:
        mov byte [cond_jmp], $7E
        jmp _emit_cmp_s
_ge_flags:
        mov byte [cond_jmp], $7D
        jmp _emit_cmp_s

;; Shared: emit cmp rdx, rbx (48 39 DA) with SWAPbit
_emit_cmp_s:
        mov byte [rbp], $48
        mov word [rbp+1], $DA39
        add rbp, 3
        jmp _s09

;; Unary flags-based conditions: store condition in cond_jmp.
_zeq_flags:
        mov byte [cond_jmp], $74
        ret
_zneq_flags:
        mov byte [cond_jmp], $75
        ret
_zlt_flags:
        mov byte [cond_jmp], $7C
        ret
_zgt_flags:
        mov byte [cond_jmp], $7F
        ret
_zle_flags:
        mov byte [cond_jmp], $7E
        ret
_zge_flags:
        mov byte [cond_jmp], $7D
        ret

;; =====================================================================
;; DOTTED COMPARISONS: produce boolean values on the stack
;; =====================================================================

;; =. ( a b -- flag )
_eq_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $DA39
        add rbp, 3
        call _s09
        mov byte [rbp], $0F
        mov word [rbp+1], $C194
        add rbp, 3
        mov byte [rbp], $0F
        mov word [rbp+1], $D9B6
        add rbp, 3
        call _s01
        mov byte [rbp], $48
        mov word [rbp+1], $DBF7
        add rbp, 3
        call _s01
        jmp _emit_drop_nos_s

;; <. ( a b -- flag )
_lt_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $DA39
        add rbp, 3
        call _s09
        mov byte [rbp], $0F
        mov word [rbp+1], $C19C
        add rbp, 3
        mov byte [rbp], $0F
        mov word [rbp+1], $D9B6
        add rbp, 3
        call _s01
        mov byte [rbp], $48
        mov word [rbp+1], $DBF7
        add rbp, 3
        call _s01
        jmp _emit_drop_nos_s

;; >. ( a b -- flag )
_gt_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $DA39
        add rbp, 3
        call _s09
        mov byte [rbp], $0F
        mov word [rbp+1], $C19F
        add rbp, 3
        mov byte [rbp], $0F
        mov word [rbp+1], $D9B6
        add rbp, 3
        call _s01
        mov byte [rbp], $48
        mov word [rbp+1], $DBF7
        add rbp, 3
        call _s01
        jmp _emit_drop_nos_s

;; 0=. ( n -- flag )
_zeq_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $DB85
        add rbp, 3
        call _s09
        mov byte [rbp], $0F
        mov word [rbp+1], $C194
        add rbp, 3
        mov byte [rbp], $0F
        mov word [rbp+1], $D9B6
        add rbp, 3
        call _s01
        mov byte [rbp], $48
        mov word [rbp+1], $DBF7
        add rbp, 3
        jmp _s01

;; 0<>. ( n -- flag )
_zneq_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $DB85
        add rbp, 3
        call _s09
        mov byte [rbp], $0F
        mov word [rbp+1], $C195
        add rbp, 3
        mov byte [rbp], $0F
        mov word [rbp+1], $D9B6
        add rbp, 3
        call _s01
        mov byte [rbp], $48
        mov word [rbp+1], $DBF7
        add rbp, 3
        jmp _s01

;; 0<. ( n -- flag ): boolean sign test
_zlt_inline:
        mov byte [rbp], $48
        mov word [rbp+1], $FBC1
        add rbp, 3
        call _s01
        mov byte [rbp], $3F
        inc rbp
        ret

;; Compile-time words (ct=2): executed during compilation
;; These use the data stack (rbx/rdx/r15) to track patch addresses.
;; rbp = compilation pointer.
;; =====================================================================

;; IF: use FLAGS set by preceding comparison/test.
;; If cond_jmp is set: emit conditional jump using stored condition.
;; If cond_jmp is 0: fallback to test TOS + DROP1 + jz (backward compat).
_if:
        call _rst
        movzx eax, byte [cond_jmp]
        mov byte [cond_jmp], 0
        test al, al
        jz .fallback
        ;; FLAGS-based: invert condition, emit long conditional jump
        xor al, 1
        mov byte [rbp], $0F
        add al, $10
        mov byte [rbp+1], al
        add rbp, 2
        jmp .push_patch
.fallback:
        ;; Boolean fallback: test rbx, rbx + DROP1 + jz
        mov byte [rbp], $48
        mov word [rbp+1], $DB85
        add rbp, 3
        mov byte [rbp], $48
        mov word [rbp+1], $D389
        add rbp, 3
        mov byte [rbp], $49
        mov word [rbp+1], $178B
        add rbp, 3
        mov dword [rbp], $087F8D4D
        add rbp, 4
        mov byte [rbp], $0F
        mov byte [rbp+1], $84
        add rbp, 2
.push_patch:
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, rbp
        add rbp, 4
        ret

;; THEN: resolve forward jump. TOS = patch address.
;; Calls _rst to reconcile SWAPbit at join point.
_then:
        call _rst
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
        call _rst
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
        call _rst
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, rbp            ; TOS = current compilation pointer
        ret

;; AGAIN: compile unconditional jump back to BEGIN address
_again:
        call _rst
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

;; UNTIL: use FLAGS to loop. Same dual-path as IF but backward jump.
_until:
        call _rst
        movzx eax, byte [cond_jmp]
        mov byte [cond_jmp], 0
        test al, al
        jz .fallback
        ;; FLAGS-based: invert condition, emit long conditional backward jump
        xor al, 1
        mov byte [rbp], $0F
        add al, $10
        mov byte [rbp+1], al
        add rbp, 2
        jmp .calc_offset
.fallback:
        ;; Boolean fallback: test + DROP1 + jz
        mov byte [rbp], $48
        mov word [rbp+1], $DB85
        add rbp, 3
        mov byte [rbp], $48
        mov word [rbp+1], $D389
        add rbp, 3
        mov byte [rbp], $49
        mov word [rbp+1], $178B
        add rbp, 3
        mov dword [rbp], $087F8D4D
        add rbp, 4
        mov byte [rbp], $0F
        mov byte [rbp+1], $84
        add rbp, 2
.calc_offset:
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
        call _rst
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

;; ( -- skip input until matching )
_paren:
        mov rdi, [tin]
        mov rsi, [tp]
.scan:  cmp rdi, rsi
        jae .done
        cmp byte [rdi], ')'
        je .found
        inc rdi
        jmp .scan
.found: inc rdi                 ; skip past )
.done:  mov [tin], rdi
        ret

;; \ -- skip rest of line
_backslash:
        mov rdi, [tp]           ; set input pointer to end of buffer
        mov [tin], rdi
        ret

;; Runtime helper: print inline string after call instruction
;; Called via: call _dotstr_rt / db len / db "string..."
;; Return address on stack points to the length byte
_dotstr_rt:
        pop rsi                 ; rsi = address of length byte
        movzx rdx, byte [rsi]  ; rdx = string length
        inc rsi                 ; rsi = string data
        push rax
        push rdi
        push rcx
        push r11
        mov rax, 1              ; sys_write
        mov rdi, 1              ; stdout
        syscall
        pop r11
        pop rcx
        pop rdi
        pop rax
        add rsi, rdx            ; skip past string data
        jmp rsi                 ; "return" to after the string

;; ." compile-time word: scan until " and compile inline string print
_dotquote:
        ;; Compile: call _dotstr_rt
        mov byte [rbp], $E8
        inc rbp
        lea rax, [_dotstr_rt]
        lea rcx, [rbp + 4]
        sub rax, rcx
        mov dword [rbp], eax
        add rbp, 4
        ;; Scan input for closing "
        mov rdi, [tin]
        mov rsi, [tp]
        ;; Skip leading space after ."
        cmp rdi, rsi
        jae .nostr
        cmp byte [rdi], ' '
        jne .start
        inc rdi
.start: mov rax, rdi            ; rax = start of string
.scan:  cmp rdi, rsi
        jae .noclose
        cmp byte [rdi], '"'
        je .found
        inc rdi
        jmp .scan
.found: mov rcx, rdi
        sub rcx, rax            ; rcx = string length
        inc rdi                 ; skip past "
        mov [tin], rdi
        ;; Compile: db length, db string...
        mov byte [rbp], cl
        inc rbp
        ;; Copy string bytes
        mov rsi, rax
        mov rdi, rbp
        push rcx
        rep movsb
        pop rcx
        add rbp, rcx
        ret
.noclose:
.nostr: mov [tin], rdi
        mov byte [rbp], 0      ; empty string
        inc rbp
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
        call _rst               ; sync registers before call
        mov byte [rbp], $E8
        lea rcx, [rbp+5]
        sub eax, ecx
        mov dword [rbp+1], eax
        add rbp, 5
        ret

_lit_compile:
        ;; DUP1 inline: lea r15,[r15-8]; mov [r15],rdx; mov rdx,rbx
        call _rst               ; sync before literal
        mov dword [rbp], $F87F8D4D  ; lea r15, [r15-8] (flags-preserving)
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
        call _rst               ; sync registers before ret
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

;; variable: parse name, allocate 8-byte cell, create literal header
;; Usage: variable x    → x pushes address of its cell
_variable:
        call _wsparse
        test ecx, ecx
        jz _colon.missing_name
        ;; rax=name addr, ecx=name len
        ;; xt = rbp (current compilation pointer = address of data cell)
        mov r8, rbp             ; xt = address of the cell
        mov r9d, 1              ; ct=1 (literal → push xt as literal)
        call _header
        mov qword [rbp], 0      ; initialize cell to 0
        add rbp, 8              ; advance past the cell
        mov [anon], rbp          ; update anon so code doesn't get recycled
        ret

;; constant: parse name, TOS is the value, create literal header
;; Usage: 42 constant answer    → answer pushes 42
_constant:
        call _wsparse
        test ecx, ecx
        jz _colon.missing_name
        ;; rax=name addr, ecx=name len
        ;; xt = rbx (TOS = the constant value)
        mov r8, rbx             ; xt = constant value
        mov r9d, 1              ; ct=1 (literal → push xt as literal)
        call _header
        ;; Drop the constant value from data stack
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        mov [anon], rbp
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
        ;; Check for "variable"
        cmp ecx, 8
        jne .notvar
        push rdi
        push rsi
        mov rdi, rax
        lea rsi, [kw_variable]
        push rcx
        repz cmpsb
        pop rcx
        pop rsi
        pop rdi
        jnz .notvar
        call _variable
        jmp _compiler
.notvar:
        ;; Check for "constant"
        cmp ecx, 8
        jne .notconst
        push rdi
        push rsi
        mov rdi, rax
        lea rsi, [kw_constant]
        push rcx
        repz cmpsb
        pop rcx
        pop rsi
        pop rdi
        jnz .notconst
        ;; Execute accumulated code to get value on stack
        call _semi_exec
        call _constant
        jmp _compiler
.notconst:
        ;; Check for "include"
        cmp ecx, 7
        jne .notincl
        push rdi
        push rsi
        mov rdi, rax
        lea rsi, [kw_include]
        push rcx
        repz cmpsb
        pop rcx
        pop rsi
        pop rdi
        jnz .notincl
        call _include
        jmp _compiler
.notincl:
        push rax
        push rcx
        call _find
        jc .notfound
        ;; Found: rax=xt, ecx=ct
        add rsp, 16
        test ecx, ecx
        jz .compilecall
        cmp ecx, 1
        je .compilelit
        ;; ct >= 2: compile-time word → execute immediately
        call rax
        jmp _compiler
.compilecall:
        call _call_compile
        jmp _compiler
.compilelit:
        ;; ct=1: literal word → push xt value as literal
        mov rbx, rax
        call _lit_compile
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

;; include: parse filename, open file, read contents, compile, close
;; Saves and restores input state (tin, tp)
_include:
        ;; Parse filename from input
        call _wsparse
        test ecx, ecx
        jz .err_nofile
        ;; NUL-terminate the filename (wsparse leaves rax=start, ecx=len)
        mov byte [rax + rcx], 0
        ;; Save current input state and filebuf position
        push qword [tin]
        push qword [tp]
        push qword [filebuf_ptr]
        ;; Open file (sys_open=2, O_RDONLY=0)
        mov rdi, rax            ; filename
        xor esi, esi            ; O_RDONLY
        xor edx, edx            ; mode (ignored for read)
        mov rax, 2              ; sys_open
        syscall
        test rax, rax
        js .err_open
        mov r12, rax            ; save fd in r12
        ;; Read file into current filebuf position (sys_read=0)
        xor eax, eax            ; sys_read
        mov rdi, r12            ; fd
        mov rsi, [filebuf_ptr]  ; buffer at current nesting level
        mov rdx, 16384          ; max 16KB per file
        syscall
        test rax, rax
        js .err_read
        ;; Close file (sys_close=3)
        push rax                ; save bytes read
        mov rax, 3              ; sys_close
        mov rdi, r12
        syscall
        pop rax
        ;; Set up input from file buffer, advance filebuf_ptr
        mov rcx, [filebuf_ptr]
        mov [tin], rcx
        lea rcx, [rcx + rax]
        mov [tp], rcx
        lea rcx, [rcx + 16]    ; small gap between levels
        mov [filebuf_ptr], rcx
        ;; Compile the file contents
        call _compiler
        ;; Restore input state and filebuf position
        pop qword [filebuf_ptr]
        pop qword [tp]
        pop qword [tin]
        ret
.err_nofile:
        push rax
        mov rax, 1
        mov rdi, 1
        lea rsi, [err_nofile_msg]
        mov rdx, err_nofile_len
        syscall
        pop rax
        ret
.err_open:
        push rax
        mov rax, 1
        mov rdi, 1
        lea rsi, [err_open_msg]
        mov rdx, err_open_len
        syscall
        pop rax
        ;; Restore input state
        pop qword [filebuf_ptr]
        pop qword [tp]
        pop qword [tin]
        ret
.err_read:
        mov rax, 3              ; close fd
        mov rdi, r12
        syscall
        mov rax, 1
        mov rdi, 1
        lea rsi, [err_read_msg]
        mov rdx, err_read_len
        syscall
        pop qword [filebuf_ptr]
        pop qword [tp]
        pop qword [tin]
        ret

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

;; Inline code generators (ct=2) — emit machine code directly
WORD64 "over", _over_inline, 2, 4
WORD64 "swap", _swap_inline, 2, 4
WORD64 "drop", _drop_inline, 2, 4
WORD64 "dup", _dup_inline, 2, 3
WORD64 "negate", _negate_inline, 2, 6
WORD64 "not", _not_inline, 2, 3
WORD64 "nip", _nip_inline, 2, 3
WORD64 "*", _mul_inline, 2, 1
WORD64 "-", _sub_inline, 2, 1
WORD64 "+", _add_inline, 2, 1
WORD64 "and", _and_inline, 2, 3
WORD64 "or", _or_inline, 2, 2
WORD64 "xor", _xor_inline, 2, 3
WORD64 "@", _fetch_inline, 2, 1
WORD64 "c@", _cfetch_inline, 2, 2
WORD64 "rot", _rot_inline, 2, 3
WORD64 "tuck", _tuck_inline, 2, 4

;; FLAGS-based comparison words (ct=2)
WORD64 "0-", _0minus_inline, 2, 2
WORD64 "0>=", _zge_flags, 2, 3
WORD64 "0<=", _zle_flags, 2, 3
WORD64 "0>", _zgt_flags, 2, 2
WORD64 "0<", _zlt_flags, 2, 2
WORD64 "0<>", _zneq_flags, 2, 3
WORD64 "0=", _zeq_flags, 2, 2
WORD64 ">=", _ge_flags, 2, 2
WORD64 "<=", _le_flags, 2, 2
WORD64 "<>", _neq_flags, 2, 2
WORD64 ">", _gt_flags, 2, 1
WORD64 "<", _lt_flags, 2, 1
WORD64 "=", _eq_flags, 2, 1

;; DOTTED comparisons (ct=2): produce boolean values on stack
WORD64 "0<>.", _zneq_inline, 2, 4
WORD64 "0=.", _zeq_inline, 2, 3
WORD64 "0<.", _zlt_inline, 2, 3
WORD64 ">.", _gt_inline, 2, 2
WORD64 "<.", _lt_inline, 2, 2
WORD64 "=.", _eq_inline, 2, 2

;; Runtime words (ct=0) — still called via compiled CALL instruction
WORD64 "cr", _cr, 0, 2
WORD64 "2", _two, 0, 1
WORD64 "1", _one, 0, 1
WORD64 ".", _dot, 0, 1
WORD64 "rshift", _rshift, 0, 6
WORD64 "lshift", _lshift, 0, 6
WORD64 "c,", _ccomma, 0, 2
WORD64 ",", _comma, 0, 1
WORD64 "allot", _allot, 0, 5
WORD64 "here", _here, 0, 4
WORD64 "depth", _depth, 0, 5
WORD64 "/mod", _divmod, 0, 4
WORD64 "mod", _mod, 0, 3
WORD64 "/", _div, 0, 1
WORD64 "+!", _addstore, 0, 2
WORD64 "c!", _cstore, 0, 2
WORD64 "!", _store, 0, 1
WORD64 "emit", _emit, 0, 4
WORD64 "erase", _erase, 0, 5
WORD64 "fill", _fill, 0, 4
WORD64 "cmove", _cmove, 0, 5
WORD64 "zlen", _zlen, 0, 4
WORD64 "r@", _rfetch, 0, 2
WORD64 "r>", _rfrom, 0, 2
WORD64 ">r", _tor, 0, 2

;; Compile-time words (ct=1)
WORD64 "REPEAT", _repeat, 2, 6
WORD64 "WHILE", _while, 2, 5
WORD64 "UNTIL", _until, 2, 5
WORD64 "AGAIN", _again, 2, 5
WORD64 "BEGIN", _begin, 2, 5
WORD64 "ELSE", _else, 2, 4
WORD64 "THEN", _then, 2, 4
WORD64 "IF", _if, 2, 2
WORD64 "\", _backslash, 2, 1
WORD64 "(", _paren, 2, 1
WORD64 '."', _dotquote, 2, 2

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

        lea rax, [filebuf]
        mov [filebuf_ptr], rax

        ;; Process command-line arguments: -f <file> loads file
        mov r13, [rsp]          ; argc
        lea r14, [rsp+8]        ; argv[0]
        mov r12, 1              ; current arg index (skip argv[0])
.argloop:
        cmp r12, r13
        jge .repl
        mov rdi, [r14 + r12*8]
        cmp word [rdi], $662D   ; "-f" (little-endian)
        jne .nextarg
        cmp byte [rdi+2], 0
        jne .nextarg
        inc r12
        cmp r12, r13
        jge .repl
        mov rdi, [r14 + r12*8]  ; filename
        push r12
        push r13
        push r14
        push qword [tin]
        push qword [tp]
        push qword [filebuf_ptr]
        xor esi, esi
        xor edx, edx
        mov rax, 2              ; sys_open
        syscall
        test rax, rax
        js .argfile_err
        mov r12, rax
        xor eax, eax            ; sys_read
        mov rdi, r12
        mov rsi, [filebuf_ptr]
        mov rdx, 16384
        syscall
        push rax
        mov rax, 3              ; sys_close
        mov rdi, r12
        syscall
        pop rax
        test rax, rax
        jle .argfile_done
        mov rcx, [filebuf_ptr]
        mov [tin], rcx
        lea rcx, [rcx + rax]
        mov [tp], rcx
        lea rcx, [rcx + 16]
        mov [filebuf_ptr], rcx
        call _compiler
.argfile_done:
        pop qword [filebuf_ptr]
        pop qword [tp]
        pop qword [tin]
        pop r14
        pop r13
        pop r12
.nextarg:
        inc r12
        jmp .argloop
.argfile_err:
        push rax
        mov rax, 1
        mov rdi, 1
        lea rsi, [err_open_msg]
        mov rdx, err_open_len
        syscall
        pop rax
        jmp .argfile_done

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
kw_variable:  db "variable"
kw_constant:  db "constant"
kw_include:   db "include"
err_nofile_msg: db "error: include without filename", 10
err_nofile_len = $ - err_nofile_msg
err_open_msg: db "error: cannot open file", 10
err_open_len = $ - err_open_msg
err_read_msg: db "error: cannot read file", 10
err_read_len = $ - err_read_msg
minus_char    db '-'
nl_char       db 10
numbuf        rb 21

        align 8
headbuf    rb 65536
heads64:   GENWORDS64

inbuf      rb 4096
filebuf    rb 65536
dstack     rb 8192
dstack_top:
codebuf    rb 65536
