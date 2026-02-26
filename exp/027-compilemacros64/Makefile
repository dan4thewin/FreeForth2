BIN = ../../ff64

all: $(BIN)

$(BIN):
	$(MAKE) -C ../.. ff64

test: $(BIN)
	@echo "=== 027-compilemacros64 ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1"; local input="$$2"; local expected="$$3"; \
		actual=$$(printf '%s\n' "$$input" | ./$(BIN) -f macros.ff 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | tr -d '\n' | sed 's/ *$$//'); \
		if [ "$$actual" = "$$expected" ]; then \
			PASS=$$((PASS+1)); \
		else \
			echo "FAIL: $$desc"; \
			echo "  expected: [$$expected]"; \
			echo "  actual:   [$$actual]"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "c, advance"     "here 65 c, here swap - . cr ;"                "1"; \
	run_test "c, value"       "here 65 c, c@ . cr ;"                         "65"; \
	run_test "c, two bytes"   "here 72 c, 73 c, dup c@ . 1 + c@ . cr ;"     "72 73"; \
	run_test "w, advance"     "here 4660 w, here swap - . cr ;"              "2"; \
	run_test "w, value"       "here 4660 w, w@ . cr ;"                       "4660"; \
	run_test ", advance"      "here 42 , here swap - . cr ;"                 "8"; \
	run_test ", value"        "here 42 , @ . cr ;"                           "42"; \
	run_test ", big value"    "here 1000000 , @ . cr ;"                      "1000000"; \
	if [ $$FAIL -eq 0 ]; then echo "PASS"; else echo "$$FAIL FAILED ($$PASS passed)"; exit 1; fi
