# Exp 035: Number Output with Base Variable
# Tests the Forth-defined number output chain that replaces assembly _dot

FF=../../ff64-
MACROS=macros.ff
TMP = /tmp/ff-035.ff

.PHONY: test clean

test:
	@echo "=== Exp 035: Number output ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1" input="$$2" expect="$$3"; \
		echo "$$input" > $(TMP); \
		result=$$($(FF) $(MACROS) $(TMP) 2>/dev/null | head -1 | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//'); \
		if [ "$$result" = "$$expect" ]; then \
			echo "  PASS: $$desc"; \
			PASS=$$((PASS+1)); \
		else \
			echo "  FAIL: $$desc (expected '$$expect', got '$$result')"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "zero" "0 . ;" "0"; \
	run_test "positive" "42 . ;" "42"; \
	run_test "negative" "-42 . ;" "-42"; \
	run_test "one" "1 . ;" "1"; \
	run_test "minus one" "-1 . ;" "-1"; \
	run_test "large" "123456789 . ;" "123456789"; \
	run_test "hex output" '$$FF .x ;' "ff"; \
	run_test "hex deadbeef" '$$DEADBEEF .x ;' "deadbeef"; \
	run_test "decimal explicit" "42 .dec ;" "42"; \
	run_test "base switch to hex" "16 base! 255 . 10 base! ;" "ff"; \
	run_test "base restored" "16 base! 255 . 10 base! 255 . ;" "ff 255"; \
	run_test "unsigned hex" '$$FF .ux ;' "ff"; \
	run_test "unsigned decimal" "42 .u ;" "42"; \
	run_test "multi-digit" "100 . ;" "100"; \
	run_test "three digits" "999 . ;" "999"; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

clean:
	@echo "Nothing to clean"

clean:
	@rm -f $(TMP)
