FF      = ../../ff64

test:
	@echo "=== 055: \$$- string comparison and string literals ==="
	@PASS=0; FAIL=0; \
	run_one() { \
		printf '  --- %s ---\n' "$$1"; \
		OUT=$$(printf '%s\n' "$$2" | timeout 5 $(FF) 2>&1); \
		if echo "$$OUT" | grep -qF -- "$$3"; then \
			printf '  PASS: %s\n' "$$1"; PASS=$$((PASS+1)); \
		else \
			printf '  FAIL: %s\n  expected: %s\n  got: %s\n' "$$1" "$$3" "$$OUT"; FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_one "equal-strings" \
		"create s1 65 c, 66 c, 67 c, create s2 65 c, 66 c, 67 c, s1 s2 3 \$$- . cr" \
		"0"; \
	run_one "diff-strings" \
		"create s1 65 c, 66 c, 67 c, create s2 65 c, 66 c, 68 c, s1 s2 3 \$$- . cr" \
		"-1"; \
	run_one "diff-reverse" \
		"create s1 65 c, 66 c, 68 c, create s2 65 c, 66 c, 67 c, s1 s2 3 \$$- . cr" \
		"1"; \
	run_one "single-char-eq" \
		"create s1 88 c, create s2 88 c, s1 s2 1 \$$- . cr" \
		"0"; \
	run_one "single-char-ne" \
		"create s1 65 c, create s2 90 c, s1 s2 1 \$$- . cr" \
		"-25"; \
	run_one "zero-length" \
		"create s1 65 c, create s2 90 c, 99 s1 s2 0 \$$- . depth . cr" \
		"0 1"; \
	run_one "first-differs" \
		"create s1 90 c, 66 c, create s2 65 c, 66 c, s1 s2 2 \$$- . cr" \
		"25"; \
	run_one "stack-depth" \
		"create s1 65 c, create s2 65 c, s1 s2 1 \$$- . depth . cr" \
		"0 0"; \
	run_one "dotstr-print" \
		'.\"hello" cr' \
		"hello"; \
	run_one "dotstr-space" \
		'.\"hello_world" cr' \
		"hello world"; \
	run_one "litstr-type" \
		'"test" type cr' \
		"test"; \
	run_one "litstr-count" \
		'"abcde" . cr' \
		"5"; \
	run_one "litstr-drop-cmp" \
		': t "ab" drop "ab" drop 2 $$- . cr ; t' \
		"0"; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	[ "$$FAIL" = "0" ]

.PHONY: test
