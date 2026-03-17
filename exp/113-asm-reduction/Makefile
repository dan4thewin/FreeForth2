FF = ../../ff64-
FFS = ../../ff64s
SHELL := /bin/bash
TMP := /tmp/ff64-test-113.ff

.PHONY: test
test:
	@echo "=== Exp 113: Assembly reduction ==="
	@pass=0; fail=0; \
	run() { \
		local desc="$$1" input="$$2" expected="$$3" cmd="$${4:-$(FF)}"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(timeout 5 $$cmd $(TMP) 2>/dev/null); \
		if [[ $$actual = $$expected ]]; then \
			printf '  %-50s PASS\n' "$$desc"; pass=$$((pass+1)); \
		else \
			printf '  %-50s FAIL\n' "$$desc"; \
			echo "    expected: [$$expected]"; \
			echo "    actual:   [$$actual]"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	run "write via syscall (ff64)" \
		'"hello" type cr bye' 'hello'; \
	run "write via syscall (ff64s)" \
		'"hello" type cr bye' 'hello' '$(FFS) -f'; \
	run "cr as Forth vector (ff64)" \
		'42 .\ cr bye' '42'; \
	run "cr as Forth vector (ff64s)" \
		'42 .\ cr bye' '42' '$(FFS) -f'; \
	run "emit still works (ff64)" \
		'65 emit cr bye' 'A'; \
	printf ': t 0 @ ; t bye\n' > $(TMP); \
	actual=$$(timeout 2 $(FF) $(TMP) 2>/dev/null | head -3); \
	if echo "$$actual" | grep -q "SEGV"; then \
		printf '  %-50s PASS\n' "SEGV recovery (ff64)"; pass=$$((pass+1)); \
	else \
		printf '  %-50s FAIL\n' "SEGV recovery (ff64)"; \
		echo "    actual: [$$actual]"; fail=$$((fail+1)); \
	fi; \
	printf ': t 0 @ ; t bye\n' > $(TMP); \
	actual=$$(timeout 2 $(FFS) -f $(TMP) 2>/dev/null | head -3); \
	if echo "$$actual" | grep -q "SEGV"; then \
		printf '  %-50s PASS\n' "SEGV recovery (ff64s)"; pass=$$((pass+1)); \
	else \
		printf '  %-50s FAIL\n' "SEGV recovery (ff64s)"; \
		echo "    actual: [$$actual]"; fail=$$((fail+1)); \
	fi; \
	SIZE=$$(stat -c%s ../../ff64); \
	if [ "$$SIZE" -lt 120000 ]; then \
		printf '  %-50s PASS (%s < 120000)\n' "binary smaller" "$$SIZE"; pass=$$((pass+1)); \
	else \
		printf '  %-50s FAIL (%s)\n' "binary smaller" "$$SIZE"; fail=$$((fail+1)); \
	fi; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	rm -f $(TMP); \
	test $$fail -eq 0
