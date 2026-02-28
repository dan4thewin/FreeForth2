FF = ../../ff64
BOOT = ../../ff64.boot

.PHONY: test
test:
	@echo "=== Exp 090: remove compiler keyword fast-paths ==="
	@PASS=0; FAIL=0; \
	\
	run_test() { \
		name="$$1"; shift; \
		input="$$1"; shift; \
		expected="$$1"; shift; \
		actual=$$(echo "$$input" | $(FF) -f $(BOOT) 2>&1 | tr -d '\n '); \
		expected_clean=$$(echo "$$expected" | tr -d '\n '); \
		if echo "$$actual" | grep -qF "$$expected_clean"; then \
			echo "  PASS: $$name"; PASS=$$((PASS+1)); \
		else \
			echo "  FAIL: $$name"; \
			echo "    expected: $$expected_clean"; \
			echo "    actual:   $$actual"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	\
	run_test "variable creates and stores" \
		"variable x 42 x ! x @ . bye" "42"; \
	\
	run_test "constant stores value" \
		"99 constant y y . bye" "99"; \
	\
	run_test "variable flushes anon block" \
		": foo .\"foo\" ; foo variable z :. bar .\"bar\" ; bar bye" "foobar"; \
	\
	run_test "constant flushes anon block" \
		": foo .\"foo\" ; foo 7 constant c :. bar .\"bar\" ; bar bye" "foobar"; \
	\
	run_test "semicolon via dictionary" \
		"1 2 + . bye" "3"; \
	\
	run_test "colon via dictionary" \
		": sq dup * ; 5 sq . bye" "25"; \
	\
	run_test "multiple variables" \
		"variable a variable b 10 a ! 20 b ! a @ b @ + . bye" "30"; \
	\
	run_test "variable in loadfile" \
		"bye" ""; \
	\
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0
