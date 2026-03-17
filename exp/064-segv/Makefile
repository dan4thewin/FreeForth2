FF=../../ff64-
FF_RAW=../../ff64
TIMEOUT=3
TMP=/tmp/ff-064.ff

all: test

test: test-segv-message test-segv-recovery test-segv-continue test-normal-ok

# Test that SEGV prints the expected message
test-segv-message:
	@echo "--- $@ ---"
	@echo '0 @' > $(TMP); result=$$(timeout $(TIMEOUT) $(FF) $(TMP) 2>&1); \
	echo "$$result" | grep -q 'SEGV' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

# Test that SEGV is caught (exit 0, not 139)
# Uses FF_RAW with stdin redirect — SEGV recovery needs interactive REPL
test-segv-recovery:
	@echo "--- $@ ---"
	@printf '0 @\n0 exit\n' > $(TMP); timeout $(TIMEOUT) $(FF_RAW) < $(TMP) >/dev/null 2>&1; \
	rc=$$?; \
	[ $$rc -eq 0 ] && echo "  PASS: $@" || { echo "  FAIL: $@ (exit code: $$rc, expected 0)"; exit 1; }

# Test that REPL continues after SEGV
# Uses FF_RAW with stdin redirect — SEGV recovery needs interactive REPL
test-segv-continue:
	@echo "--- $@ ---"
	@result=$$(printf '0 @\n42 .\n0 exit\n' > $(TMP); timeout $(TIMEOUT) $(FF_RAW) < $(TMP) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

# Test that normal operation still works (no false SEGV)
test-normal-ok:
	@echo "--- $@ ---"
	@echo '42 .' > $(TMP); result=$$(timeout $(TIMEOUT) $(FF) $(TMP) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

clean:
	@rm -f $(TMP)

.PHONY: all test test-segv-message test-segv-recovery test-segv-continue test-normal-ok
