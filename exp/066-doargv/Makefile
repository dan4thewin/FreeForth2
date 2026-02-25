# Experiment 066: needs`, -f`, doargv
# Tests: needs` compile-time file loading, -f` flag, doargv argument processing

FF = ../../ff64
BOOT = ../../ff64.boot

all: test

test: test-needs test-needs-guard test-fback test-doargv
	@echo "All 066-doargv tests passed."

# Test 1: needs` loads a file and makes its definitions available
# We cd into this dir so hello.ff is found by loadfile
test-needs:
	@echo "--- $@ ---"
	@{ printf '%-80s' 'needs hello.ff'; sleep 0.1; \
	   printf '%-80s' 'hello cr'; } | \
	  (cd $(CURDIR) && $(abspath $(FF)) -f $(abspath $(BOOT))) 2>&1 | \
	  grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@"; exit 1; }

# Test 2: needs` with guard — second load is skipped (no error)
test-needs-guard:
	@echo "--- $@ ---"
	@{ printf '%-80s' 'needs hello.ff'; sleep 0.1; \
	   printf '%-80s' 'needs hello.ff'; sleep 0.1; \
	   printf '%-80s' 'hello cr'; } | \
	  (cd $(CURDIR) && $(abspath $(FF)) -f $(abspath $(BOOT))) 2>&1 | \
	  grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@"; exit 1; }

# Test 3: -f` flag loads a file (same as needs`)
test-fback:
	@echo "--- $@ ---"
	@{ printf '%-80s' '-f hello.ff'; sleep 0.1; \
	   printf '%-80s' 'hello cr'; } | \
	  (cd $(CURDIR) && $(abspath $(FF)) -f $(abspath $(BOOT))) 2>&1 | \
	  grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@"; exit 1; }

# Test 4: doargv + _boot work correctly (boot still comes up)
test-doargv:
	@echo "--- $@ ---"
	@echo '' | $(abspath $(FF)) -f $(abspath $(BOOT)) 2>&1 | \
	  head -1 | grep -q '>' && echo "  PASS: $@ (doargv defined, boot ok)" || \
	  { echo "  FAIL: $@"; exit 1; }

.PHONY: all test test-needs test-needs-guard test-fback test-doargv
