FF = ../../ff64-
SHELL := /bin/bash
TMP := /tmp/ff64-test-092.ff

.PHONY: test
test:
	@echo "=== Exp 092: remove comparison WORD64 entries ==="
	@pass=0; fail=0; \
	run() { \
		local desc="$$1" input="$$2" expected="$$3"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(timeout 5 $(FF) $(TMP) 2>/dev/null); \
		if [[ $$actual = $$expected ]]; then \
			echo "  PASS: $$desc"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$desc"; \
			echo "    expected: [$$expected]"; \
			echo "    actual:   [$$actual]"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	run "0- 0= true"   ": t 0 0- 0= drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "0- 0= false"  ": t 5 0- 0= drop IF 1 . THEN depth .\\ cr ; t bye" "0"; \
	run "0- 0<> true"  ": t 5 0- 0<> drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "0- 0<> false" ": t 0 0- 0<> drop IF 1 . THEN depth .\\ cr ; t bye" "0"; \
	run "0- 0< true"   ": t -1 0- 0< drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "0- 0< false"  ": t 5 0- 0< drop IF 1 . THEN depth .\\ cr ; t bye" "0"; \
	run "0- 0> true"   ": t 5 0- 0> drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "0- 0> false"  ": t -1 0- 0> drop IF 1 . THEN depth .\\ cr ; t bye" "0"; \
	run "0- 0<= true"  ": t 0 0- 0<= drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "0- 0>= true"  ": t 0 0- 0>= drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "= true"       ": t 5 5 = 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "= false"      ": t 5 3 = 2drop IF 1 . THEN depth .\\ cr ; t bye" "0"; \
	run "<> true"      ": t 5 3 <> 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "< true"       ": t 3 5 < 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "> true"       ": t 5 3 > 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "<= true"      ": t 3 5 <= 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run ">= true"      ": t 5 3 >= 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "u< true"      ": t 3 5 u< 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "u> true"      ": t 5 3 u> 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "u<= true"     ": t 3 5 u<= 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "u>= true"     ": t 5 3 u>= 2drop IF 1 . THEN depth .\\ cr ; t bye" "1 0"; \
	run "0- in def"    ": t 0- 0= drop IF 99 . THEN depth .\\ cr ; 0 t bye" "99 0"; \
	rm -f $(TMP); \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[[ $$fail -eq 0 ]]
