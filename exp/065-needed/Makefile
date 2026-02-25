FF=../../ff64
BOOT=../../ff64.boot
TIMEOUT=3

all: test

test: test-needed test-needed-guard test-needed-find

# Test that needed loads a file and its definitions are accessible
test-needed:
	@echo "--- $@ ---"
	@echo ': hello 42 ;' > /tmp/ntest1.ff
	@result=$$({ printf '%s\n' '"/tmp/ntest1.ff" needed'; sleep 0.1; printf '%s\n' 'hello .'; sleep 0.1; } \
	  | timeout $(TIMEOUT) $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }
	@rm -f /tmp/ntest1.ff

# Test that second needed call skips (no error, word still works)
test-needed-guard:
	@echo "--- $@ ---"
	@echo ': answer 99 ;' > /tmp/ntest2.ff
	@result=$$({ printf '%s\n' '"/tmp/ntest2.ff" needed'; sleep 0.1; \
	  printf '%s\n' '"/tmp/ntest2.ff" needed'; sleep 0.1; \
	  printf '%s\n' 'answer .'; sleep 0.1; } \
	  | timeout $(TIMEOUT) $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '99' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }
	@rm -f /tmp/ntest2.ff

# Test that find word works correctly
test-needed-find:
	@echo "--- $@ ---"
	@result=$$(echo '"dup" find . .' | timeout $(TIMEOUT) $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '^> 0 ' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

.PHONY: all test test-needed test-needed-guard test-needed-find
