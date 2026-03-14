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
;;;   - [64]/[32]/[0]/[1] boolean markers with [IF]/[ELSE]/[THEN]
;;;   - [~] detected and rejected (requires Forth dictionary)
;;;   - ^V path includes (Ctrl-V, recursive, 8-level limit)
;;;   - Reads files from args or stdin if none given
;;;
;;; Build: fasm ffpp.asm ffpp
;;;
;;; Usage: ffpp [--64] [file ...]   (stdin if no args)
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
        mov     [flag_64], eax         ; --64 not set
        mov     [flag_debug], eax      ; --debug not set
        mov     [had_files], eax       ; no files processed yet
        mov     byte [prev_was_ws], 1  ; start as if prev was whitespace (BOF)
        mov     byte [prev_was_nl], 1  ; suppress leading blank lines

        ;; Scan args for flags; collect file args
        cmp     r12, 1
        jle     .do_stdin

        ;; First pass: find flags, process file args
        mov     r14, 1                 ; arg index (skip argv[0])
.arg_loop:
        cmp     r14, r12
        jge     .args_done
        mov     rdi, [r13 + r14*8]    ; argv[i]
        ;; Check for --64: '-','-','6','4',0
        cmp     byte [rdi], '-'
        jne     .arg_file
        cmp     byte [rdi+1], '-'
        jne     .arg_file
        cmp     byte [rdi+2], '6'
        jne     .try_debug_arg
        cmp     byte [rdi+3], '4'
        jne     .arg_file
        cmp     byte [rdi+4], 0
        jne     .arg_file
        mov     dword [flag_64], 1
        inc     r14
        jmp     .arg_loop
.try_debug_arg:
        ;; Check for --debug: '-','-','d','e','b','u','g',0
        cmp     byte [rdi+2], 'd'
        jne     .arg_file
        cmp     byte [rdi+3], 'e'
        jne     .arg_file
        cmp     byte [rdi+4], 'b'
        jne     .arg_file
        cmp     byte [rdi+5], 'u'
        jne     .arg_file
        cmp     byte [rdi+6], 'g'
        jne     .arg_file
        cmp     byte [rdi+7], 0
        jne     .arg_file
        mov     dword [flag_debug], 1
        inc     r14
        jmp     .arg_loop

.arg_file:
        mov     dword [had_files], 1
        call    process_file
        inc     r14
        jmp     .arg_loop

