all: subrthread64

subrthread64.o: subrthread64.asm
	fasm $< $@

subrthread64: subrthread64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f subrthread64 subrthread64.o

test: subrthread64
	./subrthread64
