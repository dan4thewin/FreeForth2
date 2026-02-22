variables64: variables64.asm
	fasm variables64.asm variables64.o
	ld -m elf_x86_64 -o variables64 variables64.o

clean:
	rm -f variables64 variables64.o

.PHONY: clean
