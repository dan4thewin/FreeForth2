FF = ../../ff64
SHELL := /bin/bash
TMP := /tmp/ff64-test-091.ff

.PHONY: test
test:
	@echo "=== Exp 091: remove ct=2 inline words ==="
	@pass=0; fail=0; \
	run() { \
		local desc="$$1" input="$$2" expected="$$3"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(timeout 5 $(FF) ': prompt ;' -f $(TMP) 2>/dev/null); \
		if [[ $$actual = $$expected ]]; then \
			echo "  PASS: $$desc"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$desc"; \
			echo "    expected: [$$expected]"; \
			echo "    actual:   [$$actual]"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	run "dup works" ": t 5 dup + . depth .\ cr ; t bye" "10 0"; \
	run "drop works" ": t 1 2 drop . depth .\ cr ; t bye" "1 0"; \
	run "swap works" ": t 1 2 swap - . depth .\ cr ; t bye" "1 0"; \
	run "over works" ": t 3 4 over + . . depth .\ cr ; t bye" "7 3 0"; \
	run "nip works" ": t 1 2 nip . depth .\ cr ; t bye" "2 0"; \
	run "rot works" ": t 1 2 3 rot . . . depth .\ cr ; t bye" "1 3 2 0"; \
	run "tuck works" ": t 1 2 tuck . . . depth .\ cr ; t bye" "2 1 2 0"; \
	run "negate works" ": t 5 negate . depth .\ cr ; t bye" "-5 0"; \
	run "add works" ": t 3 7 + . depth .\ cr ; t bye" "10 0"; \
	run "sub works" ": t 10 3 - . depth .\ cr ; t bye" "7 0"; \
	run "mul works" ": t 6 7 * . depth .\ cr ; t bye" "42 0"; \
	run "fetch works" "variable x 99 x ! : t x @ . depth .\ cr ; t bye" "99 0"; \
	run "cfetch works" ": t here 65 c, c@ . depth .\ cr ; t bye" "65 0"; \
	rm -f $(TMP); \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[[ $$fail -eq 0 ]]
