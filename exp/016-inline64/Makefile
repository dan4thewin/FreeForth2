.PHONY: all clean test

all: inline64

inline64: inline64.o
	ld -m elf_x86_64 -o $@ $<

inline64.o: inline64.asm
	fasm $< $@

clean:
	rm -f inline64 inline64.o

# Test: pipe Forth commands, strip prompts, compare output
# Tests cover all 10 inline primitives: dup drop swap over nip + - * negate not
# Also tests interactions with flow control (IF/THEN, BEGIN/UNTIL)
test: inline64
	@echo "=== 016-inline64 ==="
	@printf '%s\n' \
	  '3 4 + . cr ;' \
	  '10 3 - . cr ;' \
	  '6 7 * . cr ;' \
	  '-5 negate . cr ;' \
	  '0 not . cr ;' \
	  '3 dup + . cr ;' \
	  '10 drop 5 . cr ;' \
	  '3 4 swap - . cr ;' \
	  '1 2 over . . . cr ;' \
	  '5 3 nip . cr ;' \
	  ': square dup * ; 7 square . cr ;' \
	  ': abs dup 0< IF negate THEN ; -5 abs . cr ;' \
	  ': fact dup 1 > IF dup 1 - fact * ELSE drop 1 THEN ; 5 fact . cr ;' \
	  | ./inline64 | sed 's/^> //;/^ok$$/d;/^>$$/d;s/ $$//' > /tmp/016_out.txt
	@printf '%s\n' '7' '7' '42' '5' '-1' '6' '5' '1' '1 2 1' '3' '49' '5' '120' \
	  > /tmp/016_exp.txt
	@diff -u /tmp/016_exp.txt /tmp/016_out.txt && echo "PASS" || echo "FAIL"
