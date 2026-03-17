;;; 001-hello64: Minimal x86-64 Linux binary
;;; Proves: fasm produces x86-64 ELF, syscall instruction works
;;; Expected output: Hello, 64-bit FreeForth2!

format elf64
section '.text' executable
public _start

_start:
        ;; write(stdout, msg, len)
        ;; x86-64 syscall: rax=syscall#, rdi=arg1, rsi=arg2, rdx=arg3
        mov rax, 1              ; syscall: write
        mov rdi, 1              ; fd: stdout
        lea rsi, [msg]          ; buf: message
        mov rdx, len            ; count: length
        syscall

        ;; exit(0)
        mov rax, 60             ; syscall: exit
        xor rdi, rdi            ; status: 0
        syscall

section '.data' writeable
msg     db "Hello, 64-bit FreeForth2!", 10
len = $ - msg
