FF=../../ff64
BOOT=../../ff64.boot
TIMEOUT=3

all: test

test: test-segv-message test-segv-exit-code test-normal-ok

# Test that SEGV prints the expected message
test-segv-message:
	@echo "--- $@ ---"
	@result=$$(echo '0 @' | timeout $(TIMEOUT) $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q 'SEGV' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

# Test that SEGV exit code is 139 (128 + 11)
test-segv-exit-code:
	@echo "--- $@ ---"
	@echo '0 @' | timeout $(TIMEOUT) $(FF) -f $(BOOT) >/dev/null 2>&1; \
	rc=$$?; \
	[ $$rc -eq 139 ] && echo "  PASS: $@" || { echo "  FAIL: $@ (exit code: $$rc, expected 139)"; exit 1; }

# Test that normal operation still works (no false SEGV)
test-normal-ok:
	@echo "--- $@ ---"
	@result=$$(echo '42 .' | timeout $(TIMEOUT) $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

.PHONY: all test test-segv-message test-segv-exit-code test-normal-ok
