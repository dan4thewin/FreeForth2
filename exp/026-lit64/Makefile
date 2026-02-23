BIN = ../../ff64
BOOT = ../../ff64.boot

all: $(BIN)

$(BIN):
	$(MAKE) -C ../.. ff64

test: $(BIN)
	@echo "=== 026-lit64 ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1"; local input="$$2"; local expected="$$3"; \
		actual=$$(printf '%s\n' "$$input" | cat macros.ff - | ./$(BIN) -f $(BOOT) 2>/dev/null | sed '/^> ok$$/d;/^ok$$/d;/^> *$$/d;s/^> //' | tr -d '\n' | sed 's/ *$$//'); \
		if [ "$$actual" = "$$expected" ]; then \
			PASS=$$((PASS+1)); \
		else \
			echo "FAIL: $$desc"; \
			echo "  expected: [$$expected]"; \
			echo "  actual:   [$$actual]"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "lit byte"       "const42 . cr ;"                          "42"; \
	run_test "lit 32-bit"     "biglit . cr ;"                           "1000000"; \
	run_test "lit 64-bit"     "hugelit . cr ;"                          "4294967296"; \
	run_test "lit negative"   "neg1 . cr ;"                             "-1"; \
	run_test "lit zero"       ": z0\` 0 lit\` ; z0 . cr ;"             "0"; \
	run_test "lit 127"        ": z127\` 127 lit\` ; z127 . cr ;"       "127"; \
	run_test "lit 128"        ": z128\` 128 lit\` ; z128 . cr ;"       "128"; \
	run_test "lit -128"       ": zm128\` -128 lit\` ; zm128 . cr ;"    "-128"; \
	run_test "off"            "variable x 42 x ! x off x @ . cr ;"     "0"; \
	run_test "on"             "variable x 0 x ! x on x @ . cr ;"       "-1"; \
	run_test "off-on cycle"   "variable x x on x @ . x off x @ . cr ;" "-1 0"; \
	run_test "lit + arith"    ": add10\` 10 lit\` +\` ; 5 add10 . cr ;" "15"; \
	if [ $$FAIL -eq 0 ]; then echo "PASS"; else echo "$$FAIL FAILED ($$PASS passed)"; exit 1; fi
