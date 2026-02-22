;;; 006-headers64: Dictionary headers and FIND
;;; Proves: FreeForth's header structure and word lookup work on x86-64
;;;         with 8-byte cells (xt field is now 8 bytes).
;;;
;;; FreeForth header structure (i386):
;;;   offset 0: 4 bytes: xt (code/data pointer or constant value)
;;;   offset 4: 1 byte:  ct (type: 0=code, 1=data, $21=constant)
;;;   offset 5: 1 byte:  name length
;;;   offset 6: N bytes: name string
;;;   offset 6+N: 1 byte: zero terminator
;;;
;;; For x86-64, xt becomes 8 bytes:
;;;   offset 0: 8 bytes: xt
;;;   offset 8: 1 byte:  ct
;;;   offset 9: 1 byte:  name length
;;;   offset 10: N bytes: name string
;;;   offset 10+N: 1 byte: zero terminator
;;;
;;; Headers grow BACKWARDS in memory (high to low).
;;; H points to the newest (lowest-address) header.
;;; To traverse: add h.nm + name_length + 1 to get the next header.
;;;
;;; Test:
;;;   1. Build a small dictionary with 3 words: "dup", "drop", "swap"
;;;   2. Look up "drop" — should find it and return its xt
;;;   3. Look up "bogus" — should fail
;;;   4. Print results
;;;
;;; Expected output:
;;;   found:1
;;;   xt:222
;;;   notfound:1

format elf64
section '.flat' writeable executable
public _start

h.ct = 8
h.sz = 9
h.nm = 10

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

;; --- Header generation macros (for fasm, not runtime) ---
;; These mirror FreeForth's WORD/GENWORDS but for 64-bit

macro WORD64 name, xt_val, ct_val {
    macro GENWORDS64 \{
        local .str, .eostr
        dq xt_val               ; 8-byte xt
        db ct_val               ; ct
        db .eostr - .str        ; name length
    .str:
        db name                 ; name
    .eostr:
        db 0                    ; zero terminator
        GENWORDS64
    \}
}

macro GENWORDS64 {
        dq 0                    ; sentinel xt
        db -1                   ; sentinel ct
        db 0                    ; zero length = end
        db 0                    ; zero terminator
}

;; Define some words (in reverse order — last defined is first in memory)
WORD64 "swap", 333, 0
WORD64 "drop", 222, 0
WORD64 "dup",  111, 0

;; --- FIND: search dictionary ---
;; Input: rdx = string address, rbx = string length
;; Output: if found: rdx = xt, rbx = 0, ZF set
;;         if not found: rdx, rbx unchanged, ZF clear
;; Clobbers: rsi, rcx, rdi

H       dq 0                    ; will be set to heads64 at startup

_find:  mov rsi, [H]
.b:     lea rsi, [rsi + h.nm]   ; skip to name
        movzx ecx, byte [rsi-1] ; ecx = name length
        jecxz .e                ; zero length = end of headers
        cmp rcx, rbx            ; lengths match?
        jnz .skip
        mov rdi, rdx            ; rdi = search string
        push rsi
        push rcx
        repz cmpsb              ; compare names
        pop rcx
        pop rsi
        jz .found
.skip:  lea rsi, [rsi + rcx + 1] ; skip name + zero terminator
        jmp .b
.found: lea rsi, [rsi - h.nm]   ; back to header start
        mov rdx, [rsi]          ; rdx = xt
        xor ebx, ebx            ; rbx = 0 (found)
.e:     ret

;; --- Print helpers ---
print_num:
        mov rax, rbx
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
        lea rdx, [numbuf+20]
        sub rdx, rdi
        mov rsi, rdi
        mov rax, 1
        mov rdi, 1
        syscall
        pop rdx
        pop r15
        ret

print_str:  ; rsi=addr, rdx=len
        mov rax, 1
        mov rdi, 1
        syscall
        ret

_start:
        lea r15, [dstack_top]
        xor ebx, ebx
        xor edx, edx

        ;; Initialize H to point at the generated headers
        lea rax, [heads64]
        mov [H], rax

        ;; --- Test 1: find "drop" ---
        lea rsi, [s_found]
        mov rdx, 6              ; "found:"
        call print_str

        ;; Set up stack for find: rdx=addr, rbx=length
        lea rdx, [search_drop]
        mov rbx, 4              ; length of "drop"
        call _find

        ;; rbx should be 0 (found). Print !rbx (1 if found)
        test rbx, rbx
        setz bl
        movzx rbx, bl
        call print_num

        ;; Print newline
        lea rsi, [nl]
        mov rdx, 1
        call print_str

        ;; --- Print the xt value ---
        lea rsi, [s_xt]
        mov edx, 3              ; "xt:"
        push rdx                ; save xt across print_str (rdx = xt from find)
        ;; wait, rdx was overwritten by print_str len. Let me restructure.

        ;; Re-find to get xt cleanly
        lea rdx, [search_drop]
        mov rbx, 4
        call _find              ; rdx = xt (222), rbx = 0

        push rdx                ; save xt
        lea rsi, [s_xt]
        mov rdx, 3
        call print_str
        pop rbx                 ; rbx = xt for printing
        call print_num
        lea rsi, [nl]
        mov rdx, 1
        call print_str

        ;; --- Test 2: find "bogus" (should fail) ---
        lea rsi, [s_notfound]
        mov rdx, 9              ; "notfound:"
        call print_str

        lea rdx, [search_bogus]
        mov rbx, 5
        call _find              ; should NOT find it, rbx stays 5

        ;; rbx != 0 means not found. Print 1 if not found.
        test rbx, rbx
        setnz bl
        movzx rbx, bl
        call print_num
        lea rsi, [nl]
        mov rdx, 1
        call print_str

        mov rax, 60
        xor rdi, rdi
        syscall

;; --- Data ---
search_drop  db "drop"
search_bogus db "bogus"
s_found      db "found:"
s_xt         db "xt:"
s_notfound   db "notfound:"
nl           db 10

        align 8
heads64: GENWORDS64              ; generates all headers

numbuf  rb 21
dstack  rb 8192
dstack_top:
