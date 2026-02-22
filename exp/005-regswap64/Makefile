all: regswap64

regswap64.o: regswap64.asm
	fasm $< $@

regswap64: regswap64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f regswap64 regswap64.o

test: regswap64
	./regswap64
