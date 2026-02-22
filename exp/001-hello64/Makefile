all: hello64

hello64.o: hello64.asm
	fasm $< $@

hello64: hello64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f hello64 hello64.o

test: hello64
	./hello64
