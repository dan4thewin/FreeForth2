FF = ../../ff64-
MACROS = macros.ff
TMP = /tmp/ff-028.ff

.PHONY: test clean

test:
	@echo "=== Exp 028: Stack ops and divmod ==="
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
	run_test "2xchg: a b c → c b a" \
		"10 20 30 2xchg . . . cr ;" \
		"10 20 30"; \
	run_test "2xchg: different values" \
		"100 200 300 2xchg . . . cr ;" \
		"100 200 300"; \
	run_test "2r@: read two return stack items" \
		": t 10 >r 20 >r 2r . . cr rdrop rdrop ; t ;" \
		"20 10"; \
	run_test "2r@: different values" \
		": t 99 >r 42 >r 2r . . cr rdrop rdrop ; t ;" \
		"42 99"; \
	run_test "3dup: triplicate" \
		"10 20 30 3dup . . . . . . cr ;" \
		"30 20 10 30 20 10"; \
	run_test "3dup: check no clobber" \
		"5 6 7 3dup + + + + + . cr ;" \
		"36"; \
	run_test "/%: divmod positive" \
		"17 5 /% . . cr ;" \
		"3 2"; \
	run_test "/%: divmod negative" \
		"-17 5 /% . . cr ;" \
		"-3 -2"; \
	run_test "/: divide" \
		"100 7 / . cr ;" \
		"14"; \
	run_test "%: modulo" \
		"100 7 % . cr ;" \
		"2"; \
	run_test "/%: exact division" \
		"20 4 /% . . cr ;" \
		"5 0"; \
	run_test "/: negative divide" \
		"-20 3 / . cr ;" \
		"-6"; \
	echo "---"; \
	echo "$$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

clean:
	@echo "Nothing to clean (uses production ff64)"

clean:
	@rm -f $(TMP)
