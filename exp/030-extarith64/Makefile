FF = ../../ff64
MACROS = macros.ff

.PHONY: test clean

test:
	@echo "=== Exp 030: Extended arithmetic ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		desc="$$1"; input="$$2"; expect="$$3"; \
		actual=$$(printf '%s\n' "$$input" | $(FF) -f $(MACROS) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | tr -d '\n' | sed 's/ *$$//'); \
		if [ "$$actual" = "$$expect" ]; then \
			echo "PASS: $$desc"; PASS=$$((PASS+1)); \
		else \
			echo "FAIL: $$desc"; \
			echo "  expected: [$$expect]"; \
			echo "  got:      [$$actual]"; FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "m/mod: 10/3 signed" \
		"10 0 3 m/mod . . cr ;" \
		"3 1"; \
	run_test "m/mod: negative" \
		"-10 -1 3 m/mod . . cr ;" \
		"-3 -1"; \
	run_test "m/mod: exact" \
		"12 0 4 m/mod . . cr ;" \
		"3 0"; \
	run_test "um/mod: 10/3 unsigned" \
		"10 0 3 um/mod . . cr ;" \
		"3 1"; \
	run_test "m*: 5*7 positive" \
		"5 7 m* . . cr ;" \
		"0 35"; \
	run_test "m*: negative" \
		"-5 7 m* . . cr ;" \
		"-1 -35"; \
	run_test "um*: 5*7 unsigned" \
		"5 7 um* . . cr ;" \
		"0 35"; \
	run_test "*/mod: 10*3/7" \
		"10 3 7 */mod . . cr ;" \
		"4 2"; \
	run_test "*/: 10*3/7" \
		"10 3 7 */ . cr ;" \
		"4"; \
	run_test "*/: exact" \
		"10 6 3 */ . cr ;" \
		"20"; \
	echo "---"; \
	echo "$$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

clean:
	@echo "Nothing to clean (uses production ff64)"
