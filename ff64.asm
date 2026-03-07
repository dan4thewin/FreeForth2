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

OSFORMAT

if defined ffdl
extrn dlopen
extrn dlsym
extrn dlerror
end if

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
xfp     dq 0                    ; exception frame pointer for catch/throw
CS0     dq 0                    ; initial stack pointer (argc/argv/envp derived in Forth)
bootxt  dq 0                    ; xt of _boot (set by ff64.boot)
SC      db 0                    ; SWAPbit in bit 1: 0=rbx is TOS, 2=rdx is TOS
cond_jmp dq 0                   ; ?# : pending conditional jump opcode (0=none)
                                ; dq (not db) so Forth `0 ?#!` (cell store) is safe

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

;; String/memory operations

;; cmove> ( src dst n -- ) copy n bytes backward (for overlapping dst>src)
_cmove_up:
        push rsi
        push rdi
        mov rcx, rbx            ; n
        mov rdi, rdx            ; dst
        mov rsi, [r15]          ; src
        lea rdi, [rdi+rcx-1]    ; point to last byte of dst
        lea rsi, [rsi+rcx-1]    ; point to last byte of src
        std
        rep movsb
        cld
        pop rdi
        pop rsi
        mov rbx, [r15+8]
        mov rdx, [r15+16]
        add r15, 24
        ret

