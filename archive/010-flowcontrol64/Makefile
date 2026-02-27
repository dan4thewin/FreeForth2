nameddef64: nameddef64.asm
	fasm nameddef64.asm nameddef64.o
	ld -m elf_x86_64 -o nameddef64 nameddef64.o

clean:
	rm -f nameddef64 nameddef64.o

test: nameddef64
	@echo -n "010-flowcontrol64: "; PASS=true; \
	T() { GOT=$$(echo "$$1" | ./nameddef64 2>&1 | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -s ' \n' ' ' | xargs); \
	      if [ "$$GOT" != "$$2" ]; then echo "FAIL: '$$GOT' != '$$2'"; PASS=false; fi; }; \
	T ': abs dup 0< IF negate THEN ; -42 abs . cr ;' '42'; \
	T ': abs dup 0< IF negate THEN ; 42 abs . cr ;' '42'; \
	T ': max over over < IF swap THEN drop ; 3 7 max . cr ;' '7'; \
	T ': fact dup 1 > IF dup 1 - fact * THEN ; 5 fact . cr ;' '120'; \
	T ': fact dup 1 > IF dup 1 - fact * THEN ; 10 fact . cr ;' '3628800'; \
	T ': recsum dup 1 > IF dup 1 - recsum + THEN ; 3 recsum . cr ;' '6'; \
	T ': recsum dup 1 > IF dup 1 - recsum + THEN ; 10 recsum . cr ;' '55'; \
	T ': fib dup 1 > IF dup 1 - fib swap 2 - fib + THEN ; 10 fib . cr ;' '55'; \
	T ': countdown BEGIN dup . cr 1 - dup 0= UNTIL drop ; 3 countdown ;' '3 2 1'; \
	$$PASS && echo "PASS"

.PHONY: clean test
