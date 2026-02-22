memory64: memory64.asm
	fasm memory64.asm memory64.o
	ld -m elf_x86_64 -o memory64 memory64.o

clean:
	rm -f memory64 memory64.o

test: memory64
	@echo -n "011-memory64: "; PASS=true; \
	T() { GOT=$$(echo "$$1" | ./memory64 2>&1 | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -s ' \n' ' ' | xargs); \
	      if [ "$$GOT" != "$$2" ]; then echo "FAIL: '$$GOT' != '$$2'"; PASS=false; fi; }; \
	T '10 3 / . cr ;' '3'; \
	T '10 3 mod . cr ;' '1'; \
	T '10 3 /mod . . cr ;' '3 1'; \
	T '$$FF $$0F and . cr ;' '15'; \
	T '$$F0 $$0F or . cr ;' '255'; \
	T '$$FF $$0F xor . cr ;' '240'; \
	T '1 8 lshift . cr ;' '256'; \
	T '256 2 rshift . cr ;' '64'; \
	T '1 2 3 rot . . . cr ;' '1 3 2'; \
	T '1 2 tuck . . . cr ;' '2 1 2'; \
	T 'here dup 42 swap ! here @ . cr ;' '42'; \
	T 'here dup $$41 swap c! c@ . cr ;' '65'; \
	T ': fact dup 1 > IF dup 1 - fact * THEN ; 10 fact . cr ;' '3628800'; \
	T '( this is a comment ) 3 4 + . cr ;' '7'; \
	$$PASS && echo "PASS"

.PHONY: clean test
