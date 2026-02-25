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
callmark dq 0
tin     dq 0
tp      dq 0
filebuf_ptr dq 0
xfp     dq 0                    ; exception frame pointer for catch/throw
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

_dfetch: movsxd rbx, dword [rbx] ; d@ ( addr -- sval ) sign-extended 32-bit fetch
        ret

_dstore: mov [rbx], edx         ; d! ( val addr -- ) store 32-bit dword
        mov rbx, [r15]
        mov rdx, [r15+8]
        add r15, 16
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
        dec rbx                 ; don't count the item depth itself pushed
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

_wcomma: mov [rbp], bx          ; w, ( w -- ) compile 16-bit word
        add rbp, 2
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        ret

;; Internal state accessors — push addresses of compiler variables
_H_addr:                        ; H ( -- addr ) header pointer variable
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        lea rbx, [H]
        ret

_anon_addr:                     ; anon ( -- addr ) anonymous def start
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        lea rbx, [anon]
        ret

_callmark_addr:                 ; callmark ( -- addr ) last compiled call position
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        lea rbx, [callmark]
        ret

_call_comma:                    ; call, ( xt -- ) compile call to xt, reset SWAPbit
        mov rax, rbx
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        jmp _call_compile

_dcall_comma:                   ; dcall, ( xt -- ) compile call to xt, no reset
        mov rax, rbx
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8
        jmp _call_compile.no_rst

_SC_addr:                       ; SC ( -- addr ) SWAPbit/condition state
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        lea rbx, [SC]
        ret

_cond_addr:                     ; ? ( -- addr ) condition jump opcode byte
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        lea rbx, [cond_jmp]
        ret

