all: minicompiler64

minicompiler64.o: minicompiler64.asm
	fasm $< $@

minicompiler64: minicompiler64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f minicompiler64 minicompiler64.o

test: minicompiler64
	@echo -n "007-minicompiler64: "
	@OUT=$$(./minicompiler64); \
	echo "$$OUT" | head -1 | grep -q "7" && \
	echo "$$OUT" | tail -1 | grep -q "42" && echo "PASS" || echo "FAIL"

.PHONY: all clean test
