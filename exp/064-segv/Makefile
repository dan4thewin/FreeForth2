FF=../../ff64
TIMEOUT=3

all: test

test: test-segv-message test-segv-recovery test-segv-continue test-normal-ok

# Test that SEGV prints the expected message
test-segv-message:
	@echo "--- $@ ---"
	@result=$$(echo '0 @' | timeout $(TIMEOUT) $(FF) 2>&1); \
	echo "$$result" | grep -q 'SEGV' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

# Test that SEGV is caught (exit 0, not 139)
test-segv-recovery:
	@echo "--- $@ ---"
	@printf '0 @\n0 exit\n' | timeout $(TIMEOUT) $(FF) >/dev/null 2>&1; \
	rc=$$?; \
	[ $$rc -eq 0 ] && echo "  PASS: $@" || { echo "  FAIL: $@ (exit code: $$rc, expected 0)"; exit 1; }

# Test that REPL continues after SEGV
test-segv-continue:
	@echo "--- $@ ---"
	@result=$$(printf '0 @\n42 .\n0 exit\n' | timeout $(TIMEOUT) $(FF) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

# Test that normal operation still works (no false SEGV)
test-normal-ok:
	@echo "--- $@ ---"
	@result=$$(echo '42 .' | timeout $(TIMEOUT) $(FF) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

.PHONY: all test test-segv-message test-segv-recovery test-segv-continue test-normal-ok