.args_done:
        ;; If no file args were processed (only flags), read stdin
        cmp     dword [had_files], 0
        jne     .done
        jmp     .do_stdin

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

        ;; Check for [ — possible conditional marker
        cmp     al, '['
        je      .maybe_bracket

        ;; Check for Ctrl-V (0x16) — include
        cmp     al, 0x16
        je      .maybe_include

        ;; Regular character — emit if not suppressing (or in passthru)
        cmp     dword [passthru], 0
        jne     .emit_char
        cmp     byte [suppressing], 0
        jne     .skip_char
.emit_char:
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
.skip_char:
        inc     r13
        jmp     .normal

        ;; ---- Newline handling ----
.got_newline:
        cmp     dword [passthru], 0
        jne     .emit_newline
        cmp     byte [suppressing], 0
        jne     .skip_newline          ; suppress newlines too
.emit_newline:
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
        cmp     dword [passthru], 0
        jne     .emit_space
        cmp     byte [suppressing], 0
        jne     .skip_space            ; suppress whitespace too
.emit_space:
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
        cmp     byte [suppressing], 0
        jne     .suppress_string       ; skip entire string in suppress mode
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

.suppress_string:
        ;; Skip entire string (including quotes) when suppressing
        inc     r13                    ; skip opening quote
.suppress_string_loop:
        cmp     r13, r12
        jge     .buf_done
        cmp     byte [rbp + r13], '"'
        je      .suppress_string_done
        inc     r13
        jmp     .suppress_string_loop
.suppress_string_done:
        inc     r13                    ; skip closing quote
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

        ;; ---- Include: Ctrl-V (0x16) ----
.maybe_include:
        ;; Must be preceded by whitespace (or BOF)
        cmp     byte [prev_was_ws], 0
        je      .not_include

        ;; Skip the Ctrl-V byte
        inc     r13

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

        ;; If suppressing, skip the include entirely
        cmp     byte [suppressing], 0
        jne     .normal

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
        ;; Emit Ctrl-V as regular byte
        mov     al, 0x16
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
        inc     r13
        jmp     .normal

        ;; ---- Bracket conditionals: [64] [32] [IF] [ELSE] [THEN] ----
.maybe_bracket:
        ;; [ is a marker only if preceded by whitespace
        cmp     byte [prev_was_ws], 0
        je      .bracket_literal

        ;; In passthru mode, only track [IF]/[THEN] nesting
        cmp     dword [passthru], 0
        jne     .passthru_bracket

        ;; Try matching [64], [32], [IF], [ELSE], [THEN]
        ;; All must end with ] followed by whitespace or EOF

        ;; Check [64] — need 3 more bytes: '6','4',']'
        lea     rcx, [r13 + 3]
        cmp     rcx, r12
        jg      .bracket_literal
        cmp     byte [rbp + r13 + 1], '6'
        jne     .try_32
        cmp     byte [rbp + r13 + 2], '4'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 3], ']'
        jne     .bracket_literal
        ;; Check followed by ws or EOF
        lea     rcx, [r13 + 4]
        cmp     rcx, r12
        jge     .got_64                ; EOF after ] is ok
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .got_64
        cmp     dl, 9
        je      .got_64
        cmp     dl, 10
        je      .got_64
        jmp     .bracket_literal       ; not followed by ws
.got_64:
        add     r13, 4                 ; skip [64]
        mov     eax, [flag_64]
        mov     [last_bool], eax
        jmp     .normal

.try_32:
        cmp     byte [rbp + r13 + 1], '3'
        jne     .try_0
        cmp     byte [rbp + r13 + 2], '2'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 3], ']'
        jne     .bracket_literal
        lea     rcx, [r13 + 4]
        cmp     rcx, r12
        jge     .got_32
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .got_32
        cmp     dl, 9
        je      .got_32
        cmp     dl, 10
        je      .got_32
        jmp     .bracket_literal
.got_32:
        add     r13, 4                 ; skip [32]
        mov     eax, [flag_64]
        xor     eax, 1                 ; invert
        mov     [last_bool], eax
        jmp     .normal

.try_0:
        ;; Check [0] — 3 bytes: '[','0',']'
        cmp     byte [rbp + r13 + 1], '0'
        jne     .try_1
        cmp     byte [rbp + r13 + 2], ']'
        jne     .bracket_literal
        lea     rcx, [r13 + 3]
        cmp     rcx, r12
        jge     .got_0
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .got_0
        cmp     dl, 9
        je      .got_0
        cmp     dl, 10
        je      .got_0
        jmp     .bracket_literal
.got_0:
        add     r13, 3                 ; skip [0]
        mov     dword [last_bool], 0
        jmp     .normal

.try_1:
        ;; Check [1] — 3 bytes: '[','1',']'
        cmp     byte [rbp + r13 + 1], '1'
        jne     .try_tilde
        cmp     byte [rbp + r13 + 2], ']'
        jne     .bracket_literal
        lea     rcx, [r13 + 3]
        cmp     rcx, r12
        jge     .got_1
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .got_1
        cmp     dl, 9
        je      .got_1
        cmp     dl, 10
        je      .got_1
        jmp     .bracket_literal
.got_1:
        add     r13, 3                 ; skip [1]
        mov     dword [last_bool], 1
        jmp     .normal

