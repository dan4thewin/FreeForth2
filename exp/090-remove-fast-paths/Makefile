FF = ../../ff64
SHELL := /bin/bash
TMP := /tmp/ff64-test-090.ff

.PHONY: test
test:
	@echo "=== Exp 090: remove compiler keyword fast-paths ==="
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
	run "variable creates and stores" \
	"variable x 42 x ! x @ . depth .\ cr bye" "42 0"; \
	run "constant stores value" \
	"99 constant y y . depth .\ cr bye" "99 0"; \
	run "variable flushes anon block" \
	': foo ."foo" ; foo variable z :. bar ."bar" ; bar depth .\ cr bye' "foobar0"; \
	run "constant flushes anon block" \
	': foo ."foo" ; foo 7 constant c :. bar ."bar" ; bar depth .\ cr bye' "foobar0"; \
	run "semicolon via dictionary" \
	"1 2 + . depth .\ cr bye" "3 0"; \
	run "colon via dictionary" \
	": sq dup * ; 5 sq . depth .\ cr bye" "25 0"; \
	run "multiple variables" \
	"variable a variable b 10 a ! 20 b ! a @ b @ + . depth .\ cr bye" "30 0"; \
	rm -f $(TMP); \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[[ $$fail -eq 0 ]]
