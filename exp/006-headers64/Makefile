all: headers64

headers64.o: headers64.asm
	fasm $< $@

headers64: headers64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f headers64 headers64.o

test: headers64
	./headers64
