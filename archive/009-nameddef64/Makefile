nameddef64: nameddef64.asm
	fasm nameddef64.asm nameddef64.o
	ld -m elf_x86_64 -o nameddef64 nameddef64.o

clean:
	rm -f nameddef64 nameddef64.o

test: nameddef64
	@echo -n "009-nameddef64: "; PASS=true; \
	T() { GOT=$$(echo "$$1" | ./nameddef64 2>&1 | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -s ' \n' ' ' | xargs); \
	      if [ "$$GOT" != "$$2" ]; then echo "FAIL: '$$GOT' != '$$2'"; PASS=false; fi; }; \
	T ': square dup * ; 5 square . cr ;' '25'; \
	T ': cube dup dup * * ; 4 cube . cr ;' '64'; \
	T ': square dup * ; : quad square square ; 3 quad . cr ;' '81'; \
	T ': double dup + ; 5 double . cr ;' '10'; \
	T ': double dup + ; -3 double . cr ;' '-6'; \
	$$PASS && echo "PASS"

.PHONY: clean test
