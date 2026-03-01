FF = ../../ff64
SHELL := /bin/bash
TMP := /tmp/ff64-test-093.ff

.PHONY: test
test:
	@echo "=== Exp 093: remove dead runtime WORD64 entries ==="
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
	run "store/fetch" "variable x 42 x ! x @ . depth .\\ cr bye" "42 0"; \
	run "c! c@" "variable x 65 x c! x c@ . depth .\\ cr bye" "65 0"; \
	run "d! d@" "variable x 99 x d! x d@ . depth .\\ cr bye" "99 0"; \
	run "+!" "variable x 10 x ! 5 x +! x @ . depth .\\ cr bye" "15 0"; \
	run "allot" "variable buf 100 allot depth .\\ cr bye" "0"; \
	run "comma" "here 42 , @ . depth .\\ cr bye" "42 0"; \
	run "c," "here 65 c, c@ . depth .\\ cr bye" "65 0"; \
	run "w," "here 1000 w, w@ . depth .\\ cr bye" "1000 0"; \
	run "d," "here 99 d, d@ . depth .\\ cr bye" "99 0"; \
	run "divide" ": t 10 3 / . depth .\\ cr ; t bye" "3 0"; \
	run "modulus" ": t 10 3 % . depth .\\ cr ; t bye" "1 0"; \
	run "dot" "42 . depth .\\ cr bye" "42 0"; \
	run "cmove" "variable a 8 allot variable b 8 allot 65 a c! 66 a 1+ c! a b 2 cmove b c@ . depth .\\ cr bye" "65 0"; \
	run ">r r>" ": t 5 >r r> . depth .\\ cr ; t bye" "5 0"; \
	run "m/mod" ": t 7 0 3 m/mod . . depth .\\ cr ; t bye" "2 1 0"; \
	run "m*" ": t 3 4 m* . . depth .\\ cr ; t bye" "0 12 0"; \
	rm -f $(TMP); \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[[ $$fail -eq 0 ]]
