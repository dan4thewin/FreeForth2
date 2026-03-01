FF = ../../ff64
BOOT = ../../ff64.boot
SHELL := /bin/bash
PASS = 0
FAIL = 0
TOTAL = 0

.PHONY: test
test:
	@echo "=== Exp 092: remove comparison WORD64 entries ==="
	@pass=0; fail=0; \
	run_test() { \
		total=$$((total+1)); \
		local desc="$$1"; shift; \
		local input="$$1"; shift; \
		local expected="$$1"; shift; \
		actual=$$(echo "$$input" | timeout 5 $(FF) -f $(BOOT) 2>/dev/null | tr -d '\r'); \
		if echo "$$actual" | grep -qF "$$expected"; then \
			echo "  PASS: $$desc"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$desc (expected '$$expected', got '$$actual')"; fail=$$((fail+1)); \
		fi; \
	}; \
	run_test "0- 0= true"  "0 0- 0= IF 1 . THEN bye" "1"; \
	run_test "0- 0= false" "5 0- 0= IF 1 . THEN bye" ""; \
	run_test "0- 0<> true"  "5 0- 0<> IF 1 . THEN bye" "1"; \
	run_test "0- 0<> false" "0 0- 0<> IF 1 . THEN bye" ""; \
	run_test "0- 0< true"  "-1 0- 0< IF 1 . THEN bye" "1"; \
	run_test "0- 0< false" "5 0- 0< IF 1 . THEN bye" ""; \
	run_test "0- 0> true"  "5 0- 0> IF 1 . THEN bye" "1"; \
	run_test "0- 0> false" "-1 0- 0> IF 1 . THEN bye" ""; \
	run_test "0- 0<= true" "0 0- 0<= IF 1 . THEN bye" "1"; \
	run_test "0- 0>= true" "0 0- 0>= IF 1 . THEN bye" "1"; \
	run_test "= true"   "5 5 = IF 1 . THEN bye" "1"; \
	run_test "= false"  "5 3 = IF 1 . THEN bye" ""; \
	run_test "<> true"  "5 3 <> IF 1 . THEN bye" "1"; \
	run_test "< true"   "3 5 < IF 1 . THEN bye" "1"; \
	run_test "> true"   "5 3 > IF 1 . THEN bye" "1"; \
	run_test "<= true"  "3 5 <= IF 1 . THEN bye" "1"; \
	run_test ">= true"  "5 3 >= IF 1 . THEN bye" "1"; \
	run_test "u< true"  "3 5 u< IF 1 . THEN bye" "1"; \
	run_test "u> true"  "5 3 u> IF 1 . THEN bye" "1"; \
	run_test "u<= true" "3 5 u<= IF 1 . THEN bye" "1"; \
	run_test "u>= true" "5 3 u>= IF 1 . THEN bye" "1"; \
	run_test "0- in def" ": t 0- 0= IF 99 . THEN ; 0 t bye" "99"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]
