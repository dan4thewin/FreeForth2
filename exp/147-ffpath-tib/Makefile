FF=../../ff64

.PHONY: test
test: test-default test-subdir test-full test-tilde
	@echo PASSED

# Test 1: default FFPATH from repo root
test-default:
	@echo -n "test-default: "
	@cd ../.. && timeout 5 ./ff64 -f exp/147-ffpath-tib/ffpath.ff -f exp/147-ffpath-tib/test.ff

# Test 2: running from /tmp — # resolves via /proc/self/exe
test-subdir:
	@echo -n "test-subdir: "
	@cd /tmp && timeout 5 $(CURDIR)/$(FF) -f $(CURDIR)/ffpath.ff -f $(CURDIR)/test.ff

# Test 3: full directory entries (no ?), exercises _full/_expand/_exp#
test-full:
	@echo -n "test-full: "
	@cd ../.. && FFPATH='#/lib/x86-64:#/lib' timeout 5 ./ff64 -f exp/147-ffpath-tib/ffpath.ff -f exp/147-ffpath-tib/test-full.ff

# Test 4: ~ sigil expansion, exercises _exp~ in both partial and full entries
test-tilde:
	@echo -n "test-tilde: "
	@cd ../.. && HOME=$$(pwd) FFPATH='~/lib/?.ff:~/lib' timeout 5 ./ff64 -f exp/147-ffpath-tib/ffpath.ff -f exp/147-ffpath-tib/test-tilde.ff
