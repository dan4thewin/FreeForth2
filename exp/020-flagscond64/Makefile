.PHONY: all clean test

all: flagscond64

flagscond64: flagscond64.o
	ld -m elf_x86_64 -o $@ $<

flagscond64.o: flagscond64.asm
	fasm $< $@

clean:
	rm -f flagscond64 flagscond64.o

# Tests for flags-based conditionals
# Tests exercise both the flags-based path (< > = etc. before IF)
# and the fallback path (boolean on stack, no condition set before IF)
test: flagscond64
	@echo "=== 020-flagscond64 ==="
	@printf '%s\n' \
	  ': abs 0- 0< IF negate THEN ; -5 abs . cr ;' \
	  ': abs 0- 0< IF negate THEN ; 5 abs . cr ;' \
	  ': min < IF swap THEN nip ; 3 10 min . cr ;' \
	  ': min < IF swap THEN nip ; 10 3 min . cr ;' \
	  ': max > IF swap THEN nip ; 3 10 max . cr ;' \
	  ': max > IF swap THEN nip ; 10 3 max . cr ;' \
	  ': fact dup 1 > drop nip IF dup 1 - fact * ELSE drop 1 THEN ; 10 fact . cr ;' \
	  ': fib dup 2 < drop nip IF ELSE dup 1 - fib swap 2 - fib + THEN ; 10 fib . cr ;' \
	  '3 3 =. . cr ;' \
	  '3 4 <. . cr ;' \
	  '4 3 >. . cr ;' \
	  '0 0=. . cr ;' \
	  '5 0<>. . cr ;' \
	  '-5 0<. . cr ;' \
	  ': t1 dup IF dup + THEN ; 0 t1 . cr ;' \
	  ': t1 dup IF dup + THEN ; 5 t1 . cr ;' \
	  '5 3 <= nip nip IF 99 ELSE 0 THEN . cr ;' \
	  '10 3 >= nip nip IF 77 ELSE 0 THEN . cr ;' \
	  ': countdown BEGIN dup . 1 - 0- 0= UNTIL drop ; 3 countdown cr ;' \
	  | ./flagscond64 | sed 's/^> //;/^ok$$/d;/^>$$/d;s/ $$//' > /tmp/020_out.txt
	@printf '%s\n' '5' '5' '3' '3' '10' '10' '3628800' '55' \
	  '-1' '-1' '-1' '-1' '-1' '-1' '0' '10' '0' '77' '3 2 1' \
	  > /tmp/020_exp.txt
	@diff -u /tmp/020_exp.txt /tmp/020_out.txt && echo "PASS" || echo "FAIL"
