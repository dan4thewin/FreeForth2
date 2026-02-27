swapbit64: swapbit64.asm
	fasm swapbit64.asm swapbit64.o
	ld -m elf_x86_64 -o swapbit64 swapbit64.o

clean:
	rm -f swapbit64 swapbit64.o

test: swapbit64
	@echo -n "015-swapbit64: "; PASS=true; \
	T() { GOT=$$(echo "$$1" | ./swapbit64 2>&1 | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -s ' \n' ' ' | xargs); \
	      if [ "$$GOT" != "$$2" ]; then echo "FAIL: '$$GOT' != '$$2'"; PASS=false; fi; }; \
	T '3 4 + . cr ;' '7'; \
	T '6 7 * . cr ;' '42'; \
	T 'variable x 42 x ! x @ . cr ;' '42'; \
	T '42 constant answer answer . cr ;' '42'; \
	T '." hello" cr ;' 'hello'; \
	T ': fact dup 1 > IF dup 1 - fact * THEN ; 10 fact . cr ;' '3628800'; \
	T ': fib dup 1 > IF dup 1 - fib swap 2 - fib + THEN ; 10 fib . cr ;' '55'; \
	T ': recsum dup 1 > IF dup 1 - recsum + THEN ; 10 recsum . cr ;' '55'; \
	T '42 >r r> . cr ;' '42'; \
	T '$$41 emit $$42 emit cr ;' 'AB'; \
	$$PASS && echo "PASS"

.PHONY: clean test
