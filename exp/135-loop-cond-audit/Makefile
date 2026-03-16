FF=../../ff64-
SHELL=/bin/bash

test: $(FF)
	@echo "=== Exp 135: Loop+conditional audit (84 tests) ==="
	@cd ../.. && timeout 30 ./ff64- exp/135-loop-cond-audit/test.ff 2>/dev/null | tail -1 | grep -q PASSED || \
		(echo "  FAIL"; exit 1)
	@echo "  PASS"

.PHONY: test
