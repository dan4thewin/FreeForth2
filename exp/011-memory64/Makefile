memory64: memory64.asm
	fasm memory64.asm memory64.o
	ld -m elf_x86_64 -o memory64 memory64.o

clean:
	rm -f memory64 memory64.o

.PHONY: clean
