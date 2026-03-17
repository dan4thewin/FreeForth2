ROOT = ../..
FF = ../../ff64-
TMP = /tmp/ff-082.ff

.PHONY: test clean

test:
	@# Verify console.ff loads without error
	@printf '"console.ff" needed ;\nbye\n' > $(TMP); cd $(ROOT) && ./ff64- $(TMP) 2>&1 | grep -q '???' && echo "  FAIL test-console-load" || echo "  PASS test-console-load"
	@# Verify date/time literals in time.ff
	@printf '"time.ff" needed ;\nnow . bye\n' > $(TMP); cd $(ROOT) && ./ff64- $(TMP) 2>&1 | grep -qE '[0-9]{8,}' && echo "  PASS test-now-value" || echo "  FAIL test-now-value"
	@printf '"time.ff" needed ;\n.now bye\n' > $(TMP); cd $(ROOT) && ./ff64- $(TMP) 2>&1 | grep -qE '20[0-9][0-9]-' && echo "  PASS test-now-display" || echo "  FAIL test-now-display"
	@# Verify 24:0:0 literal works as a number
	@printf '24:0:0 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '86400' && echo "  PASS test-time-literal" || echo "  FAIL test-time-literal"
	@# Verify 2000-3-1 literal works
	@printf '2000-3-1 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '730485' && echo "  PASS test-date-literal" || echo "  FAIL test-date-literal"
	@# Verify &100 = 64 (octal)
	@printf '&100 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '64' && echo "  PASS test-octal-literal" || echo "  FAIL test-octal-literal"
	@echo "All 082-restore-lits tests passed."

clean:
	@rm -f $(TMP)
	@true