FF=../../ff64-
FFs=../../ff64s
DIR=exp/112-file-tests

.PHONY: test clean

test: test-stat-ff64 test-stat-ff64s
	@echo "  ----"
	@echo "  2 passed, 0 failed"

test-stat-ff64:
	@printf "%-48s" "stat file tests (ff64)"
	@cd ../.. && ./ff64- $(DIR)/stat-tests.ff 2>&1 | grep -q "^ok" && echo "PASS" || (cd ../.. && ./ff64- $(DIR)/stat-tests.ff 2>&1; echo "FAIL"; exit 1)

test-stat-ff64s:
	@printf "%-48s" "stat file tests (ff64s)"
	@cd ../.. && ./ff64s -f $(DIR)/stat-tests.ff 2>&1 | grep -q "^ok" && echo "PASS" || (cd ../.. && ./ff64s -f $(DIR)/stat-tests.ff 2>&1; echo "FAIL"; exit 1)

clean:
	@true
