.PHONY: all clean test

all: moreinline64

moreinline64: moreinline64.o
	ld -m elf_x86_64 -o $@ $<

moreinline64.o: moreinline64.asm
	fasm $< $@

clean:
	rm -f moreinline64 moreinline64.o

# Tests cover: and, or, xor, @, c@, 0<, rot, tuck
# Plus regressions for all previously-inlined primitives
test: moreinline64
	@echo "=== 018-moreinline64 ==="
	@printf '%s\n' \
	  '3 4 + . cr ;' \
	  '3 10 swap - . cr ;' \
	  '$$FF $$0F and . cr ;' \
	  '$$F0 $$0F or . cr ;' \
	  '$$FF $$F0 xor . cr ;' \
	  'variable x 42 x ! x @ . cr ;' \
	  '-5 0< . cr ;' \
	  '5 0< . cr ;' \
	  '1 2 3 rot . . . cr ;' \
	  '3 4 tuck . . . cr ;' \
	  ': square dup * ; 7 square . cr ;' \
	  ': abs dup 0< IF negate THEN ; -5 abs . cr ;' \
	  ': fact dup 1 > IF dup 1 - fact * ELSE drop 1 THEN ; 5 fact . cr ;' \
	  ': fib dup 2 < IF ELSE dup 1 - fib swap 2 - fib + THEN ; 10 fib . cr ;' \
	  | ./moreinline64 | sed 's/^> //;/^ok$$/d;/^>$$/d;s/ $$//' > /tmp/018_out.txt
	@printf '%s\n' '7' '7' '15' '255' '15' '42' '-1' '0' '1 3 2' '4 3 4' '49' '5' '120' '55' \
	  > /tmp/018_exp.txt
	@diff -u /tmp/018_exp.txt /tmp/018_out.txt && echo "PASS" || echo "FAIL"
