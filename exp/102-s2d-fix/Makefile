FF = ../../ff64
SHELL := /bin/bash
TMP := /tmp/ff64-test-102.ff

.PHONY: test
test:
	@echo "=== Exp 102: s>d fix ==="
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
	run "s>d positive" ": t 5 s>d . . depth .\\ cr ; t bye" "0 5 0"; \
	run "s>d negative" ": t -1 s>d . . depth .\\ cr ; t bye" "-1 -1 0"; \
	run "s>d zero" ": t 0 s>d . . depth .\\ cr ; t bye" "0 0 0"; \
	run "s>d in m/mod (10 / 3)" ": t 10 s>d 3 m/mod . . depth .\\ cr ; t bye" "3 1 0"; \
	run "s>d SWAPbit (over s>d)" ": t over s>d 2drop nip ; : u 10 20 t . depth .\\ cr ; u bye" "20 0"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	rm -f $(TMP); \
	test $$fail -eq 0
