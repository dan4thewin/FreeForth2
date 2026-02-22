retstack64: retstack64.asm
	fasm retstack64.asm retstack64.o
	ld -m elf_x86_64 -o retstack64 retstack64.o

clean:
	rm -f retstack64 retstack64.o

test: retstack64
	@echo -n "014-retstack64: "; PASS=true; \
	T() { GOT=$$(echo "$$1" | ./retstack64 2>&1 | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -s ' \n' ' ' | xargs); \
	      if [ "$$GOT" != "$$2" ]; then echo "FAIL: '$$GOT' != '$$2'"; PASS=false; fi; }; \
	T '42 >r r> . cr ;' '42'; \
	T '42 >r r@ . r> drop cr ;' '42'; \
	T '$$41 emit $$42 emit $$43 emit cr ;' 'ABC'; \
	T ': fact dup 1 > IF dup 1 - fact * THEN ; 10 fact . cr ;' '3628800'; \
	T ': fib dup 1 > IF dup 1 - fib swap 2 - fib + THEN ; 10 fib . cr ;' '55'; \
	$$PASS && echo "PASS"

.PHONY: clean test
