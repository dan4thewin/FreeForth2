retstack64: retstack64.asm
	fasm retstack64.asm retstack64.o
	ld -m elf_x86_64 -o retstack64 retstack64.o

clean:
	rm -f retstack64 retstack64.o

.PHONY: clean
