FF      = ../../ff64

test:
	@echo "=== 054: .s / ds stack display ==="
	@PASS=0; FAIL=0; \
	run_one() { \
		printf '  --- %s ---\n' "$$1"; \
		OUT=$$(echo "$$2" | timeout 5 $(FF) 2>&1); \
		if echo "$$OUT" | grep -qF "$$3"; then \
			printf '  PASS: %s\n' "$$1"; PASS=$$((PASS+1)); \
		else \
			printf '  FAIL: %s\n  expected: %s\n  got: %s\n' "$$1" "$$3" "$$OUT"; FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_one "ds-empty" "ds" " 0;"; \
	run_one "ds-one" "42 ds" " 1; 42"; \
	run_one "ds-three" "1 2 3 ds" " 3; 1 2 3"; \
	run_one "ds-order" "10 20 30 ds" "10 20 30"; \
	run_one "ds-nine" "1 2 3 4 5 6 7 8 9 ds" " 9; 1 2 3 4 5 6 7 8 9"; \
	printf '  --- ds-no-corrupt ---\n'; \
	OUT=$$(echo '42 ds depth . cr' | timeout 5 $(FF) 2>&1); \
	if echo "$$OUT" | grep -qF '1; 42' && echo "$$OUT" | grep -qF '1'; then \
		printf '  PASS: ds-no-corrupt\n'; PASS=$$((PASS+1)); \
	else \
		printf '  FAIL: ds-no-corrupt\n  got: %s\n' "$$OUT"; FAIL=$$((FAIL+1)); \
	fi; \
	printf '  --- ds-after-ops ---\n'; \
	OUT=$$(echo '3 4 + ds' | timeout 5 $(FF) 2>&1); \
	if echo "$$OUT" | grep -qF '1; 7'; then \
		printf '  PASS: ds-after-ops\n'; PASS=$$((PASS+1)); \
	else \
		printf '  FAIL: ds-after-ops\n  got: %s\n' "$$OUT"; FAIL=$$((FAIL+1)); \
	fi; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	[ "$$FAIL" = "0" ]

.PHONY: test
