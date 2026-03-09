;;; ffpp.asm — FreeForth preprocessor
;;;
;;; A minimal source preprocessor for FreeForth, written in x86-64
;;; assembly, buildable by FASM with no external dependencies.
;;;
;;; Features:
;;;   - Strips ( ... ) comments (word-delimited, no nesting)
;;;   - Strips \ comments (word-delimited, to end of line)
;;;   - Preserves "..." strings verbatim (no " inside strings)
;;;   - Collapses multiple whitespace to single space
;;;   - Collapses multiple newlines to single newline
;;;   - ‸path includes (U+2038, recursive, 8-level limit)
;;;   - Reads files from args or stdin if none given
;;;
;;; Build: fasm ffpp.asm ffpp
;;;
;;; Usage: ffpp [file ...]       (stdin if no args)
;;;        echo 'code' | ffpp

format elf64 executable 3
entry _start
segment readable writeable executable

;; =====================================================================
;; Constants
;; =====================================================================

SYS_READ        = 0
SYS_WRITE       = 1
SYS_OPEN        = 2
SYS_CLOSE       = 3
SYS_BRK         = 12
SYS_EXIT        = 60

O_RDONLY        = 0
STDIN           = 0
STDOUT          = 1
STDERR          = 2

OBUF_SZ         = 8192         ; output buffer size
PBUF_SZ         = 4096         ; path buffer for includes
MAX_DEPTH       = 8            ; include nesting limit

;; Include stack frame layout (per level):
;;   [+0]  buf_ptr   (pointer to mmap'd/read file data)
;;   [+8]  buf_len   (length of file data)
;;   [+16] cur_pos   (current byte offset)
;;   [+24] allocated (1 if we malloc'd the buffer, 0 for stdin)
FRAME_SZ        = 32

;; =====================================================================
;; Entry point
;; =====================================================================

_start:
        ;; argc is at [rsp], argv at [rsp+8], argv[1] at [rsp+16], etc.
        mov     r12, [rsp]             ; argc
        lea     r13, [rsp+8]           ; argv[]

        ;; Initialize state
        xor     eax, eax
        mov     [depth], eax           ; include depth = 0
        mov     [obuf_pos], eax        ; output buffer position = 0
        mov     byte [prev_was_ws], 1  ; start as if prev was whitespace (BOF)
        mov     byte [prev_was_nl], 1  ; suppress leading blank lines

        ;; If argc <= 1, read stdin
        cmp     r12, 1
        jle     .do_stdin

        ;; Process each filename arg
        mov     r14, 1                 ; arg index (skip argv[0])
.arg_loop:
        cmp     r14, r12
        jge     .done
        mov     rdi, [r13 + r14*8]    ; argv[i]
        call    process_file
        inc     r14
        jmp     .arg_loop

.do_stdin:
        call    process_stdin

.done:
        ;; Ensure final newline
        cmp     dword [obuf_pos], 0
        je      .no_final_nl
        call    ob_rstrip              ; strip trailing whitespace
        ;; Check if last byte in obuf is newline
        mov     ecx, [obuf_pos]
        movzx   eax, byte [obuf + ecx - 1]
        cmp     al, 10
        je      .no_final_nl
        mov     al, 10
        call    ob_putc
.no_final_nl:
        call    ob_flush
        xor     edi, edi
        mov     eax, SYS_EXIT
        syscall

;; =====================================================================
;; process_file: open, read, process, close a named file
;; Input: rdi = filename (NUL-terminated)
;; =====================================================================

process_file:
        push    rbx
        push    rbp
        push    r15

        ;; Open file
        mov     rsi, O_RDONLY
        xor     edx, edx
        mov     eax, SYS_OPEN
        syscall
        test    rax, rax
        js      .open_err
        mov     ebx, eax               ; fd

        ;; Get file size via seeking: read in chunks instead
        ;; Allocate buffer via brk
        call    brk_current
        mov     rbp, rax               ; buf_start

        ;; Read file in a loop
        xor     r15d, r15d             ; total bytes read
.read_loop:
        ;; Extend brk by 64KB
        lea     rdi, [rbp + r15 + 65536]
        call    brk_set

        ;; Read chunk
        mov     edi, ebx               ; fd
        lea     rsi, [rbp + r15]       ; buffer
        mov     edx, 65536
        mov     eax, SYS_READ
        syscall
        test    rax, rax
        jle     .read_done
        add     r15, rax
        jmp     .read_loop

.read_done:
        ;; Close fd
        mov     edi, ebx
        mov     eax, SYS_CLOSE
        syscall

        ;; Process the buffer
        mov     rdi, rbp               ; buf ptr
        mov     rsi, r15               ; buf len
        call    process_buf

        ;; Release brk back
        mov     rdi, rbp
        call    brk_set

        pop     r15
        pop     rbp
        pop     rbx
        ret

.open_err:
        ;; Print error: "ffpp: cannot open: <filename>\n" to stderr
        ;; (rdi still has filename from caller — but it was clobbered by syscall)
        ;; We'll just print a generic message
        lea     rsi, [err_open]
        mov     edx, err_open_len
        mov     edi, STDERR
        mov     eax, SYS_WRITE
        syscall
        pop     r15
        pop     rbp
        pop     rbx
        ret

;; =====================================================================
;; process_stdin: read all of stdin into buffer, then process
;; =====================================================================

process_stdin:
        push    rbp
        push    r15

        call    brk_current
        mov     rbp, rax               ; buf_start
        xor     r15d, r15d             ; total read

.read_loop:
        lea     rdi, [rbp + r15 + 65536]
        call    brk_set

        xor     edi, edi               ; stdin
        lea     rsi, [rbp + r15]
        mov     edx, 65536
        mov     eax, SYS_READ
        syscall
        test    rax, rax
        jle     .read_done
        add     r15, rax
        jmp     .read_loop

.read_done:
        mov     rdi, rbp
        mov     rsi, r15
        call    process_buf

        mov     rdi, rbp
        call    brk_set

        pop     r15
        pop     rbp
        ret

;; =====================================================================
;; process_buf: the main state machine
;; Input: rdi = buffer pointer, rsi = buffer length
;;
;; States (implicit via code path):
;;   Normal mode: scan bytes, detect comments/strings/includes
;;   Paren comment: skip until ) followed by whitespace
;;   Line comment: skip until newline
;;   String: pass through until closing "
;;   Include path: accumulate path, then recurse
;; =====================================================================

process_buf:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15

        mov     rbp, rdi               ; buf_ptr
        mov     r12, rsi               ; buf_len
        xor     r13d, r13d             ; cur_pos = 0

        ;; ---- Normal mode ----
.normal:
        cmp     r13, r12
        jge     .buf_done

        movzx   eax, byte [rbp + r13]

        ;; Check for newline
        cmp     al, 10
        je      .got_newline

        ;; Check for whitespace (space or tab)
        cmp     al, ' '
        je      .got_space
        cmp     al, 9                  ; tab
        je      .got_space

        ;; Check for " — enter string mode
        cmp     al, '"'
        je      .got_quote

        ;; Check for ( — possible paren comment
        cmp     al, '('
        je      .maybe_paren

        ;; Check for \ — possible line comment
        cmp     al, '\'
        je      .maybe_line

        ;; Check for ‸ (U+2038): E2 80 B8
        cmp     al, 0xE2
        je      .maybe_include

        ;; Regular character — emit it
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
        inc     r13
        jmp     .normal

        ;; ---- Newline handling ----
.got_newline:
        call    ob_rstrip              ; strip trailing whitespace
        cmp     byte [prev_was_nl], 0
        jne     .skip_newline          ; collapse multiple newlines
        mov     byte [prev_was_nl], 1
        mov     byte [prev_was_ws], 1
        mov     al, 10
        call    ob_putc
.skip_newline:
        inc     r13
        jmp     .normal

        ;; ---- Space/tab handling ----
.got_space:
        cmp     byte [prev_was_ws], 0
        jne     .skip_space            ; collapse multiple spaces
        ;; Don't emit space if previous was newline (leading space)
        cmp     byte [prev_was_nl], 0
        jne     .skip_space
        mov     byte [prev_was_ws], 1
        mov     al, ' '
        call    ob_putc
.skip_space:
        inc     r13
        jmp     .normal

        ;; ---- String mode: " ... " ----
.got_quote:
        ;; Emit the quote
        mov     al, '"'
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
        inc     r13

.string_loop:
        cmp     r13, r12
        jge     .buf_done              ; unterminated string — EOF
        movzx   eax, byte [rbp + r13]
        call    ob_putc
        inc     r13
        cmp     al, '"'
        jne     .string_loop
        ;; Closing quote emitted, back to normal
        jmp     .normal

        ;; ---- Paren comment: ( ... ) ----
.maybe_paren:
        ;; ( is a comment only if preceded by ws AND followed by ws
        cmp     byte [prev_was_ws], 0
        je      .not_paren
        ;; Check next char is whitespace
        lea     rcx, [r13 + 1]
        cmp     rcx, r12
        jge     .not_paren             ; ( at end of file — not comment
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .enter_paren
        cmp     dl, 9
        je      .enter_paren
        cmp     dl, 10
        je      .enter_paren
        jmp     .not_paren

.enter_paren:
        ;; Skip until ) preceded by whitespace and followed by whitespace/EOF
        inc     r13                    ; skip (
.paren_loop:
        cmp     r13, r12
        jge     .buf_done
        movzx   eax, byte [rbp + r13]
        inc     r13
        cmp     al, ')'
        jne     .paren_loop
        ;; Found ) — check preceded by whitespace
        cmp     r13, 1
        jle     .paren_check_after     ; ) at start — treat as delimited
        movzx   edx, byte [rbp + r13 - 2] ; char before )
        cmp     dl, ' '
        je      .paren_check_after
        cmp     dl, 9
        je      .paren_check_after
        cmp     dl, 10
        je      .paren_check_after
        jmp     .paren_loop            ; ) not preceded by ws — keep scanning
.paren_check_after:
        ;; Check followed by whitespace or EOF
        cmp     r13, r12
        jge     .paren_done            ; ) at EOF — comment ends
        movzx   edx, byte [rbp + r13]
        cmp     dl, ' '
        je      .paren_done
        cmp     dl, 9
        je      .paren_done
        cmp     dl, 10
        je      .paren_done
        jmp     .paren_loop            ; ) not followed by ws — keep scanning