_anon_colon:                    ; anon:` ( -- ) start new anonymous definition
        mov [anon], rbp
        mov qword [callmark], 0
        mov byte [SC], 0
        ret

;; Compile-time stack push/pop — separate from data stack
;; Used by START/END/BREAK for flow control address management
_cs_push:                       ; >cs ( x -- ) push TOS to compile-time stack
        mov rax, [csp]
        sub rax, 8
        mov [rax], rbx
        mov [csp], rax
        mov rbx, rdx            ; DROP1
        mov rdx, [r15]
        add r15, 8
        ret

_cs_pop:                        ; cs> ( -- x ) pop from compile-time stack to TOS
        sub r15, 8              ; DUP1
        mov [r15], rdx
        mov rdx, rbx
        mov rax, [csp]
        mov rbx, [rax]
        add rax, 8
        mov [csp], rax
        ret

_dcomma: mov [rbp], ebx         ; d, ( x -- ) compile 32-bit dword
        add rbp, 4
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
;; Callable SWAPbit helpers and litcomma — for Forth-defined macros
;; =====================================================================

;; litcomma: emit a mov [rbp],imm of appropriate size.
;; Called with the value in rax. Writes bytes at [rbp] but does NOT
;; advance the compilation pointer — that's done by s01/s08/s09/,1 etc.
_litcomma:
        cmp rax, $FF
        ja .word
        ;; Byte: C6 45 00 xx (4 bytes)
        mov dword [rbp], $000045C6
        mov byte [rbp+3], al
        add rbp, 4
        ret
.word:  cmp rax, $FFFF
        ja .dword
        ;; Word: 66 C7 45 00 xx xx (6 bytes)
        mov dword [rbp], $0045C766
        mov word [rbp+4], ax
        add rbp, 6
        ret
.dword:
        ;; DWord: C7 45 00 xx xx xx xx (7 bytes)
        mov word [rbp], $45C7
        mov byte [rbp+2], 0
        mov dword [rbp+3], eax
        add rbp, 7
        ret

;; Callable wrappers for s01/s08/s09 — advance rbp by 2 + SWAPbit XOR
_s1_word:
        inc rbp
        jmp _s01_check
_s01_word:
        add rbp, 2
_s01_check:
        test byte [SC], 2
        jz .done
        xor byte [rbp-1], 1
.done:  ret

_s08_word:
        add rbp, 2
        test byte [SC], 2
        jz .done
        xor byte [rbp-1], 8
.done:  ret

_s09_word:
        add rbp, 2
        test byte [SC], 2
        jz .done
        xor byte [rbp-1], 9
.done:  ret

;; ,1-,4: advance compilation pointer by N bytes (no SWAPbit action)
_comma1: inc rbp
        ret
_comma2: add rbp, 2
        ret
_comma3: add rbp, 3
        ret
_comma4: add rbp, 4
        ret

;; lit` — compile n as a literal ( n -- ; -- n )
;; Takes value from TOS at compile time, emits code that pushes it at runtime.
;; Step 1: emit under code (push NOS) + toggle SWAPbit
;; Step 2: emit mov/push+pop depending on value size
;; Step 3: drop n from compile-time stack
_lit:
        ;; Step 1: emit under code (7 bytes) + toggle SWAPbit
        call _emit_dup_nos_s        ; lea r15,[r15-8]; mov [r15],rdx/rbx
        xor byte [SC], 2            ; toggle SWAPbit (swap`)
        ;; Step 2: check value size and emit appropriate code
        ;; Use r8 for value — rcx is clobbered by _s01/_s08 (ch register)
        mov r8, rbx                 ; save full 64-bit value
        movsx rax, bl               ; sign-extend low byte
        cmp rax, r8                 ; fits in signed byte (-128..127)?
        jne .long
        ;; Byte path: push imm8; pop rbx = 6A xx 5B (3 bytes)
        mov dword [rbp], $005B006A  ; 6A 00 5B 00
        mov byte [rbp+1], r8b       ; actual byte value
        inc rbp                     ; rbp past 6A
        add rbp, 2                  ; rbp past imm8 + pop
        call _s01                   ; SWAPbit on pop: 5B↔5A
        jmp _drop                   ; drop n
.long:
        mov eax, r8d                ; zero-extend to 32-bit
        cmp rax, r8                 ; same as 64-bit? (positive, fits in 32 bits)
        jne .big
        ;; 32-bit path: mov ebx, imm32 = BB imm32 (5 bytes, zero-extends to rbx)
        mov byte [rbp], $BB
        inc rbp
        call _s01                   ; SWAPbit on BB: BB↔BA
        mov dword [rbp], r8d        ; 32-bit immediate
        add rbp, 4
        jmp _drop
.big:
        ;; 64-bit path: 48 BB imm64 (10 bytes)
        mov byte [rbp], $48         ; REX.W
        mov byte [rbp+1], $BB
        add rbp, 2
        call _s01                   ; SWAPbit on BB: BB↔BA
        mov qword [rbp], r8         ; 64-bit immediate
        add rbp, 8
        jmp _drop

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

;; Unsigned binary comparisons (JB=$72, JAE=$73, JBE=$76, JA=$77)
_ult_flags:
        mov byte [cond_jmp], $72
        jmp _emit_cmp_s
_ugt_flags:
        mov byte [cond_jmp], $77
        jmp _emit_cmp_s
_ule_flags:
        mov byte [cond_jmp], $76
        jmp _emit_cmp_s
_uge_flags:
        mov byte [cond_jmp], $73
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

;; Compile-time words (ct=2): executed during compilation
;; Flow control (IF/THEN/ELSE/BEGIN/AGAIN/UNTIL/WHILE/REPEAT)
;; Migrated to ff64.boot — Forth-defined using cond/d!
;; ~140 lines of assembly replaced by ~10 lines of Forth

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
        mov rdi, [tin]
        mov rsi, [tp]
.scan:  cmp rdi, rsi
        jae .done
        cmp byte [rdi], 10      ; newline?
        je .found
        inc rdi
        jmp .scan
.found: inc rdi                 ; skip past the newline
.done:  mov [tin], rdi
        ret

;; parse ( sep -- @ # ) — scan for delimiter, return start and length
_parse:
        movzx eax, bl           ; al = separator character
        mov rbx, rdx
        mov rdx, [r15]
        add r15, 8              ; drop separator from data stack
        mov rdi, [tin]
        mov rsi, [tp]
        ;; skip leading separators
.skip:  cmp rdi, rsi
        jae .eof
        cmp byte [rdi], al
        jne .start
        inc rdi
        jmp .skip
.start: sub r15, 8
        mov [r15], rdx
        mov rdx, rdi            ; rdx = start of parsed string
.scan:  cmp rdi, rsi
        jae .end
        cmp byte [rdi], al
        je .end
        inc rdi
        jmp .scan
.end:   mov [tin], rdi
        cmp rdi, rsi
        jae .noskip
        inc qword [tin]         ; skip past the separator
.noskip:
        mov rbx, rdi
        sub rbx, rdx            ; rbx = length
        ret
.eof:   mov [tin], rdi
        sub r15, 8
        mov [r15], rdx
        mov rdx, rdi            ; rdx = start (= end)
        xor ebx, ebx            ; rbx = 0 length
        ret

;; lnparse ( -- @ # ) — parse to end of line (LF=10)
_lnparse:
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, 10             ; LF separator
        jmp _parse

;; wsparse ( -- @ # ) — skip whitespace, parse next word
_wsparse_forth:
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        call _wsparse
        sub r15, 8
        mov [r15], rdx
        mov rdx, rax            ; rdx = word address
        mov rbx, rcx            ; rbx = word length
        ret

;; header ( @ # xt ct -- ) — create a new dictionary header
_header_forth:
        mov r9, rbx             ; r9 = ct
        mov r8, rdx             ; r8 = xt
        mov rcx, [r15]          ; rcx = name length
        mov rax, [r15+8]        ; rax = name address
        mov rdx, [r15+16]
        mov rbx, [r15+24]
        add r15, 32
        jmp _header

;; exit ( n -- ) — exit process with status code n
_exit_word:
        mov rdi, rbx            ; exit code in rdi
        mov rax, 60             ; sys_exit
        syscall

;; Runtime helper: print inline string after call instruction
;; Called via: call _dotstr_rt / db len / db "string..."
;; Return address on stack points to the length byte
_dotstr_rt:
        pop rsi                 ; rsi = address of length byte
        push rdx                ; save NOS (rdx is clobbered by syscall)
        push rbx                ; save TOS
        movzx rdx, byte [rsi]  ; rdx = string length
        inc rsi                 ; rsi = string data
        push rsi                ; save string start
        push rdx                ; save string length
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
        pop rdx                 ; restore string length
        pop rsi                 ; restore string start
        add rsi, rdx            ; skip past string data
        pop rbx                 ; restore TOS
        pop rdx                 ; restore NOS
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
.no_rst:
        mov byte [rbp], $E8
        lea rcx, [rbp+5]
        sub eax, ecx
        mov dword [rbp+1], eax
        add rbp, 5
        mov [callmark], rbp     ; save position AFTER call for -call/;;
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
        ;; Check for empty anonymous def: if [anon] == rbp, nothing was compiled
        ;; since anon:` — just reset and return (like i386's cmp ecx,ebp / jz)
        mov rax, [anon]
        cmp rax, rbp
        je .empty
        ;; Tail-call optimization: if last compiled was a call, change to jmp
        ;; Only for named defs (anon=0); anonymous defs need ret to return
        test rax, rax
        jnz .no_tailcall
        mov rax, [callmark]
        cmp rax, rbp
        jne .no_tailcall
        mov byte [rbp-5], $E9   ; change call ($E8) to jmp ($E9)
        jmp .after_ret
.no_tailcall:
        mov byte [rbp], $C3
        inc rbp
.after_ret:
        mov qword [callmark], 0 ; reset callmark
        mov rax, [anon]
        test rax, rax
        jnz .anonymous
.empty:
        mov [anon], rbp
        mov qword [callmark], 0
        mov byte [SC], 0
        ret
.anonymous:
_semi_exec:
        mov byte [rbp], $C3
        inc rbp
        mov rax, [anon]
        mov rbp, rax            ; reset rbp to anon start (for execution)
        call rax                ; execute anonymous code (may advance rbp via allot)
        ;; After execution, rbp reflects any allot changes.
        ;; Fall through to _anon to set [anon]=rbp, preserving allotted space.
        ;; This matches i386 behavior where _semi falls through to _anon.
        mov [anon], rbp
        mov qword [callmark], 0
        mov byte [SC], 0
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
        jz _compiler_done

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
        ;; --- Backtick name mangling ---
        ;; Temporarily append '`' to the word and search.
        ;; If found, execute immediately (compile-time macro).
        lea rdi, [rax + rcx]   ; point past end of word
        push qword [rdi]       ; save bytes at that position
        push rdi
        mov byte [rdi], '`'    ; append backtick
        inc ecx                ; length + 1
        call _find
        pop rdi
        pop qword [rdi]        ; restore original bytes
        jc .no_backtick
        ;; Found via backtick: execute immediately
        call rax
        jmp _compiler
.no_backtick:
        dec ecx                ; restore original length
        ;; --- Normal lookup (no backtick) ---
        push rax
        push rcx
        call _find
        jc .notfound
        ;; Found: rax=xt, ecx=ct
        add rsp, 16
        and ecx, 7              ; mask to compile class bits (0-2)
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
        ;; Value is in rax (xt); do NOT put in rbx (would corrupt compile-time stack)
        call _lit_compile
        jmp _compiler
.notfound:
        pop rcx
        pop rax
        ;; Check for character literal: 'X' syntax (length=3, quotes)
        cmp ecx, 3
        jne .not_charlit
        cmp byte [rax], $27     ; opening single quote
        jne .not_charlit
        cmp byte [rax+2], $27   ; closing single quote
        jne .not_charlit
        movzx eax, byte [rax+1] ; extract the character
        call _lit_compile
        jmp _compiler
.not_charlit:
        ;; ─── Suffix mechanism ───
        ;; Check if last char is an interpreted suffix: +-*/%&|^,@!_
        cmp ecx, 2              ; need at least 2 chars
        jb .try_number
        movzx edi, byte [rax + rcx - 1]  ; edi = final character
        ;; Search suffix table
        push rcx
        push rax
        lea rsi, [suffix_chars]
        xor r8d, r8d            ; index
.sfx_search:
        movzx r9d, byte [rsi + r8]
        test r9d, r9d
        jz .sfx_notfound
        cmp r9d, edi
        je .sfx_found
        inc r8d
        jmp .sfx_search
.sfx_notfound:
        pop rax
        pop rcx
        jmp .try_number
.sfx_found:
        ;; r8 = index into suffix table. Strip suffix and parse number.
        pop rax
        pop rcx
        dec ecx                 ; strip suffix char
        push r8                 ; save suffix index
        push rcx
        push rax
        ;; First try: look up as a word (for named constants/variables)
        push rdi                ; save suffix char
        call _find_suffix       ; try to find word without suffix
        pop rdi
        jz .sfx_got_value       ; found → rax = xt value
        ;; Second try: parse as number
        pop rax
        pop rcx
        push rcx
        push rax
        call _number
        jnz .sfx_fail
.sfx_got_value:
        ;; rax = value (from number or word lookup)
        add rsp, 16             ; discard saved rax/rcx
        pop r8                  ; suffix index
        ;; Dispatch to suffix handler
        jmp qword [suffix_handlers + r8*8]
.sfx_fail:
        pop rax
        pop rcx
        pop r8                  ; discard suffix index
        inc ecx                 ; restore full length
        jmp .try_number_with


.try_number:
        push rcx
        push rax
.try_number_with:
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
        ;; If a catch frame is active (xfp != 0), throw the error.
        ;; Otherwise, print "error: <word>\n" and continue compiling.
        cmp qword [xfp], 0
        jne .error_throw
        ;; No catch frame: print error inline and continue
        push rcx
        push rax
        mov rax, 1
        mov rdi, 1
        lea rsi, [errmsg]
        mov rdx, 7
        syscall
        pop rsi
        pop rdx
        and rsi, -2             ; clear low bit (wsparse artifact)
        mov rax, 1
        mov rdi, 1
        syscall
        mov rax, 1
        mov rdi, 1
        lea rsi, [nl_char]
        mov rdx, 1
        syscall
        jmp _compiler
.error_throw:
        call _error
        db 3, "???"
_compiler_done:
        ret
        ;; ─── Suffix handlers ───

;; _find_suffix: look up rax/ecx as a word, return xt value if ct=1
;; On entry: rax=string, ecx=length (suffix stripped)
;; Returns: ZF set and rax=value if found (ct=1 data word)
;;          ZF clear if not found
_find_suffix:
        push rbx
        push rdx
        ;; _find expects: rax=string addr, rcx=length
        ;; rax and ecx already set correctly
        call _find
        jc .fs_notfound         ; CF set = not found
        ;; Found: check ct=1 (data/literal)
        and ecx, 7
        cmp ecx, 1
        jne .fs_notfound
        ;; ct=1: rax has xt (the data value)
        pop rdx
        pop rbx
        xor ecx, ecx           ; set ZF
        ret
.fs_notfound:
        pop rdx
        pop rbx
        or ecx, 1              ; clear ZF
        ret

;; lit8_64: check if rax fits in a signed byte
;; Returns: CF set if byte-sized (jbe = byte, ja = long)
_lit8_64:
        push rcx
        mov rcx, rax
        sar rcx, 7             ; shift right 7 bits
        cmp rcx, 0             ; 0 = positive byte, -1 = negative byte
        je .byte
        cmp rcx, -1
        je .byte
        pop rcx
        stc                     ; CF=1 → NOT byte-sized (use "ja" for long)
        ret
.byte:  pop rcx
        clc                     ; CF=0 → byte-sized
        ret

;; litadd — 5+ becomes add rbx,5
;; On entry: rax = value
_litadd:
        call _rst
        call _lit8_64
        jc .long
        ;; Byte: 48 83 C3 xx (4 bytes) — add rbx, imm8
        mov dword [rbp], $C38348
        add rbp, 3              ; advance past opcode for _s01
        call _s01               ; SWAPbit on ModR/M byte [rbp-1]
        mov byte [rbp], al
        add rbp, 1
        jmp _compiler
.long:  ;; Long: 48 81 C3 xx xx xx xx (7 bytes) — add rbx, imm32
        mov dword [rbp], $C38148
        add rbp, 3
        call _s01
        mov dword [rbp], eax
        add rbp, 4
        jmp _compiler

;; litsub — 3- becomes sub rbx,3
_litsub:
        call _rst
        call _lit8_64
        jc .long
        mov dword [rbp], $EB8348      ; sub rbx, imm8
        add rbp, 3
        call _s01
        mov byte [rbp], al
        add rbp, 1
        jmp _compiler
.long:  mov dword [rbp], $EB8148      ; sub rbx, imm32
        add rbp, 3
        call _s01
        mov dword [rbp], eax
        add rbp, 4
        jmp _compiler

;; litand — $FF& becomes and rbx,$FF
_litand:
        call _rst
        call _lit8_64
        jc .long
        mov dword [rbp], $E38348      ; and rbx, imm8
        add rbp, 3
        call _s01
        mov byte [rbp], al
        add rbp, 1
        jmp _compiler
.long:  mov dword [rbp], $E38148      ; and rbx, imm32
        add rbp, 3
        call _s01
        mov dword [rbp], eax
        add rbp, 4
        jmp _compiler

;; litior — $80| becomes or rbx,$80
_litior:
        call _rst
        call _lit8_64
        jc .long
        mov dword [rbp], $CB8348      ; or rbx, imm8
        add rbp, 3
        call _s01
        mov byte [rbp], al
        add rbp, 1
        jmp _compiler
.long:  mov dword [rbp], $CB8148      ; or rbx, imm32
        add rbp, 3
        call _s01
        mov dword [rbp], eax
        add rbp, 4
        jmp _compiler

;; litxor — 1^ becomes xor rbx,1
_litxor:
        call _rst
        call _lit8_64
        jc .long
        mov dword [rbp], $F38348      ; xor rbx, imm8
        add rbp, 3
        call _s01
        mov byte [rbp], al
        add rbp, 1
        jmp _compiler
.long:  mov dword [rbp], $F38148      ; xor rbx, imm32
        add rbp, 3
        call _s01
        mov dword [rbp], eax
        add rbp, 4
        jmp _compiler

;; litmul — 3* becomes imul rbx,rbx,3
_litmul:
        call _rst
        call _lit8_64
        jc .long
        ;; Byte: 48 6B DB xx (4 bytes) — imul rbx, rbx, imm8
        mov dword [rbp], $DB6B48
        add rbp, 3
        call _s09               ; SWAPbit on both fields
        mov byte [rbp], al
        add rbp, 1
        jmp _compiler
.long:  ;; Long: 48 69 DB xx xx xx xx (7 bytes) — imul rbx, rbx, imm32
        mov dword [rbp], $DB6948
        add rbp, 3
        call _s09
        mov dword [rbp], eax
        add rbp, 4
        jmp _compiler

;; litdiv — compile inline signed division by immediate
;; push rdx; mov rax,rbx; cqo; mov rcx,imm32; idiv rcx; mov rbx,rax; pop rdx
_litdiv:
        call _rst
        ;; 52             push rdx
        ;; 48 89 D8       mov rax, rbx
        ;; 48 99          cqo
        mov byte [rbp], $52             ; push rdx
        mov dword [rbp+1], $D88948      ; mov rax, rbx
        mov word [rbp+4], $9948         ; cqo
        ;; 48 C7 C1 imm32 mov rcx, sign-extended imm32
        mov byte [rbp+6], $48
        mov word [rbp+7], $C1C7
        mov dword [rbp+9], eax
        ;; 48 F7 F9       idiv rcx
        ;; 48 89 C3       mov rbx, rax (quotient)
        ;; 5A             pop rdx
        mov byte [rbp+13], $48
        mov word [rbp+14], $F9F7
        mov byte [rbp+16], $48
        mov word [rbp+17], $C389
        mov byte [rbp+19], $5A
        add rbp, 20
        jmp _compiler

;; litmod — like litdiv but keep remainder (rdx) instead of quotient (rax)
_litmod:
        call _rst
        mov byte [rbp], $52             ; push rdx
        mov dword [rbp+1], $D88948      ; mov rax, rbx
        mov word [rbp+4], $9948         ; cqo
        mov byte [rbp+6], $48
        mov word [rbp+7], $C1C7
        mov dword [rbp+9], eax
        mov byte [rbp+13], $48
        mov word [rbp+14], $F9F7
        ;; mov rbx, rdx (remainder instead of quotient)
        mov byte [rbp+16], $48
        mov word [rbp+17], $D389
        mov byte [rbp+19], $5A
        add rbp, 20
        jmp _compiler

;; litfetch — addr@ becomes mov rbx,[addr] via RIP-relative
;; On entry: rax = address to fetch from
_litfetch:
        call _rst
        ;; Emit DUP1 first (push current TOS)
        ;; lea r15,[r15-8]; mov [r15],rdx; mov rdx,rbx
        mov dword [rbp], $F87F8D4D      ; lea r15,[r15-8]
        add rbp, 4
        mov byte [rbp], $49
        mov word [rbp+1], $1789         ; mov [r15], rdx
        add rbp, 3
        mov byte [rbp], $48
        mov word [rbp+1], $DA89         ; mov rdx, rbx
        add rbp, 3
        call _s08                       ; SWAPbit on dup preamble
        ;; Now emit: mov rbx, [rip+disp32]
        ;; 48 8B 1D xx xx xx xx (7 bytes)
        mov byte [rbp], $48
        mov word [rbp+1], $1D8B
        add rbp, 3
        call _s01                       ; SWAPbit on result register
        ;; disp32 = target - (here + 4)  (4 more bytes for disp32)
        lea rcx, [rbp + 4]             ; address after this instruction
        sub rax, rcx                    ; rip-relative displacement
        mov dword [rbp], eax
        add rbp, 4
        jmp _compiler

;; litstore — addr! becomes mov [addr],rbx via RIP-relative, then drop
;; On entry: rax = address to store to
_litstore:
        call _rst
        ;; Emit: mov [rip+disp32], rbx → 48 89 1D xx xx xx xx
        mov byte [rbp], $48
        mov word [rbp+1], $1D89
        add rbp, 3
        call _s01
        ;; disp32 = target - (here + 4)
        lea rcx, [rbp + 4]
        sub rax, rcx
        mov dword [rbp], eax
        add rbp, 4
        ;; Emit inline DROP:
        ;; 48 89 D3       mov rbx, rdx
        ;; 49 8B 17       mov rdx, [r15]
        ;; 4D 8D 7F 08    lea r15, [r15+8]
        mov byte [rbp], $48
        mov word [rbp+1], $D389
        mov byte [rbp+3], $49
        mov word [rbp+4], $178B
        mov dword [rbp+6], $087F8D4D
        add rbp, 10
        jmp _compiler

;; litnip — 42_ replaces TOS without push (like drop + lit)
;; On entry: rax = value
_litnip:
        call _rst
        ;; Just emit mov rbx, imm32/imm64 (no DUP1 preamble)
        mov rcx, rax
        mov eax, eax            ; zero-extend to test if 32-bit
        cmp rax, rcx
        jne .big
        ;; 32-bit: BB xx xx xx xx (5 bytes)
        mov byte [rbp], $BB
        inc rbp
        call _s01               ; SWAPbit on BB byte [rbp-1]
        mov dword [rbp], eax
        add rbp, 4
        jmp _compiler
.big:   ;; 64-bit: 48 BB xx xx xx xx xx xx xx xx (10 bytes)
        mov byte [rbp], $48
        mov byte [rbp+1], $BB
        add rbp, 2
        call _s01
        mov qword [rbp], rcx
        add rbp, 8
        jmp _compiler

;; Suffix dispatch tables
suffix_chars db "+-*/%&|^,@!_", 0
suffix_handlers:
        dq _litadd              ; +
        dq _litsub              ; -
        dq _litmul              ; *
        dq _litdiv              ; /
        dq _litmod              ; %
        dq _litand              ; &
        dq _litior              ; |
        dq _litxor              ; ^
        dq _litcomma_suffix     ; ,
        dq _litfetch            ; @
        dq _litstore            ; !
        dq _litnip              ; _

;; litcomma wrapper — called from suffix dispatch, rax=value
_litcomma_suffix:
        call _litcomma
        jmp _compiler


;; Error: IF/UNTIL/WHILE used without preceding condition
_err_nocond:
        add rsp, 8              ; pop return addr from 'call rax' in compiler
        mov rax, 1
        mov rdi, 1
        lea rsi, [err_nocond_msg]
        mov rdx, err_nocond_len
        syscall
        ;; Skip remaining input on this line
        mov rax, [tp]
        mov [tin], rax
        ;; Reset data stack
        lea r15, [dstack_top]
        xor ebx, ebx
        xor edx, edx
        ;; Clear SWAPbit
        and byte [SC], $FD
        ;; Reset compilation pointer if in anonymous context
        mov rax, [anon]
        test rax, rax
        jz .skip_reset
        mov rbp, rax
.skip_reset:
        jmp _compiler

;; =====================================================================
;; Exception handling: catch/throw
;; =====================================================================

;; catch ( xt -- exception ) execute xt, return 0 if ok, exception if throw
_catch:
        push r15                ; save data stack pointer
        push rdx                ; save NOS
        push qword [xfp]       ; save previous frame pointer
        mov [xfp], rsp          ; set new frame pointer
        mov rcx, rbx            ; xt to call
        mov rbx, rdx            ; DROP1: TOS = NOS
        mov rdx, [r15]
        add r15, 8
        call rcx                ; execute protected code
        pop qword [xfp]        ; restore frame pointer
        add rsp, 16             ; discard saved NOS and r15
        ;; No exception: push 0
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        xor ebx, ebx            ; TOS = 0 (no exception)
        ret

;; _error: inline counted-string error. Usage: call _error / db count, "msg"
;; Pops return address (= counted string) into TOS, falls through to throw.
_error:
        pop rbx                 ; return addr → TOS (pointer to counted string)
;; throw ( message -- ) unwind to catch, TOS = exception message
_throw:
        mov rsp, [xfp]          ; restore call stack
        pop qword [xfp]        ; restore previous frame pointer
        pop rdx                 ; restore NOS
        pop r15                 ; restore data stack pointer
        ret                     ; return to catch's caller with TOS=message

;; =====================================================================
;; I/O — Forth-callable read/write/accept
;; =====================================================================

;; write ( addr count fd -- written )
_write_word:
        push rax
        push rdi
        push rsi
        push rcx
        mov rax, 1              ; sys_write
        mov rdi, rbx            ; fd = TOS
        mov rcx, rdx            ; save count = NOS
        mov rsi, [r15]          ; addr = third
        mov rdx, rcx            ; count for syscall
        syscall
        mov rbx, rax            ; TOS = bytes written
        mov rdx, [r15+8]       ; NOS = item below third
        add r15, 16             ; pop third + old NOS
        pop rcx
        pop rsi
        pop rdi
        pop rax
        ret

;; read ( addr count fd -- nread )
_read_word:
        push rax
        push rdi
        push rsi
        push rcx
        xor eax, eax            ; sys_read
        mov rdi, rbx            ; fd = TOS
        mov rcx, rdx            ; save count = NOS
        mov rsi, [r15]          ; addr = third
        mov rdx, rcx            ; count for syscall
        syscall
        mov rbx, rax            ; TOS = bytes read
        mov rdx, [r15+8]       ; NOS = item below third
        add r15, 16             ; pop third + old NOS
        pop rcx
        pop rsi
        pop rdi
        pop rax
        ret

;; accept ( addr count -- nread ) read from stdin (fd=0)
_accept:
        push rax
        push rdi
        push rsi
        xor eax, eax            ; sys_read
        xor edi, edi            ; fd=0 (stdin)
        mov rsi, rdx            ; addr = NOS
        mov rdx, rbx            ; count = TOS (also syscall count arg)
        syscall
        mov rbx, rax            ; TOS = bytes read
        mov rdx, [r15]          ; NOS = item below addr
        add r15, 8              ; pop addr
        pop rsi
        pop rdi
        pop rax
        ret

;; =====================================================================
;; Line-based I/O (internal)
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

;; Backtick-named versions (ct=0) for macro composition
;; These let macros compile calls to compile-time primitives.
;; E.g.: `: 0;` 0-` 0=` IF` drop` ;THEN` ;`
; Flow control (IF/THEN/ELSE/BEGIN/AGAIN/UNTIL/WHILE/REPEAT)
; moved to ff64.boot — Forth-defined using cond/d!
WORD64 "0>=`", _zge_flags, 0, 4
WORD64 "0<=`", _zle_flags, 0, 4
WORD64 "0>`", _zgt_flags, 0, 3
WORD64 "0<`", _zlt_flags, 0, 3
WORD64 "0<>`", _zneq_flags, 0, 4
WORD64 "0=`", _zeq_flags, 0, 3
WORD64 ">=`", _ge_flags, 0, 3
WORD64 "<=`", _le_flags, 0, 3
WORD64 "u>=`", _uge_flags, 0, 4
WORD64 "u<=`", _ule_flags, 0, 4
WORD64 "u>`", _ugt_flags, 0, 3
WORD64 "u<`", _ult_flags, 0, 3
WORD64 "<>`", _neq_flags, 0, 3
WORD64 ">`", _gt_flags, 0, 2
WORD64 "<`", _lt_flags, 0, 2
WORD64 "=`", _eq_flags, 0, 2
WORD64 "0-`", _0minus_inline, 0, 3

;; FLAGS-based comparison words (ct=2)
WORD64 "0-", _0minus_inline, 2, 2
WORD64 "0>=", _zge_flags, 2, 3
WORD64 "0<=", _zle_flags, 2, 3
WORD64 "0>", _zgt_flags, 2, 2
WORD64 "0<", _zlt_flags, 2, 2
WORD64 "0<>", _zneq_flags, 2, 3
WORD64 "0=", _zeq_flags, 2, 2
WORD64 "u>=", _uge_flags, 2, 3
WORD64 "u<=", _ule_flags, 2, 3
WORD64 "u>", _ugt_flags, 2, 2
WORD64 "u<", _ult_flags, 2, 2
WORD64 ">=", _ge_flags, 2, 2
WORD64 "<=", _le_flags, 2, 2
WORD64 "<>", _neq_flags, 2, 2
WORD64 ">", _gt_flags, 2, 1
WORD64 "<", _lt_flags, 2, 1
WORD64 "=", _eq_flags, 2, 1

;; Runtime words (ct=0) — still called via compiled CALL instruction
WORD64 "cr", _cr, 0, 2
WORD64 "2", _two, 0, 1
WORD64 "1", _one, 0, 1
WORD64 ".", _dot, 0, 1
WORD64 "rshift", _rshift, 0, 6
WORD64 "lshift", _lshift, 0, 6
WORD64 "d,", _dcomma, 0, 2
WORD64 "w,", _wcomma, 0, 2
WORD64 "c,", _ccomma, 0, 2
WORD64 ",", _comma, 0, 1
WORD64 "allot", _allot, 0, 5
WORD64 "here", _here, 0, 4
WORD64 "SC", SC, 1, 2
WORD64 "?", _cond_addr, 0, 1
WORD64 "callmark", callmark, 1, 8
WORD64 "call,", _call_comma, 0, 5
WORD64 "dcall,", _dcall_comma, 0, 6
WORD64 "anon", anon, 1, 4
WORD64 "H", H, 1, 1
WORD64 "depth", _depth, 0, 5
WORD64 "/mod", _divmod, 0, 4
WORD64 "mod", _mod, 0, 3
WORD64 "/", _div, 0, 1
WORD64 "+!", _addstore, 0, 2
WORD64 "d@", _dfetch, 0, 2
WORD64 "d!", _dstore, 0, 2
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
WORD64 "parse", _parse, 0, 5
WORD64 "lnparse", _lnparse, 0, 7
WORD64 "wsparse", _wsparse_forth, 0, 7
WORD64 "header", _header_forth, 0, 6
WORD64 "exit", _exit_word, 0, 4
WORD64 "catch", _catch, 0, 5
WORD64 "throw", _throw, 0, 5
WORD64 "write", _write_word, 0, 5
WORD64 "read", _read_word, 0, 4
WORD64 "accept", _accept, 0, 6
WORD64 "compiler", _compiler, 0, 8

;; Data words (ct=1) — push address/value
WORD64 ">in", tin, 1, 3
WORD64 "tp", tp, 1, 2
WORD64 "tib", inbuf, 1, 3

;; Compile-time words (ct=1)
WORD64 "swap`", _swap_inline, 0, 5
WORD64 "lit`", _lit, 0, 4
WORD64 ">S0", _rst, 0, 3
WORD64 "s09", _s09_word, 0, 3
WORD64 "s08", _s08_word, 0, 3
WORD64 "s01", _s01_word, 0, 3
WORD64 "s1", _s1_word, 0, 2
WORD64 ",4", _comma4, 0, 2
WORD64 ",3", _comma3, 0, 2
WORD64 ",2", _comma2, 0, 2
WORD64 ",1", _comma1, 0, 2
; (IF/THEN/ELSE/BEGIN/AGAIN/UNTIL/WHILE/REPEAT now in ff64.boot)
WORD64 "anon:`", _anon_colon, 0, 6
WORD64 ">cs", _cs_push, 0, 3
WORD64 "cs>", _cs_pop, 0, 3
WORD64 ";`", _semi, 0, 2
WORD64 ":`", _colon, 0, 2
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
        ;; Reset anon so anonymous code in loaded files gets executed
        mov [anon], rbp
        mov qword [callmark], 0
        mov byte [SC], 0
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
        ;; Reset anon after boot file processing.
        ;; Boot file may leave anon=0 from unterminated definitions.
        mov [anon], rbp
        mov qword [callmark], 0
        mov byte [SC], 0
.repl_loop:
        mov rax, 1
        mov rdi, 1
        lea rsi, [prompt]
        mov rdx, 2
        syscall

        call _readline
        jz .exit

        call _compiler

        ;; Auto-execute anonymous code (like eval.'s _auto).
        ;; If anon != 0 and anon != rbp, there's pending code to run.
        mov rax, [anon]
        test rax, rax
        jz .repl_ok             ; anon=0: named def just ended, skip
        cmp rax, rbp
        je .repl_ok             ; empty block, skip
        call _semi_exec         ; execute the anonymous block
.repl_ok:
        mov rax, 1
        mov rdi, 1
        lea rsi, [ok_msg]
        mov rdx, 3
        syscall

        jmp .repl_loop

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
err_nocond_msg: db "error: requires preceding condition", 10
err_nocond_len = $ - err_nocond_msg
minus_char    db '-'
nl_char       db 10
numbuf        rb 21

        align 8
;; Compile-time stack — separate from data stack for flow control addresses.
;; Used by START/END/BREAK to save/restore mrk and break addresses.
;; 16 entries deep (128 bytes) — enough for any reasonable nesting.
cstack     rq 16
cstack_top:
csp        dq cstack_top           ; compile-time stack pointer (grows down)

        align 8
headbuf    rb 65536
heads64:   GENWORDS64

inbuf      rb 4096
filebuf    rb 65536
dstack     rb 8192
dstack_top:
codebuf    rb 65536
