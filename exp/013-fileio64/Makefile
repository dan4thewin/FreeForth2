fileio64: fileio64.asm
	fasm fileio64.asm fileio64.o
	ld -m elf_x86_64 -o fileio64 fileio64.o

clean:
	rm -f fileio64 fileio64.o

test: fileio64
	@echo -n "013-fileio64: "; PASS=true; \
	T() { GOT=$$(echo "$$1" | ./fileio64 2>&1 | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -s ' \n' ' ' | xargs); \
	      if [ "$$GOT" != "$$2" ]; then echo "FAIL: '$$GOT' != '$$2'"; PASS=false; fi; }; \
	T 'include test.ff 5 square . cr ;' '25'; \
	T 'include test.ff 3 cube . cr ;' '27'; \
	T 'include test.ff greet ;' 'Hello from file!'; \
	T 'include main.ff' '42 7 3'; \
	T 'include nonexistent.ff 3 4 + . cr ;' 'error: cannot open file 7'; \
	$$PASS && echo "PASS"

.PHONY: clean test