_strcmp: push rsi                ; $- ( @1 @2 # -- n ) 0=match
        push rdi
        mov rcx, rbx            ; # = count
        mov rdi, rdx            ; @2
        mov rsi, [r15]          ; @1
        test rcx, rcx
        jz .strcmp_done
        repz cmpsb
        movzx ebx, byte [rsi-1]
        movzx edx, byte [rdi-1]
        sub rbx, rdx
        jmp .strcmp_out
.strcmp_done:
        xor ebx, ebx
.strcmp_out:
        mov rdx, [r15+8]       ; restore NOS (item below @1)
        lea r15, [r15+16]      ; pop @1 and old NOS (lea preserves FLAGS)
        pop rdi
        pop rsi
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

_cfetch: movzx rbx, byte [rbx]  ; c@ ( addr -- char )
        ret

_dfetch: movsxd rbx, dword [rbx] ; d@ ( addr -- sval ) sign-extended 32-bit fetch
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

_DS0:   sub r15, 8              ; DS0 ( -- addr ) data stack top address
        mov [r15], rdx
        mov rdx, rbx
        lea rbx, [dstack_top]
        ret

;; Memory compilation words
_here:  sub r15, 8              ; here ( -- addr )
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, rbp
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

;; Shift operations

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

;; swap ( a b -- b a ): toggle SWAPbit — ZERO bytes emitted!
;; This is the core of FreeForth's optimization: swap is free.
_swap_inline:
        xor byte [SC], 2           ; toggle SWAPbit
        ret

;; Inline code generators for dup, drop, over, nip, +, -, *, negate,
;; @, c@, rot, tuck are now defined as Forth backtick macros in ff64.boot,
;; matching Lavarenne's approach. Only swap` remains in assembly because
;; it modifies the compiler's SWAPbit state rather than emitting code.

;; =====================================================================
;; FLAGS-BASED CONDITIONALS (FreeForth approach)
;;
;; Comparison words set CPU FLAGS and store a conditional jump opcode
;; in cond_jmp. IF/UNTIL/WHILE read it and emit the conditional jump.
;; =====================================================================
;; Comparison routines removed — now Forth-defined in ff64.boot
;; (0-`, _?1, _?2, condition factory matching ff.boot pattern)

;; Compile-time words (ct=2): executed during compilation
;; Flow control (IF/THEN/ELSE/BEGIN/AGAIN/UNTIL/WHILE/REPEAT)
;; Migrated to ff64.boot — Forth-defined using cond/d!
;; ~140 lines of assembly replaced by ~10 lines of Forth

;; parse ( sep -- @ # ) — scan for delimiter, return start and length
_parse:
        movzx eax, bl           ; al = separator character
        mov rbx, rdx            ; drop separator from TOS; NOS stays in rdx
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
        inc rsi                 ; skip zero terminator
        pop rbx                 ; restore TOS
        pop rdx                 ; restore NOS
        jmp rsi                 ; "return" to after the string

;; Runtime helper: push inline counted string as ( addr count )
;; Called via: call _litstr_rt / db len / db "string..."
_litstr_rt:
        pop rsi                 ; rsi = address of length byte
        sub r15, 16
        mov [r15+8], rdx        ; push old NOS
        mov [r15], rbx          ; push old TOS
        movzx rbx, byte [rsi]  ; TOS = count
        inc rsi                 ; rsi = string data
        lea rax, [rsi + rbx + 1] ; rax = past string end + zero terminator
        mov rdx, rsi            ; NOS = string address
        push rax                ; push resume address
        ret                     ; jump past string

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
.word:  mov rax, rdi            ; rax = token start
        xor r8d, r8d           ; r8 = within-quote flag
.scan:  movzx ecx, byte [rdi]  ; read char at current position
        inc rdi                 ; advance past it
        cmp rdi, rsi
        ja .done               ; past EOF → done
        and cl, $7F
        cmp cl, '"'
        jne .nq
        xor r8d, 1             ; toggle quote flag
.nq:    cmp r8d, 1
        je .scan               ; inside quotes: skip whitespace check
        cmp cl, ' '
        ja .scan               ; non-whitespace: continue
        ;; Found whitespace outside quotes. rdi is past the whitespace char.
        ;; Token is rax..rdi-2 (rdi-1 is the whitespace we just read).
        ;; But we want tin to point past the delimiter for next parse.
.done:  mov [tin], rdi
        lea rcx, [rdi - 1]     ; rcx = past last char of token
        sub rcx, rax            ; rcx = token length
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

;;; number input — table-driven parser
;;; Ported from Lavarenne's i386 _number (ff.asm:536-657).
;;; Supports: decimal, $hex, &octal, %binary, #base, 'quoted ASCII,
;;;           y-m-d Gregorian dates, h:m:s times, d_h day-hour,
;;;           skip chars (' , /), negative sign.
;;; API: rax=string addr, rcx=string length
;;;      Success: rax=number, ZF set.  Failure: rax=orig addr, ZF clear.

numaccu dq 0

_number:
        push r8
        push rdx                ; save NOS (data stack)
        push r10                ; save r10 (used as current base)
        mov r8, rax             ; r8 = original string addr (for fail)
        mov r10d, 10            ; default base = decimal
        mov rsi, rax            ; rsi = scan pointer
        lea rdi, [rax + rcx]   ; rdi = string end
        xor ecx, ecx            ; accumulator = 0
        mov [numaccu], rcx      ; secondary accumulator = 0
        lodsb                   ; al = first char
        push rax                ; save initial (maybe '-' sign)
        cmp al, '-'             ; skip initial sign
        jne @f
        lodsb
@@:     cmp al, "'"             ; single quoted ASCII
        jne .e
        movzx ecx, byte [rsi]  ; ecx = ASCII value of next char
        jmp .s
.7:     mov r10d, 8             ; & → octal
        jmp .4
.6:     mov r10d, 2             ; % → binary
        jmp .4
.5:     mov r10d, 16            ; $ → hexadecimal
        jmp .4
.z:     mov r10d, 10
        jmp .4
.8:     test ecx, ecx           ; # → base = accumulated value
        jz .z                   ; if zero, default to decimal
        mov r10d, ecx           ; set base
.d:     xor ecx, ecx            ; reset accumulator
.4:     lodsb                   ; al = next character
.e:     cmp al, $7F             ; reject >= $7F
        jae .0
        movzx eax, al
        push rax                ; save digit value
        movzx eax, byte [.ct + rax]   ; method index from char table
        mov rax, [.jt + rax*8]        ; handler address from jump table
        xchg rax, [rsp]               ; restore digit, push handler
        ret                            ; dispatch to handler
.jt:    dq .0,.1,.2,.3,.4,.5,.6,.7,.8,.9,.10,.11,.12
.3:     sub al, 'a'-'A'         ; lowercase → uppercase
.2:     sub al, 'A'-'0'-$A      ; uppercase hex digit
.1:     sub al, '0'             ; decimal digit
        cmp eax, r10d           ; reject digit >= base
        jae .0
        imul rcx, r10           ; accumulator *= base
        add rcx, rax            ; accumulator += digit
        cmp rsi, rdi            ; end of string?
        jb .4                   ; no → next char
        add rcx, [numaccu]      ; yes → add secondary accumulator
.s:     cmp byte [rsp], '-'     ; saved initial sign
        jne @f
        neg rcx
@@:     mov rax, rcx            ; result in rax
        add rsp, 8              ; discard saved initial
        pop r10
        pop rdx
        pop r8
        cmp rax, rax            ; ZF set = success
        ret
.9:                              ; whitespace (wsparse compat)
.0:     pop rax                  ; discard saved initial
        mov rax, r8              ; restore original string addr
        pop r10
        pop rdx
        pop r8
        test rax, rax            ; ZF clear (addr is never 0)
        ret

.10:    xchg rcx, [numaccu]      ; Gregorian date: y-m-d
        test ecx, ecx
        jz .4                    ; first dash: year → accu, continue
        xchg rcx, [numaccu]     ; ecx = month, [numaccu] = year
        cmp ecx, 3
        jge @f
        add ecx, 12             ; move origin to March 1st
        dec qword [numaccu]
@@:     inc ecx
        push rdx
        mov eax, 31+30+31+30+31 ; = 153 (5-month period)
        mul ecx                  ; edx:eax = 153*(m+1)
        mov ecx, 5
        div ecx                  ; eax = 153*(m+1)/5
        sub eax, 123             ; day-of-year (can be negative)
        cdqe                     ; sign-extend eax → rax (32→64 bit)
        xchg rax, [numaccu]     ; rax = year, [numaccu] = day-of-year
        imul ecx, eax, 1461
        shr ecx, 2               ; ecx = 365y + y/4
        add [numaccu], rcx
        mov ecx, 100
        xor edx, edx
        div ecx                  ; eax = y/100
        sub [numaccu], rax
        shr eax, 2               ; eax = y/400
        add [numaccu], rax
        pop rdx
        xor eax, eax
        jmp .d
.11:    cmp qword [numaccu], 730484  ; date-time separator
        jl @f
        sub qword [numaccu], 730485  ; translate to 2000-03-01 origin
@@:     mov al, 24               ; d_h: multiply by 24
        jmp @f
.12:    mov al, 60               ; h:m:s: multiply by 60
@@:     add rcx, [numaccu]
        imul rcx, rax            ; shift accumulator
        mov [numaccu], rcx
        jmp .d

;;;         0  1  2  3   4  5  6  7   8  9  A  B   C  D  E  F
;;;    00: NUL                                                    ; 0:error
.ct:    db  9, 0, 0, 0,  0, 0, 0, 0,  0, 9, 9, 9,  9, 9, 0, 0  ; 1:digit
;;;    10: DLE                                                    ; 2:upper
        db  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0  ; 3:lower
;;;    20:     !  "  #   $  %  &  '   (  )  *  +   ,  -  .  /   ; 4:skip
        db  9, 0, 0, 8,  5, 6, 7, 4,  0, 0, 0, 0,  4,10, 0, 4  ; 5:$hex
;;;    30:  0  1  2  3   4  5  6  7   8  9  :  ;   <  =  >  ?   ; 6:%bin
        db  1, 1, 1, 1,  1, 1, 1, 1,  1, 1,12, 0,  0, 0, 0, 0  ; 7:&oct
;;;    40:  @  A  B  C   D  E  F  G   H  I  J  K   L  M  N  O   ; 8:#base
        db  0, 2, 2, 2,  2, 2, 2, 2,  2, 2, 2, 2,  2, 2, 2, 2  ; 9:ws
;;;    50:  P  Q  R  S   T  U  V  W   X  Y  Z  [   \  ]  ^  _   ; 10:- date
        db  2, 2, 2, 2,  2, 2, 2, 2,  2, 2, 2, 0,  0, 0, 0,11  ; 11:_ ×24
;;;    60:  `  a  b  c   d  e  f  g   h  i  j  k   l  m  n  o   ; 12:: ×60
        db  0, 3, 3, 3,  3, 3, 3, 3,  3, 3, 3, 3,  3, 3, 3, 3
;;;    70:  p  q  r  s   t  u  v  w   x  y  z  {   |  }  ~ DEL
        db  3, 3, 3, 3,  3, 3, 3, 3,  3, 3, 3, 3,  3, 3, 3, 0

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
        call _rst               ; reconcile SWAPbit before closing anonymous block
        mov byte [rbp], $C3
        inc rbp
        mov rax, [anon]
        mov rbp, rax            ; reset rbp to anon start (for execution)
        call rax                ; execute anonymous code (may advance rbp via allot)
        ;; After execution, rbp reflects any allot/eval changes.
        ;; Fall through to _anon to set [anon]=rbp, preserving allotted space.
        ;; This matches i386 behavior where _semi falls through to _anon.
        mov [anon], rbp
        mov qword [callmark], 0
        mov byte [SC], 0
        ret


;; =====================================================================
;; Compiler main loop
;; =====================================================================

_compiler:
        call _wsparse
        test ecx, ecx
        jz _compiler_done

        ;; --- Backtick name mangling ---
        ;; No keyword fast-paths: ; : variable constant are found via
        ;; dictionary lookup (backtick macros), as in Lavarenne's ff.asm.
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
        ;; Found via backtick: dispatch by ct
        test ecx, 1            ; ct bit 0 set = literal/data word
        jz .bt_exec
        ;; ct=1 (or ct=3): push xt value as compile-time literal
        sub r15, 8
        mov [r15], rdx
        mov rdx, rbx
        mov rbx, rax
        jmp _compiler
.bt_exec:
        ;; ct=0 (or ct=2): execute immediately
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
        ;; ─── String compiler ───
        ;; Check if last char is " (trailing quote = string literal)
        cmp ecx, 2
        jb .not_string
        cmp byte [rax + rcx - 1], '"'
        jne .not_string
        ;; Token ends with " — dispatch on initial character
        ;; rax = token start, ecx = token length (including trailing ")
        push rax
        push rcx
        movzx edi, byte [rax]   ; edi = initial character
        inc rax                 ; skip initial
        sub ecx, 2              ; ecx = string content length (excl initial and final ")
        ;; Save content start/length for strcomma
        push rax                ; content start
        push rcx                ; content length
        cmp dil, ','
        je .str_memcomma
        call _rst
        cmp dil, '"'
        je .str_litstr
        cmp dil, '.'
        je .str_dotstr
        cmp dil, '!'
        je .str_error
        ;; Unknown initial — not a valid string, fall through
        add rsp, 32             ; discard 4 pushes
        jmp .not_string
.str_litstr:
        ;; Compile: call _litstr_rt
        mov byte [rbp], $E8
        inc rbp
        lea rdi, [_litstr_rt]
        lea rsi, [rbp + 4]
        sub rdi, rsi
        mov dword [rbp], edi
        add rbp, 4
        jmp .str_strcomma
.str_dotstr:
        ;; Compile: call _dotstr_rt
        mov byte [rbp], $E8
        inc rbp
        lea rdi, [_dotstr_rt]
        lea rsi, [rbp + 4]
        sub rdi, rsi
        mov dword [rbp], edi
        add rbp, 4
        jmp .str_strcomma
.str_error:
        ;; Compile: call _error
        mov byte [rbp], $E8
        inc rbp
        lea rdi, [_error]
        lea rsi, [rbp + 4]
        sub rdi, rsi
        mov dword [rbp], edi
        add rbp, 4
        jmp .str_strcomma
.str_strcomma:
        ;; Compile counted string: db length, db string...
        pop rcx                 ; content length
        pop rsi                 ; content start
        mov r8, rbp             ; r8 = address of length byte (to patch later)
        mov byte [rbp], 0      ; placeholder for length
        inc rbp
        ;; Copy string bytes with encoding:
        ;; _ → space, " → skip, \ → literal next, ^ → toggle bit6 of next
.str_copy:
        test ecx, ecx
        jz .str_end
        movzx edi, byte [rsi]
        inc rsi
        dec ecx
        cmp dil, '\'            ; prefix \ escapes next
        jne .str_c1
        movzx edi, byte [rsi]
        inc rsi
        dec ecx
        jmp .str_emit
.str_c1:
        cmp dil, '^'            ; prefix ^ toggles bit6 of next
        jne .str_c2
        movzx edi, byte [rsi]
        inc rsi
        dec ecx
        xor dil, $40
        jmp .str_emit
.str_c2:
        cmp dil, '~'            ; suffix ~ toggles bit7 of previous
        jne .str_c3
        xor byte [rbp-1], $80
        jmp .str_copy
.str_c3:
        cmp dil, '"'            ; ignore embedded quotes
        je .str_copy
        cmp dil, '_'            ; _ → space
        jne .str_emit
        mov dil, ' '
.str_emit:
        mov byte [rbp], dil
        inc rbp
        jmp .str_copy
.str_end:
        ;; Patch the length byte with actual compiled string length
        mov rdi, rbp
        sub rdi, r8
        dec rdi                 ; subtract the length byte itself
        mov byte [r8], dil
        mov byte [rbp], 0      ; zero-terminate
        inc rbp
        add rsp, 16             ; discard outer saved rax/rcx
        jmp _compiler
.str_memcomma:
        ;; ,"..." — raw data, no call, no count
        pop rcx                 ; content length
        pop rsi                 ; content start
        add rsp, 16             ; discard outer pushes
.str_rawcopy:
        test ecx, ecx
        jz .str_rawend
        movzx edi, byte [rsi]
        inc rsi
        dec ecx
        cmp dil, '\'
        jne .str_r1
        movzx edi, byte [rsi]
        inc rsi
        dec ecx
        jmp .str_rawemit
.str_r1:
        cmp dil, '^'
        jne .str_r2
        movzx edi, byte [rsi]
        inc rsi
        dec ecx
        xor dil, $40
        jmp .str_rawemit
.str_r2:
        cmp dil, '~'
        jne .str_r3
        xor byte [rbp-1], $80
        jmp .str_rawcopy
.str_r3:
        cmp dil, '"'
        je .str_rawcopy
        cmp dil, '_'
        jne .str_rawemit
        mov dil, ' '
.str_rawemit:
        mov byte [rbp], dil
        inc rbp
        jmp .str_rawcopy
.str_rawend:
        jmp _compiler
.not_string:
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
        cmp qword [xfp], 0
        jz .throw_nocatch
        mov rsp, [xfp]          ; restore call stack
        pop qword [xfp]        ; restore previous frame pointer
        pop rdx                 ; restore NOS
        pop r15                 ; restore data stack pointer
        ret                     ; return to catch's caller with TOS=message
.throw_nocatch:
        ;; No catch frame: print the error message and return
        movzx edx, byte [rbx]   ; string count
        lea rsi, [rbx + 1]      ; string data
        mov rax, 1              ; sys_write
        mov rdi, 1              ; stdout
        syscall
        ;; Print newline
        push rax
        mov rax, 1
        mov rdi, 1
        lea rsi, [nl_char]
        mov rdx, 1
        syscall
        pop rax
        ret

;; =====================================================================
;; I/O — Forth-callable read/write/accept
;; =====================================================================

;; find ( addr len -- addr len | xt 0 )
;; Look up a word in the dictionary. If found, replace with xt and push 0.
;; If not found, leave addr and len unchanged.
_find_forth:
        mov rax, rdx            ; addr = NOS
        mov rcx, rbx            ; len = TOS
        call _find
        jc .find_not_found
        ;; Found: rax=xt, ecx=ct. Push xt and 0.
        mov rdx, rax            ; NOS = xt
        xor ebx, ebx            ; TOS = 0
        ret
.find_not_found:
        ret

;; accept ( addr count -- nread ) read from stdin, one line at a time
;; Reads byte-by-byte until newline, EOF, or count reached.
_accept:
        push rax
        push rdi
        push rsi
        push rcx
        mov rsi, rdx            ; rsi = buffer addr (NOS)
        mov rcx, rbx            ; rcx = max count (TOS)
        xor r8d, r8d            ; r8 = bytes read so far
.loop:  cmp r8, rcx
        jge .done               ; reached max count
        lea rdi, [rsi + r8]     ; read position
        push rcx
        push rsi
        push r8
        xor eax, eax            ; sys_read
        xor edi, edi            ; fd=0 (stdin)
        lea rsi, [rsp-1]        ; temp stack byte
        mov edx, 1              ; read 1 byte
        push rax                ; allocate stack byte
        lea rsi, [rsp]
        syscall
        cmp rax, 1
        jne .eof_pop
        movzx eax, byte [rsp]   ; get the byte
        add rsp, 8              ; free stack byte
        pop r8
        pop rsi
        pop rcx
        mov byte [rsi + r8], al ; store byte
        inc r8
        cmp al, 10              ; newline?
        jne .loop
.done:  mov rbx, r8             ; TOS = bytes read
        mov rdx, [r15]          ; NOS = item below addr
        add r15, 8              ; pop addr
        pop rcx
        pop rsi
        pop rdi
        pop rax
        ret
.eof_pop:
        add rsp, 8              ; free stack byte
        pop r8
        pop rsi
        pop rcx
        jmp .done

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

;; =====================================================================
;; Signal handling — SEGV handler via rt_sigaction
;; =====================================================================

;; _segv_handler: called by kernel on SIGSEGV. Prints message and throws.
;; If catch frame (xfp) is active, throw to it. Otherwise, exit(139).
_segv_handler:
        ;; Check if we have a catch frame
        cmp qword [xfp], 0
        je .segv_fatal
        ;; We have a catch frame — print "SEGV" and throw
        ;; rt_sigreturn first to clean up signal context
        ;; Actually, we can't easily throw from a signal handler because
        ;; the stack frame is wrong. Just print and exit.
.segv_fatal:
        mov rax, 1              ; sys_write
        mov rdi, 2              ; stderr
        lea rsi, [segv_msg]
        mov rdx, segv_msg_len
        syscall
        mov rax, 60             ; sys_exit
        mov rdi, 139            ; 128 + SIGSEGV(11)
        syscall

;; _segv_restorer: required on x86-64 (SA_RESTORER flag)
;; Exposed as constant so Forth SEGV setup can use it with rt_sigaction.
_segv_restorer:
        mov rax, 15             ; sys_rt_sigreturn
        syscall

;; =====================================================================
;; Dynamic library interface — dlopen/dlsym/dlerror wrappers
;; =====================================================================
;; x86-64 SysV ABI: args in rdi,rsi,rdx,rcx,r8,r9; result in rax.
;; Callee-saved (preserved across C calls): rbx,rbp,r12,r13,r14,r15.
;; Stack must be 16-byte aligned before call instruction.

if defined ffdl

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

;; Backtick-named versions (ct=0) for macro composition
;; These let macros compile calls to compile-time primitives.
;; E.g.: `: 0;` 0-` 0=` IF` drop` ;THEN` ;`
;; Inline code generators (dup, drop, over, etc.) are now defined purely
;; as Forth backtick macros in ff64.boot, matching Lavarenne's approach.
; Flow control (IF/THEN/ELSE/BEGIN/AGAIN/UNTIL/WHILE/REPEAT)
; moved to ff64.boot — Forth-defined using cond/d!
; Comparisons moved to ff64.boot — Forth-defined matching ff.boot pattern

;; Runtime words (ct=0) — still called via compiled CALL instruction
;; WORD64 entries ordered by ascending code address (XT) so the header
;; chain walks in decreasing XT order — required for first-match findh.

;; Constants (ct=1) — XT stores value, not code address; order irrelevant
WORD64 "SC", SC, 1, 2
WORD64 "?#", cond_jmp, 1, 2
WORD64 "callmark", callmark, 1, 8
WORD64 "anon", anon, 1, 4
WORD64 "H", H, 1, 1
WORD64 "CS0", CS0, 1, 3
WORD64 "_bootxt", bootxt, 1, 7
WORD64 "sigrestorer", _segv_restorer, 1, 11
WORD64 ">in", tin, 1, 3
WORD64 "tp", tp, 1, 2
WORD64 "tib", tib, 1, 3
WORD64 "eob", eob, 1, 3
WORD64 "helpbuf", helpbuf, 1, 7
WORD64 "xfp", xfp, 1, 3

;; Code words — ascending XT order
WORD64 ">S0", _rst, 0, 3
WORD64 "cmove>", _cmove_up, 0, 6
WORD64 "$-", _strcmp, 0, 2
WORD64 "emit", _emit, 0, 4
WORD64 "d@", _dfetch, 0, 2
WORD64 "depth", _depth, 0, 5
WORD64 "DS0", _DS0, 0, 3
WORD64 "call,", _call_comma, 0, 5
WORD64 "dcall,", _dcall_comma, 0, 6
WORD64 "anon:`", _anon_colon, 0, 6
WORD64 ">cs", _cs_push, 0, 3
WORD64 "cs>", _cs_pop, 0, 3
WORD64 "s1", _s1_word, 0, 2
WORD64 "s01", _s01_word, 0, 3
WORD64 "s08", _s08_word, 0, 3
WORD64 "s09", _s09_word, 0, 3
WORD64 ",1", _comma1, 0, 2
WORD64 ",2", _comma2, 0, 2
WORD64 ",3", _comma3, 0, 2
WORD64 ",4", _comma4, 0, 2
WORD64 "lit`", _lit, 0, 4
WORD64 "swap`", _swap_inline, 0, 5
WORD64 "parse", _parse, 0, 5
WORD64 "lnparse", _lnparse, 0, 7
WORD64 "wsparse", _wsparse_forth, 0, 7
WORD64 "header", _header_forth, 0, 6
WORD64 "exit", _exit_word, 0, 4
WORD64 ":`", _colon, 0, 2
WORD64 ";`", _semi, 0, 2
WORD64 "compiler", _compiler, 0, 8
WORD64 "catch", _catch, 0, 5
WORD64 "throw", _throw, 0, 5
WORD64 "find", _find_forth, 0, 4
WORD64 "accept", _accept, 0, 6
WORD64 "syscall", _syscall, 0, 7
WORD64 "#lib", _dllib, 0, 4
WORD64 "#fun", _dlfun, 0, 4
WORD64 "#call", _dlcall, 0, 5

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

        ;; Save initial stack pointer for Forth (argc/argv/envp derived from CS0)
        mov [CS0], rsp

        ;; Compile embedded boot source
        lea rax, [boot64]
        mov [tin], rax
        lea rax, [boot64_end]
        mov [tp], rax
        mov [anon], rbp
        mov qword [callmark], 0
        mov byte [SC], 0
        call _compiler

        ;; Execute boot's final anonymous block: _boot ;
        ;; _boot calls doargv (processes -f args), _hidepvt, _top (REPL).
        ;; _top never returns — it loops or calls bye/exit.
        call _semi_exec

        ;; Fallback exit (should never reach here)
        mov rax, 60
        xor rdi, rdi
        syscall

;; =====================================================================
;; Data
;; =====================================================================

errmsg:       db "error: "
err_noname:   db "error: : without name"
              db 10
err_noname_len = $ - err_noname
err_nocond_msg: db "error: requires preceding condition", 10
err_nocond_len = $ - err_nocond_msg
segv_msg:     db 10, "*** SEGV (segmentation fault) ***", 10
segv_msg_len = $ - segv_msg
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

        align 8
boot64:    file "ff64.boot.min"
boot64_end:
    boot64_size = boot64_end - boot64

;; BSS: uninitialized buffers — NOBITS section, not stored in file.
;; Mirrors i386 pattern (ff.asm:1335): section '.bss' after last initialized data.
;; The linker merges .flat (WAX) + .bss (WA) into one RWE LOAD segment,
;; with MemSiz > FileSiz — the kernel zero-fills BSS pages on demand.
if defined ffdl
section '.bss'
end if

codebuf    rb 65536
tib        rb 1024*256             ; terminal input and file-stack buffer (i386 layout)
eob        rb 1024                 ; end-of-buffer scratch area
helpbuf    rb 131072               ; 128KB buffer for help file reading
dstack     rb 8192
dstack_top:
