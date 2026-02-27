all: headers64

headers64.o: headers64.asm
	fasm $< $@

headers64: headers64.o
	ld -m elf_x86_64 -o $@ $<

clean:
	rm -f headers64 headers64.o

test: headers64
	@echo -n "006-headers64: "
	@OUT=$$(./headers64); \
	echo "$$OUT" | grep -q "found:1" && \
	echo "$$OUT" | grep -q "notfound:1" && echo "PASS" || echo "FAIL"

.PHONY: all clean test
