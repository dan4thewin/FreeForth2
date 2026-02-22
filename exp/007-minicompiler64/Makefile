all: minicompiler64

minicompiler64.o: minicompiler64.asm
	fasm $< $@

minicompiler64: minicompiler64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f minicompiler64 minicompiler64.o

test: minicompiler64
	./minicompiler64
