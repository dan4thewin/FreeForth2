all: subrthread64

subrthread64.o: subrthread64.asm
	fasm $< $@

subrthread64: subrthread64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f subrthread64 subrthread64.o

test: subrthread64
	@echo -n "004-subrthread64: "
	@./subrthread64 | grep -q "42" && echo "PASS" || echo "FAIL"

.PHONY: all clean test
