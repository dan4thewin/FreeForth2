# Exp 037: Counted loops — TIMES/REPEAT
# Tests the TIMES` and REPEAT` macros for counted loop iteration.
# TIMES pushes count to return stack; dec+js at loop top.
# REPEAT resolves the backward/forward jumps and does rdrop.
# r reads the current counter (N-1 down to 0).

FF=../../ff64

.PHONY: test clean

test:
	@echo "=== Exp 037: Counted loops ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1" input="$$2" expect="$$3"; \
		result=$$(echo "$$input" | $(FF) 2>/dev/null | head -1 | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//'); \
		if [ "$$result" = "$$expect" ]; then \
			echo "  PASS: $$desc"; \
			PASS=$$((PASS+1)); \
		else \
			echo "  FAIL: $$desc (expected '$$expect', got '$$result')"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "TIMES 1" ": t 0 1 TIMES 1 + REPEAT ; t . ;" "1"; \
	run_test "TIMES 3" ": t 0 3 TIMES 1 + REPEAT ; t . ;" "3"; \
	run_test "TIMES 5" ": t 0 5 TIMES 1 + REPEAT ; t . ;" "5"; \
	run_test "TIMES 10" ": t 0 10 TIMES 1 + REPEAT ; t . ;" "10"; \
	run_test "TIMES 0 skips" ": t 42 0 TIMES 99 REPEAT ; t . ;" "42"; \
	run_test "r counts" ": t 5 TIMES r . REPEAT ; t ;" "4 3 2 1 0"; \
	run_test "r sum" ": t 0 5 TIMES r + REPEAT ; t . ;" "10"; \
	run_test "r sum 10" ": t 0 10 TIMES r + REPEAT ; t . ;" "45"; \
	run_test "nested" ": t 0 3 TIMES 2 TIMES 1 + REPEAT REPEAT ; t . ;" "6"; \
	run_test "WHILE still works" ": t BEGIN dup 0- 0<> WHILE 1 - REPEAT ; 5 t . ;" "0"; \
	run_test "mixed WHILE/TIMES" ": t 0 BEGIN dup 5 < drop WHILE 3 TIMES 1 + REPEAT REPEAT drop ; 0 t . ;" "6"; \
	run_test "TIMES in word" ": add3 3 TIMES 1 + REPEAT ; : t 0 add3 ; t . ;" "3"; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

clean:
	@echo "Nothing to clean"
