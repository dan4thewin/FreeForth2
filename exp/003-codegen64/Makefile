all: codegen64

codegen64.o: codegen64.asm
	fasm $< $@

codegen64: codegen64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f codegen64 codegen64.o

test: codegen64
	@echo -n "003-codegen64: "
	@./codegen64 | grep -q "42" && echo "PASS" || echo "FAIL"

.PHONY: all clean test
