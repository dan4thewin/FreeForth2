.PHONY: all clean test

all: litcomma64

litcomma64: litcomma64.o
	ld -m elf_x86_64 -o $@ $<

litcomma64.o: litcomma64.asm
	fasm $< $@

clean:
	rm -f litcomma64 litcomma64.o

# Tests for trailing-comma literal compiler and s01/s08/s09 exposure
#
# The trailing-comma syntax ($DA89,) emits code that writes bytes at [rbp]
# without advancing it. The s01/s08/s09 words advance rbp and apply SWAPbit.
# Together they enable Forth-defined inline code generators (backtick macros).
test: litcomma64
	@echo "=== 021-litcomma64 ==="
	@printf '%s\n' \
	  '1 2 + . cr ;' \
	  ': nipdup $$48, ,1 $$DA89, s09 ; here nipdup here 1 - c@ . here 2 - c@ . here 3 - c@ . cr ;' \
	  ': emit1 $$48, ,1 ; here emit1 here 1 - c@ . here swap - . cr ;' \
	  ': emit2 $$DA89, ,2 ; here emit2 here 1 - c@ . here 2 - c@ . here swap - . cr ;' \
	  ': emit4 $$04C38348, ,4 ; here emit4 here 1 - c@ . here 4 - c@ . here swap - . cr ;' \
	  | ./litcomma64 | sed 's/^> //;/^ok$$/d;/^>$$/d;s/ $$//' > /tmp/021_out.txt
	@printf '%s\n' \
	  '3' \
	  '218 137 72' \
	  '72 1' \
	  '218 137 2' \
	  '4 72 4' \
	  > /tmp/021_exp.txt
	@diff -u /tmp/021_exp.txt /tmp/021_out.txt && echo "PASS" || echo "FAIL"
