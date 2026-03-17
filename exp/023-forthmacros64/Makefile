ASM = forthmacros64.asm
BIN = forthmacros64
OBJ = forthmacros64.o
TMP = /tmp/ff-023.ff

all: $(BIN)

$(BIN): $(ASM)
	fasm $(ASM) $(OBJ) && ld -o $(BIN) $(OBJ)

test: $(BIN)
	@echo "=== 023-forthmacros64 ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1"; local input="$$2"; local expected="$$3"; \
		cat macros.ff > $(TMP); printf '%s\n' "$$input" >> $(TMP); \
		actual=$$(./$(BIN) < $(TMP) 2>/dev/null | sed '/^> ok$$/d;/^ok$$/d;/^> *$$/d;s/^> //' | tr -d '\n' | sed 's/ *$$//'); \
		if [ "$$actual" = "$$expected" ]; then \
			PASS=$$((PASS+1)); \
		else \
			echo "FAIL: $$desc"; \
			echo "  input:    $$input"; \
			echo "  expected: [$$expected]"; \
			echo "  actual:   [$$actual]"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "dup" \
		": t dup ; 42 t . . cr ;" "42 42"; \
	run_test "drop" \
		": t drop ; 10 20 t . cr ;" "10"; \
	run_test "over" \
		": t over ; 10 20 t . . . cr ;" "10 20 10"; \
	run_test "swap" \
		": t swap ; 10 20 t . . cr ;" "10 20"; \
	run_test "nip" \
		": t nip ; 10 20 t . cr ;" "20"; \
	run_test "tuck" \
		": t tuck ; 10 20 t . . . cr ;" "20 10 20"; \
	run_test "add" \
		": t + ; 21 21 t . cr ;" "42"; \
	run_test "sub" \
		": t - ; 50 8 t . cr ;" "42"; \
	run_test "mul" \
		": t * ; 6 7 t . cr ;" "42"; \
	run_test "and" \
		": t and ; \$$FF \$$0F t . cr ;" "15"; \
	run_test "or" \
		": t or ; \$$30 \$$0F t . cr ;" "63"; \
	run_test "xor" \
		": t xor ; \$$FF \$$FF t . cr ;" "0"; \
	run_test "negate" \
		": t negate ; 42 t . cr ;" "-42"; \
	run_test "not (bitwise)" \
		": t ~ ; 0 t 1 + . cr ;" "0"; \
	run_test "1+" \
		": t 1 + ; 41 t . cr ;" "42"; \
	run_test "1-" \
		": t 1 - ; 43 t . cr ;" "42"; \
	run_test "fetch @" \
		"variable x 42 x ! x : t @ ; t . cr ;" "42"; \
	run_test "cfetch c@" \
		"variable x 65 x c! x : t c@ ; t . cr ;" "65"; \
	run_test "over+" \
		": t over + ; 10 20 t . . cr ;" "30 10"; \
	run_test "composition: abs" \
		": abs dup 0< IF negate THEN ; 0 42 - abs . cr ;" "42"; \
	run_test "composition: max" \
		": mymax over over > IF swap THEN nip ; 10 20 mymax . cr ;" "20"; \
	run_test "SWAPbit: swap dup" \
		": t swap dup ; 10 20 t . . . cr ;" "10 10 20"; \
	run_test "deep chain: 2dup+" \
		": 2dup+ over over + ; 3 4 2dup+ . . . cr ;" "7 4 3"; \
	if [ $$FAIL -eq 0 ]; then echo "PASS"; else echo "$$FAIL FAILED"; exit 1; fi

clean:
	rm -f $(TMP)
	rm -f $(BIN) $(OBJ)

.PHONY: all test clean
