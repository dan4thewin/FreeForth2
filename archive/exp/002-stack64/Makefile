all: stack64

stack64.o: stack64.asm
	fasm $< $@

stack64: stack64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f stack64 stack64.o

EXPECTED = 30 20 10\n20 30 10\n30 20 10
test: stack64
	@echo -n "002-stack64: "
	@./stack64 > /tmp/test_002.out 2>&1
	@printf '$(EXPECTED)\n' | diff -q - /tmp/test_002.out > /dev/null 2>&1 && echo "PASS" || echo "FAIL"
	@rm -f /tmp/test_002.out

.PHONY: all clean test
