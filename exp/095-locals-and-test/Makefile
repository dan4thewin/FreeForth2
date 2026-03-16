FF = ../../ff64-
SHELL := /bin/bash
TOP := $(shell cd ../.. && pwd)

.PHONY: test
test:
	@echo "=== Exp 095: locals and test framework ==="
	@cd $(TOP) && output=$$(timeout 10 ./ff64- \
		exp/095-locals-and-test/test-locals.ff 2>/dev/null | \
		sed 's/\x1b\[[0-9;]*m//g'); \
	echo "$$output"; \
	echo "$$output" | tail -1 | grep -q PASSED
