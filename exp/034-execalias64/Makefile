FF = ../../ff64-
MACROS = macros.ff
TMP = /tmp/ff-034.ff

.PHONY: test clean

test:
	@echo "=== Exp 034: Execute, alias, constant, brackets ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		desc="$$1"; input="$$2"; expect="$$3"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$($(FF) $(MACROS) $(TMP) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | tr -d '\n' | sed 's/ *$$//'); \
		if [ "$$actual" = "$$expect" ]; then \
			echo "PASS: $$desc"; PASS=$$((PASS+1)); \
		else \
			echo "FAIL: $$desc"; \
			echo "  expected: [$$expect]"; \
			echo "  got:      [$$actual]"; FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "execute: call xt from stack" \
		": hi 72 emit 105 emit cr ; H@ @ execute ;" \
		"Hi"; \
	run_test "execute: call another word" \
		": add3 3 + ; H@ @ 5 swap execute . cr ;" \
		"8"; \
	run_test "alias: create synonym" \
		": hi 72 emit 105 emit cr ; H@ @ alias greet greet ;" \
		"Hi"; \
	run_test "alias: preserves arithmetic" \
		": add3 3 + ; H@ @ alias plus3 5 plus3 . cr ;" \
		"8"; \
	run_test "alias: ct has alias flag 0x20" \
		": foo ; H@ @ alias bar H@ 8 + c@ \$$20 & . cr ;" \
		"32"; \
	run_test "constant (asm): define and use" \
		"42 constant answer answer . cr ;" \
		"42"; \
	run_test "constant (asm): negative" \
		"-7 constant neg neg . cr ;" \
		"-7"; \
	run_test "constant (Forth): via myconst wrapper" \
		"99 myconst val val . cr ;" \
		"99"; \
	run_test "brackets: compile-time eval" \
		": t [ 3 4 + ] . cr ; t ;" \
		"7"; \
	run_test "brackets: compute in named def" \
		": t [ 10 2 * ] . cr ; t ;" \
		"20"; \
	echo ""; \
	echo "Results: $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0

clean:
	@echo "Nothing to clean"

clean:
	@rm -f $(TMP)
