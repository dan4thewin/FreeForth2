;;; hello.asm — Minimal static ELF64 via FASM
;;; Proves format ELF64 executable 3 works with no linker, no libc.

format ELF64 executable 3
entry _start

segment readable executable

_start:
        ;; sys_write(1, msg, msglen)
        mov rax, 1              ; sys_write
        mov rdi, 1              ; fd = stdout
        lea rsi, [msg]
        mov rdx, msglen
        syscall

        ;; sys_exit(0)
        mov rax, 60             ; sys_exit
        xor rdi, rdi
        syscall

segment readable

msg     db 'Hello from static ELF64!', 10
msglen  = $ - msg