.try_tilde:
        ;; Check [DEBUG] — need 6 more bytes: 'D','E','B','U','G',']'
        cmp     byte [rbp + r13 + 1], 'D'
        jne     .try_tilde2
        lea     rcx, [r13 + 7]
        cmp     rcx, r12
        jg      .bracket_literal
        cmp     byte [rbp + r13 + 2], 'E'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 3], 'B'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 4], 'U'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 5], 'G'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 6], ']'
        jne     .bracket_literal
        lea     rcx, [r13 + 7]
        cmp     rcx, r12
        jge     .got_debug
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .got_debug
        cmp     dl, 9
        je      .got_debug
        cmp     dl, 10
        je      .got_debug
        jmp     .bracket_literal
.got_debug:
        add     r13, 7                 ; skip [DEBUG]
        mov     eax, [flag_debug]
        mov     [last_bool], eax
        jmp     .normal

.try_tilde2:
        ;; Check [~] — 3 bytes: '[','~',']'
        cmp     byte [rbp + r13 + 1], '~'
        jne     .try_if
        cmp     byte [rbp + r13 + 2], ']'
        jne     .bracket_literal
        lea     rcx, [r13 + 3]
        cmp     rcx, r12
        jge     .got_tilde
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .got_tilde
        cmp     dl, 9
        je      .got_tilde
        cmp     dl, 10
        je      .got_tilde
        jmp     .bracket_literal
.got_tilde:
        ;; [~] requires dictionary lookup — pass through to Forth compiler
        ;; If already suppressing, just skip [~] as literal text
        cmp     byte [suppressing], 0
        jne     .got_tilde_skip
        ;; Emit [~] literally and enter passthru mode: output everything
        ;; verbatim until the matching [THEN] is seen.
        mov     dword [passthru], 1
        mov     al, '['
        call    ob_putc
        mov     al, '~'
        call    ob_putc
        mov     al, ']'
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
        add     r13, 3
        jmp     .normal
.got_tilde_skip:
        ;; Suppressing — skip [~] as 3 bytes
        add     r13, 3
        jmp     .normal

        ;; ---- Passthru mode: emit bracket directives literally,
        ;;      but track [IF]/[THEN] nesting depth ----
.passthru_bracket:
        ;; Check for [IF] — increment nesting
        lea     rcx, [r13 + 3]
        cmp     rcx, r12
        jg      .passthru_emit
        cmp     byte [rbp + r13 + 1], 'I'
        jne     .passthru_try_then
        cmp     byte [rbp + r13 + 2], 'F'
        jne     .passthru_emit
        cmp     byte [rbp + r13 + 3], ']'
        jne     .passthru_emit
        lea     rcx, [r13 + 4]
        cmp     rcx, r12
        jge     .passthru_got_if
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .passthru_got_if
        cmp     dl, 9
        je      .passthru_got_if
        cmp     dl, 10
        je      .passthru_got_if
        jmp     .passthru_emit
.passthru_got_if:
        inc     dword [passthru]
        jmp     .passthru_emit

.passthru_try_then:
        ;; Check for [THEN] — decrement nesting, exit passthru at 0
        lea     rcx, [r13 + 5]
        cmp     rcx, r12
        jg      .passthru_emit
        cmp     byte [rbp + r13 + 1], 'T'
        jne     .passthru_emit
        cmp     byte [rbp + r13 + 2], 'H'
        jne     .passthru_emit
        cmp     byte [rbp + r13 + 3], 'E'
        jne     .passthru_emit
        cmp     byte [rbp + r13 + 4], 'N'
        jne     .passthru_emit
        cmp     byte [rbp + r13 + 5], ']'
        jne     .passthru_emit
        lea     rcx, [r13 + 6]
        cmp     rcx, r12
        jge     .passthru_got_then
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .passthru_got_then
        cmp     dl, 9
        je      .passthru_got_then
        cmp     dl, 10
        je      .passthru_got_then
        jmp     .passthru_emit
