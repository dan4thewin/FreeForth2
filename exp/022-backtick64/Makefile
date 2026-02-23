ASM = backtick64.asm
BIN = backtick64
OBJ = backtick64.o

all: $(BIN)

$(BIN): $(ASM)
	fasm $(ASM) $(OBJ) && ld -o $(BIN) $(OBJ)

test: $(BIN)
	@echo "=== 022-backtick64 ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1"; local input="$$2"; local expected="$$3"; \
		actual=$$(printf '%s\n' "$$input" | cat macros.ff - | ./$(BIN) 2>/dev/null | sed '/^> ok$$/d;/^ok$$/d;/^> *$$/d;s/^> //' | tr -d '\n' | sed 's/ *$$//'); \
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
	run_test "basic arithmetic" \
		"1 2 + . cr ;" "3"; \
	run_test "nipdup macro" \
		": t nipdup ; 7 t . cr ;" "7"; \
	run_test "under+nip identity" \
		": t under nip ; 10 20 t . cr ;" "20"; \
	run_test "Forth dup macro" \
		": t dup ; 42 t . . cr ;" "42 42"; \
	run_test "Forth drop macro" \
		": t drop ; 10 20 t . cr ;" "10"; \
	run_test "Forth over macro" \
		": t over ; 10 20 t . . . cr ;" "10 20 10"; \
	run_test "Forth swap macro" \
		": t swap ; 10 20 t . . cr ;" "10 20"; \
	run_test "Forth nip macro" \
		": t nip ; 10 20 t . cr ;" "20"; \
	run_test "dup+add via Forth macros" \
		": double dup + ; 21 double . cr ;" "42"; \
	run_test "over+sub via Forth macros" \
		": diff over swap - ; 100 58 diff . cr ;" "42"; \
	run_test "SWAPbit: swap+dup" \
		": t swap dup ; 10 20 t . . . cr ;" "10 10 20"; \
	run_test "nested macros with flow control" \
		": abs dup 0< IF negate THEN ; 0 42 - abs . cr ;" "42"; \
	if [ $$FAIL -eq 0 ]; then echo "PASS"; else echo "$$FAIL FAILED"; exit 1; fi

clean:
	rm -f $(BIN) $(OBJ)

.PHONY: all test clean
