all: stack64

stack64.o: stack64.asm
	fasm $< $@

stack64: stack64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f stack64 stack64.o

test: stack64
	./stack64