.passthru_got_then:
        dec     dword [passthru]
        cmp     dword [passthru], 0
        jne     .passthru_emit
        ;; Exiting passthru: emit the final [THEN] and resume normal
        mov     al, '['
        call    ob_putc
        mov     al, 'T'
        call    ob_putc
        mov     al, 'H'
        call    ob_putc
        mov     al, 'E'
        call    ob_putc
        mov     al, 'N'
        call    ob_putc
        mov     al, ']'
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
        add     r13, 6
        jmp     .normal

.passthru_emit:
        ;; Emit [ literally, let .normal handle the rest
        mov     al, '['
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
        inc     r13
        jmp     .normal

.try_if:
        ;; Check [IF] — need 3 more bytes: 'I','F',']'
        cmp     byte [rbp + r13 + 1], 'I'
        jne     .try_else
        cmp     byte [rbp + r13 + 2], 'F'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 3], ']'
        jne     .bracket_literal
        lea     rcx, [r13 + 4]
        cmp     rcx, r12
        jge     .got_if
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .got_if
        cmp     dl, 9
        je      .got_if
        cmp     dl, 10
        je      .got_if
        jmp     .bracket_literal
.got_if:
        add     r13, 4                 ; skip [IF]
        cmp     dword [last_bool], 0
        jne     .normal                ; condition true — keep emitting
        mov     byte [suppressing], 1
        jmp     .normal

.try_else:
        ;; Check [ELSE] — need 5 more bytes: 'E','L','S','E',']'
        lea     rcx, [r13 + 5]
        cmp     rcx, r12
        jg      .try_then
        cmp     byte [rbp + r13 + 1], 'E'
        jne     .try_then
        cmp     byte [rbp + r13 + 2], 'L'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 3], 'S'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 4], 'E'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 5], ']'
        jne     .bracket_literal
        lea     rcx, [r13 + 6]
        cmp     rcx, r12
        jge     .got_else
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .got_else
        cmp     dl, 9
        je      .got_else
        cmp     dl, 10
        je      .got_else
        jmp     .bracket_literal
.got_else:
        add     r13, 6                 ; skip [ELSE]
        xor     byte [suppressing], 1  ; toggle
        jmp     .normal

.try_then:
        ;; Check [THEN] — need 5 more bytes: 'T','H','E','N',']'
        lea     rcx, [r13 + 5]
        cmp     rcx, r12
        jg      .bracket_literal
        cmp     byte [rbp + r13 + 1], 'T'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 2], 'H'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 3], 'E'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 4], 'N'
        jne     .bracket_literal
        cmp     byte [rbp + r13 + 5], ']'
        jne     .bracket_literal
        lea     rcx, [r13 + 6]
        cmp     rcx, r12
        jge     .got_then
        movzx   edx, byte [rbp + rcx]
        cmp     dl, ' '
        je      .got_then
        cmp     dl, 9
        je      .got_then
        cmp     dl, 10
        je      .got_then
        jmp     .bracket_literal
.got_then:
        add     r13, 6                 ; skip [THEN]
        mov     byte [suppressing], 0
        jmp     .normal

.bracket_literal:
        ;; [ is not a marker — emit if not suppressing
        cmp     byte [suppressing], 0
        jne     .bracket_skip
        mov     al, '['
        call    ob_putc
        mov     byte [prev_was_ws], 0
        mov     byte [prev_was_nl], 0
.bracket_skip:
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

err_tilde       db 'ffpp: [~] requires dictionary lookup — not supported', 10
err_tilde_len   = $ - err_tilde

;; =====================================================================
;; BSS (uninitialized)
;; =====================================================================

obuf            rb OBUF_SZ
obuf_pos        dd 0
prev_was_ws     db 0
prev_was_nl     db 0
suppressing     db 0
flag_64         dd 0
flag_debug      dd 0
had_files       dd 0
last_bool       dd 0
passthru        dd 0
depth           dd 0
pbuf            rb PBUF_SZ
inc_stack       rb MAX_DEPTH * FRAME_SZ
