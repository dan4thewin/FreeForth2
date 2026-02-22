swapbit64: swapbit64.asm
	fasm swapbit64.asm swapbit64.o
	ld -m elf_x86_64 -o swapbit64 swapbit64.o

clean:
	rm -f swapbit64 swapbit64.o

.PHONY: clean
