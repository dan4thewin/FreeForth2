variables64: variables64.asm
	fasm variables64.asm variables64.o
	ld -m elf_x86_64 -o variables64 variables64.o

clean:
	rm -f variables64 variables64.o

test: variables64
	@echo -n "012-variables64: "; PASS=true; \
	T() { GOT=$$(echo "$$1" | ./variables64 2>&1 | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -s ' \n' ' ' | xargs); \
	      if [ "$$GOT" != "$$2" ]; then echo "FAIL: '$$GOT' != '$$2'"; PASS=false; fi; }; \
	T 'variable x 42 x ! x @ . cr ;' '42'; \
	T '42 constant answer answer . cr ;' '42'; \
	T 'variable c 0 c ! 1 c +! 1 c +! c @ . cr ;' '2'; \
	T '." Hello" cr ;' 'Hello'; \
	T ': fact dup 1 > IF dup 1 - fact * THEN ; 10 fact . cr ;' '3628800'; \
	$$PASS && echo "PASS"

.PHONY: clean test
