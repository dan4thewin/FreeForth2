all: hello64

hello64.o: hello64.asm
	fasm $< $@

hello64: hello64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f hello64 hello64.o

test: hello64
	@echo -n "001-hello64: "
	@./hello64 | grep -q "Hello, 64-bit FreeForth2!" && echo "PASS" || echo "FAIL"

.PHONY: all clean test
