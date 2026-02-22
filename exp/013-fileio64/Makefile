fileio64: fileio64.asm
	fasm fileio64.asm fileio64.o
	ld -m elf_x86_64 -o fileio64 fileio64.o

clean:
	rm -f fileio64 fileio64.o

.PHONY: clean
