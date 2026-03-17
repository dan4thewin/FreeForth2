ASM = moremacros64.asm
BIN = moremacros64
OBJ = moremacros64.o
TMP = /tmp/ff-024.ff

all: $(BIN)

$(BIN): $(ASM)
	fasm $(ASM) $(OBJ) && ld -o $(BIN) $(OBJ)

test: $(BIN)
	@echo "=== 024-moremacros64 ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1"; local input="$$2"; local expected="$$3"; \
		cat macros.ff > $(TMP); printf '%s\n' "$$input" >> $(TMP); \
		actual=$$(./$(BIN) < $(TMP) 2>/dev/null | sed '/^> ok$$/d;/^ok$$/d;/^> *$$/d;s/^> //' | tr -d '\n' | sed 's/ *$$//'); \
		if [ "$$actual" = "$$expected" ]; then \
			PASS=$$((PASS+1)); \
		else \
			echo "FAIL: $$desc"; \
			echo "  expected: [$$expected]"; \
			echo "  actual:   [$$actual]"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "store !" \
		"variable x 42 x ! x @ . cr ;" "42"; \
	run_test "byte store c!" \
		"variable x 65 x c! x c@ . cr ;" "65"; \
	run_test "add-store +!" \
		"variable x 10 x ! 32 x +! x @ . cr ;" "42"; \
	run_test "sub-store -!" \
		"variable x 50 x ! 8 x -! x @ . cr ;" "42"; \
	run_test "2dup! preserves stack" \
		"variable x 99 x 2dup! drop drop x @ . cr ;" "99"; \
	run_test ">r r>" \
		": t >r 1 r> + ; 41 t . cr ;" "42"; \
	run_test "dup>r r>" \
		": t dup>r 1 + r> + ; 20 t . cr ;" "41"; \
	run_test "r-fetch" \
		": t >r r@ r> + ; 21 t . cr ;" "42"; \
	run_test "rot" \
		": t rot ; 1 2 3 t . . . cr ;" "1 3 2"; \
	run_test "-rot" \
		": t -rot ; 1 2 3 t . . . cr ;" "2 1 3"; \
	run_test "rot -rot identity" \
		": t rot -rot ; 10 20 30 t . . . cr ;" "30 20 10"; \
	run_test "left shift" \
		": t << ; 1 4 t . cr ;" "16"; \
	run_test "right shift" \
		": t >> ; 256 4 t . cr ;" "16"; \
	run_test "here allot" \
		": t here 8 allot here swap - ; t . cr ;" "8"; \
	run_test "tuck" \
		": t tuck ; 10 20 t . . . cr ;" "20 10 20"; \
	run_test "2dup" \
		": t 2dup ; 10 20 t . . . . cr ;" "20 10 20 10"; \
	run_test "2swap via rot >r rot r>" \
		": t rot >r rot r> ; 1 2 3 4 t . . . . cr ;" "2 1 4 3"; \
	run_test "composition: nip via swap drop" \
		": t swap drop ; 10 20 t . cr ;" "20"; \
	run_test "rdrop discards rstack" \
		": t >r rdrop 99 ; 42 t . cr ;" "99"; \
	if [ $$FAIL -eq 0 ]; then echo "PASS"; else echo "$$FAIL FAILED"; exit 1; fi

clean:
	rm -f $(TMP)
	rm -f $(BIN) $(OBJ)

.PHONY: all test clean
