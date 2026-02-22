interactive64: interactive64.asm
	fasm interactive64.asm interactive64.o
	ld -m elf_x86_64 -o interactive64 interactive64.o

clean:
	rm -f interactive64 interactive64.o

# Helper: pipe input, strip prompts/ok, compare output
# Usage: echo "input" | ./interactive64 → extract numeric output lines
test: interactive64
	@echo -n "008-interactive64: "; PASS=true; \
	T() { GOT=$$(echo "$$1" | ./interactive64 2>&1 | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -s ' \n' ' ' | xargs); \
	      if [ "$$GOT" != "$$2" ]; then echo "FAIL: '$$GOT' != '$$2'"; PASS=false; fi; }; \
	T '3 4 + . cr ;' '7'; \
	T '$$FF . cr ;' '255'; \
	T '5 dup * . cr ;' '25'; \
	T '-42 . cr ;' '-42'; \
	$$PASS && echo "PASS"

.PHONY: clean test
