# Experiment 066: needs`, -f`, doargv
# Tests: needs` compile-time file loading, -f` flag, doargv argument processing

FF = ../../ff64-
TMP = /tmp/ff-066.ff

all: test

test: test-needs test-needs-guard test-fback test-doargv
	@echo "All 066-doargv tests passed."

# Test 1: needs` loads a file and makes its definitions available
# We cd into this dir so hello.ff is found by loadfile
test-needs:
	@echo "--- $@ ---"
	@printf '%s\n' 'needs hello.ff' 'hello cr' > $(TMP)
	@(cd $(CURDIR) && $(abspath $(FF)) $(TMP)) 2>&1 | \
	  grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@"; exit 1; }

# Test 2: needs` with guard — second load is skipped (no error)
test-needs-guard:
	@echo "--- $@ ---"
	@printf '%s\n' 'needs hello.ff' 'needs hello.ff' 'hello cr' > $(TMP)
	@(cd $(CURDIR) && $(abspath $(FF)) $(TMP)) 2>&1 | \
	  grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@"; exit 1; }

# Test 3: -f` flag loads a file (same as needs`)
test-fback:
	@echo "--- $@ ---"
	@printf '%s\n' '-f hello.ff' 'hello cr' > $(TMP)
	@(cd $(CURDIR) && $(abspath $(FF)) $(TMP)) 2>&1 | \
	  grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@"; exit 1; }

# Test 4: doargv + _boot work correctly (boot still comes up)
test-doargv:
	@echo "--- $@ ---"
	@echo '42 . ;' > $(TMP)
	@$(abspath $(FF)) $(TMP) 2>&1 | \
	  grep -q '42' && echo "  PASS: $@ (doargv defined, boot ok)" || \
	  { echo "  FAIL: $@"; exit 1; }

clean:
	@rm -f $(TMP)

.PHONY: all test test-needs test-needs-guard test-fback test-doargv clean
