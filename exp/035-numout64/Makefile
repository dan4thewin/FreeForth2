# Exp 035: Number Output with Base Variable
# Tests the Forth-defined number output chain that replaces assembly _dot

FF=../../ff64
BOOT=../../ff64.boot
MACROS=macros.ff

.PHONY: test clean

test:
	@echo "=== Exp 035: Number output ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1" input="$$2" expect="$$3"; \
		result=$$(echo "$$input" | $(FF) -f $(BOOT) -f $(MACROS) 2>/dev/null | head -1 | sed 's/^> //'); \
		if [ "$$result" = "$$expect" ]; then \
			echo "  PASS: $$desc"; \
			PASS=$$((PASS+1)); \
		else \
			echo "  FAIL: $$desc (expected '$$expect', got '$$result')"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "zero" "0 . ;" "0 ok"; \
	run_test "positive" "42 . ;" "42 ok"; \
	run_test "negative" "-42 . ;" "-42 ok"; \
	run_test "one" "1 . ;" "1 ok"; \
	run_test "minus one" "-1 . ;" "-1 ok"; \
	run_test "large" "123456789 . ;" "123456789 ok"; \
	run_test "hex output" '$$FF .x ;' "ff ok"; \
	run_test "hex deadbeef" '$$DEADBEEF .x ;' "deadbeef ok"; \
	run_test "decimal explicit" "42 .dec ;" "42 ok"; \
	run_test "base switch to hex" "16 base! 255 . 10 base! ;" "ff ok"; \
	run_test "base restored" "16 base! 255 . 10 base! 255 . ;" "ff 255 ok"; \
	run_test "unsigned hex" '$$FF .ux ;' "ff ok"; \
	run_test "unsigned decimal" "42 .u ;" "42 ok"; \
	run_test "multi-digit" "100 . ;" "100 ok"; \
	run_test "three digits" "999 . ;" "999 ok"; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

clean:
	@echo "Nothing to clean"
