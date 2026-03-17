FF=../../ff64-
TMP=/tmp/ff-065.ff
TMP2=/tmp/ff-065-b.ff
TIMEOUT=3

all: test

test: test-needed test-needed-guard test-needed-find

# Test that needed loads a file and its definitions are accessible
# needed overwrites the tib, so the check must be in a separate file
test-needed:
	@echo "--- $@ ---"
	@echo ': hello 42 ;' > /tmp/ntest1.ff
	@echo '"/tmp/ntest1.ff" needed' > $(TMP)
	@echo 'hello .' > $(TMP2)
	@result=$$(timeout $(TIMEOUT) $(FF) $(TMP) $(TMP2) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }
	@rm -f /tmp/ntest1.ff

# Test that second needed call skips (no error, word still works)
# First needed overwrites tib; guarded second + check go in a separate file
test-needed-guard:
	@echo "--- $@ ---"
	@echo ': answer 99 ;' > /tmp/ntest2.ff
	@echo '"/tmp/ntest2.ff" needed' > $(TMP)
	@printf '%s\n' '"/tmp/ntest2.ff" needed' 'answer .' > $(TMP2)
	@result=$$(timeout $(TIMEOUT) $(FF) $(TMP) $(TMP2) 2>&1); \
	echo "$$result" | grep -q '99' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }
	@rm -f /tmp/ntest2.ff

# Test that find word works correctly (use "cr" — always in dictionary)
test-needed-find:
	@echo "--- $@ ---"
	@echo '"cr" find . . cr ;' > $(TMP)
	@result=$$(timeout $(TIMEOUT) $(FF) $(TMP) 2>/dev/null); \
	echo "$$result" | grep -q '0 ' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

clean:
	@rm -f $(TMP) $(TMP2)

.PHONY: all test test-needed test-needed-guard test-needed-find clean
