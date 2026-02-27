.PHONY: all clean test

all: swapdeep64

swapdeep64: swapdeep64.o
	ld -m elf_x86_64 -o $@ $<

swapdeep64.o: swapdeep64.asm
	fasm $< $@

clean:
	rm -f swapdeep64 swapdeep64.o

# Test: verify SWAPbit-aware inline code generation
# Key tests:
#   - swap emits zero code (tested by combining with +, -, etc.)
#   - swap+swap cancels out
#   - swap interacts correctly with non-commutative ops (-)
#   - flow control works after swap (IF syncs via _rst)
test: swapdeep64
	@echo "=== 017-swapbit-deep ==="
	@printf '%s\n' \
	  '3 4 + . cr ;' \
	  '3 4 swap + . cr ;' \
	  '10 3 - . cr ;' \
	  '3 10 swap - . cr ;' \
	  '6 7 * . cr ;' \
	  '-5 negate . cr ;' \
	  '0 not . cr ;' \
	  '3 dup + . cr ;' \
	  '10 drop 5 . cr ;' \
	  '5 3 nip . cr ;' \
	  '1 2 over . . . cr ;' \
	  '3 4 swap swap - . cr ;' \
	  ': square dup * ; 7 square . cr ;' \
	  ': abs dup 0< IF negate THEN ; -5 abs . cr ;' \
	  ': swaptest swap - ; 3 10 swaptest . cr ;' \
	  ': fact dup 1 > IF dup 1 - fact * ELSE drop 1 THEN ; 5 fact . cr ;' \
	  | ./swapdeep64 | sed 's/^> //;/^ok$$/d;/^>$$/d;s/ $$//' > /tmp/017_out.txt
	@printf '%s\n' '7' '7' '7' '7' '42' '5' '-1' '6' '5' '3' '1 2 1' '-1' '49' '5' '7' '120' \
	  > /tmp/017_exp.txt
	@diff -u /tmp/017_exp.txt /tmp/017_out.txt && echo "PASS" || echo "FAIL"
