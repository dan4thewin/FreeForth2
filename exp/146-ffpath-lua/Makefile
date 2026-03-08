FF=../../ff64

.PHONY: test
test: test-default test-subdir
	@echo PASSED

# Test 1: default FFPATH from repo root
test-default:
	@echo -n "test-default: "
	@cd ../.. && timeout 5 ./ff64 -f exp/146-ffpath-lua/ffpath.ff -f exp/146-ffpath-lua/test.ff

# Test 2: running from /tmp — # resolves via /proc/self/exe
test-subdir:
	@echo -n "test-subdir: "
	@cd /tmp && timeout 5 $(CURDIR)/$(FF) -f $(CURDIR)/ffpath.ff -f $(CURDIR)/test.ff
