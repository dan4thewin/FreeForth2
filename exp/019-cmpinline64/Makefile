.PHONY: all clean test

all: cmpinline64

cmpinline64: cmpinline64.o
	ld -m elf_x86_64 -o $@ $<

cmpinline64.o: cmpinline64.asm
	fasm $< $@

clean:
	rm -f cmpinline64 cmpinline64.o

# Tests for inline comparisons: = < > 0= 0<>
# Plus regressions for all previously-inlined primitives
test: cmpinline64
	@echo "=== 019-cmpinline64 ==="
	@printf '%s\n' \
	  '3 3 = . cr ;' \
	  '3 4 = . cr ;' \
	  '3 4 < . cr ;' \
	  '4 3 < . cr ;' \
	  '4 3 > . cr ;' \
	  '3 4 > . cr ;' \
	  '0 0= . cr ;' \
	  '5 0= . cr ;' \
	  '0 0<> . cr ;' \
	  '5 0<> . cr ;' \
	  ': abs dup 0< IF negate THEN ; -5 abs . cr ;' \
	  ': max over over < IF swap THEN drop ; 3 10 max . cr ;' \
	  ': min over over > IF swap THEN drop ; 3 10 min . cr ;' \
	  ': fact dup 1 > IF dup 1 - fact * ELSE drop 1 THEN ; 10 fact . cr ;' \
	  ': fib dup 2 < IF ELSE dup 1 - fib swap 2 - fib + THEN ; 10 fib . cr ;' \
	  | ./cmpinline64 | sed 's/^> //;/^ok$$/d;/^>$$/d;s/ $$//' > /tmp/019_out.txt
	@printf '%s\n' '-1' '0' '-1' '0' '-1' '0' '-1' '0' '0' '-1' '5' '10' '3' '3628800' '55' \
	  > /tmp/019_exp.txt
	@diff -u /tmp/019_exp.txt /tmp/019_out.txt && echo "PASS" || echo "FAIL"