.paren_done:
        mov     byte [prev_was_ws], 1
        jmp     .normal

.not_paren:
        ;; Emit ( as regular char
        mov     al, '('
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
        inc     r13
        jmp     .normal

        ;; ---- Line comment: \ to EOL ----
.maybe_line:
        ;; \ is comment only if preceded by ws AND followed by ws or EOL
        cmp     byte [prev_was_ws], 0
        je      .not_backslash
        ;; Check next char
        lea     rcx, [r13 + 1]
        cmp     rcx, r12
        jge     .enter_line_comment    ; \ at EOF — delimiter implicit
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .enter_line_comment
        cmp     dl, 9
        je      .enter_line_comment
        cmp     dl, 10
        je      .enter_line_comment
        jmp     .not_backslash

.enter_line_comment:
        ;; Skip to end of line
.line_loop:
        cmp     r13, r12
        jge     .buf_done
        movzx   eax, byte [rbp + r13]
        inc     r13
        cmp     al, 10
        jne     .line_loop
        ;; Newline found — treat it as a normal newline
        dec     r13                    ; back up so .normal sees the \n
        jmp     .normal

.not_backslash:
        mov     al, '\'
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
        inc     r13
        jmp     .normal

        ;; ---- Include: ‸ (E2 80 B8) ----
.maybe_include:
        ;; Need at least 3 bytes for ‸
        lea     rcx, [r13 + 2]
        cmp     rcx, r12
        jg      .not_include
        cmp     byte [rbp + r13 + 1], 0x80
        jne     .not_include
        cmp     byte [rbp + r13 + 2], 0xB8
        jne     .not_include

        ;; Must be preceded by whitespace (or BOF)
        cmp     byte [prev_was_ws], 0
        je      .not_include

        ;; It's a ‸ — skip the 3 UTF-8 bytes
        add     r13, 3

        ;; Accumulate path into pbuf until whitespace/newline/EOF
        xor     ecx, ecx              ; path length
.inc_path_loop:
        lea     rdx, [r13 + rcx]      ; check bounds with rcx
        cmp     rdx, r12
        jge     .inc_path_done
        movzx   eax, byte [rbp + rdx]
        cmp     al, ' '
        je      .inc_path_done
        cmp     al, 9
        je      .inc_path_done
        cmp     al, 10
        je      .inc_path_done
        cmp     ecx, PBUF_SZ - 1
        jge     .inc_path_done
        mov     [pbuf + rcx], al
        inc     ecx
        jmp     .inc_path_loop

.inc_path_done:
        mov     byte [pbuf + rcx], 0   ; NUL terminate path
        add     r13, rcx               ; advance past path

        ;; Check nesting depth
        mov     eax, [depth]
        cmp     eax, MAX_DEPTH
        jge     .inc_too_deep

        ;; Save current state on include stack
        mov     edx, [depth]
        imul    edi, edx, FRAME_SZ
        lea     rsi, [inc_stack + rdi]
        mov     [rsi], rbp             ; buf_ptr
        mov     [rsi + 8], r12         ; buf_len
        mov     [rsi + 16], r13        ; cur_pos
        inc     dword [depth]

        ;; Open and process included file
        push    r13
        push    r12
        push    rbp
        lea     rdi, [pbuf]
        call    process_file
        pop     rbp
        pop     r12
        pop     r13

        ;; Restore state
        dec     dword [depth]
        mov     edx, [depth]
        imul    edi, edx, FRAME_SZ
        lea     rsi, [inc_stack + rdi]
        mov     rbp, [rsi]
        mov     r12, [rsi + 8]
        mov     r13, [rsi + 16]

        jmp     .normal

.inc_too_deep:
        ;; Error: include nesting too deep
        push    r13
        push    r12
        push    rbp
        lea     rsi, [err_depth]
        mov     edx, err_depth_len
        mov     edi, STDERR
        mov     eax, SYS_WRITE
        syscall
        pop     rbp
        pop     r12
        pop     r13
        jmp     .normal

.not_include:
        ;; Emit E2 as regular byte
        mov     al, 0xE2
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
        inc     r13
        jmp     .normal

.buf_done:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

;; =====================================================================
;; ob_rstrip: remove all trailing spaces/tabs from output buffer
;; =====================================================================

ob_rstrip:
        mov     ecx, [obuf_pos]
.loop:  test    ecx, ecx
        jz      .done
        cmp     byte [obuf + rcx - 1], ' '
        je      .strip
        cmp     byte [obuf + rcx - 1], 9    ; tab
        je      .strip
        jmp     .done
.strip: dec     ecx
        jmp     .loop
.done:  mov     [obuf_pos], ecx
        ret

;; =====================================================================
;; ob_putc: append byte in AL to output buffer, flush if full
;; =====================================================================

ob_putc:
        push    rcx
        push    rdx
        mov     ecx, [obuf_pos]
        mov     [obuf + rcx], al
        inc     ecx
        mov     [obuf_pos], ecx
        cmp     ecx, OBUF_SZ
        jl      .no_flush
        call    ob_flush
.no_flush:
        pop     rdx
        pop     rcx
        ret

;; =====================================================================
;; ob_flush: write output buffer to stdout
;; =====================================================================

ob_flush:
        push    rdi
        push    rsi
        push    rdx
        push    rax

        mov     edx, [obuf_pos]
        test    edx, edx
        jz      .empty

        ;; Write in a loop (short writes possible)
        lea     rsi, [obuf]
        xor     r8d, r8d               ; bytes written so far
.write_loop:
        mov     edi, STDOUT
        lea     rsi, [obuf + r8]
        mov     edx, [obuf_pos]
        sub     edx, r8d
        mov     eax, SYS_WRITE
        syscall
        test    rax, rax
        jle     .empty                 ; error or zero — bail
        add     r8d, eax
        cmp     r8d, [obuf_pos]
        jl      .write_loop

        mov     dword [obuf_pos], 0
.empty:
        pop     rax
        pop     rdx
        pop     rsi
        pop     rdi
        ret

;; =====================================================================
;; brk helpers
;; =====================================================================

brk_current:
        xor     edi, edi
        mov     eax, SYS_BRK
        syscall
        ret

brk_set:
        mov     eax, SYS_BRK
        syscall
        ret

;; =====================================================================
;; Data
;; =====================================================================

err_open        db 'ffpp: cannot open file', 10
err_open_len    = $ - err_open

err_depth       db 'ffpp: include nesting too deep', 10
err_depth_len   = $ - err_depth

;; =====================================================================
;; BSS (uninitialized)
;; =====================================================================

obuf            rb OBUF_SZ
obuf_pos        dd 0
prev_was_ws     db 0
prev_was_nl     db 0
depth           dd 0
pbuf            rb PBUF_SZ
inc_stack       rb MAX_DEPTH * FRAME_SZ
