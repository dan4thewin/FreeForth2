FF = ../../ff64

.PHONY: test clean

test: test-true test-false test-else-true test-else-false \
      test-nested-skip test-skip-text test-const-true test-const-false

test-true:
	@echo "--- $@ ---"
	@echo '[1] [IF] 42 . cr [THEN]' | $(FF) 2>&1 | grep -q '^> 42'
	@echo "  PASS: $@"

test-false:
	@echo "--- $@ ---"
	@result=$$(echo '[0] [IF] 42 . cr [THEN] 99 . cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q '99' && ! echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-else-true:
	@echo "--- $@ ---"
	@echo '[1] [IF] 42 . cr [ELSE] 99 . cr [THEN]' | $(FF) 2>&1 | grep -q '^> 42'
	@echo "  PASS: $@"

test-else-false:
	@echo "--- $@ ---"
	@echo '[0] [IF] 42 . cr [ELSE] 99 . cr [THEN]' | $(FF) 2>&1 | grep -q '^> 99'
	@echo "  PASS: $@"

test-nested-skip:
	@echo "--- $@ ---"
	@result=$$(echo '[0] [IF] [1] [IF] 42 . cr [THEN] [THEN] 99 . cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q '99' && ! echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-skip-text:
	@echo "--- $@ ---"
	@echo '[0] [IF] ARBITRARY GARBAGE WORDS [THEN] 42 . cr' | $(FF) 2>&1 | grep -q '^> 42'
	@echo "  PASS: $@"

test-const-true:
	@echo "--- $@ ---"
	@echo '1 constant YES` YES [IF] 42 . cr [THEN]' | $(FF) 2>&1 | grep -q '^> 42'
	@echo "  PASS: $@"

test-const-false:
	@echo "--- $@ ---"
	@result=$$(echo '0 constant NO` NO [IF] 42 . cr [THEN] 99 . cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q '99' && ! echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

clean:
	@true
