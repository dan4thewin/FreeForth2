FF = ../../ff64
BOOT = ../../ff64.boot

.PHONY: test
test:
	@echo "=== Exp 091: remove ct=2 inline words ==="
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
	run_test "dup works" "5 dup + . bye" "10"; \
	run_test "drop works" "1 2 drop . bye" "1"; \
	run_test "swap works" "1 2 swap - . bye" "1"; \
	run_test "over works" ": t over + ; 3 4 t . . bye" "73"; \
	run_test "nip works" "1 2 nip . bye" "2"; \
	run_test "rot works" "1 2 3 rot . . . bye" "132"; \
	run_test "tuck works" "1 2 tuck . . . bye" "212"; \
	run_test "negate works" "5 negate . bye" "0;-5"; \
	run_test "add works" "3 7 + . bye" "10"; \
	run_test "sub works" "10 3 - . bye" "7"; \
	run_test "mul works" "6 7 * . bye" "42"; \
	run_test "fetch works" "variable x 99 x ! x @ . bye" "99"; \
	run_test "cfetch works" ": t here 65 c, c@ . ; t bye" "65"; \
	\
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0
