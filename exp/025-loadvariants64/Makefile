BIN = ../../ff64-
TMP = /tmp/ff-025.ff

all: $(BIN)

$(BIN):
	$(MAKE) -C ../.. ff64

test: $(BIN)
	@echo "=== 025-loadvariants64 ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1"; local input="$$2"; local expected="$$3"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(./$(BIN) macros.ff $(TMP) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | tr -d '\n' | sed 's/ *$$//'); \
		if [ "$$actual" = "$$expected" ]; then \
			PASS=$$((PASS+1)); \
		else \
			echo "FAIL: $$desc"; \
			echo "  expected: [$$expected]"; \
			echo "  actual:   [$$actual]"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "cs@ positive"     "variable x 127 x c! x cs@ . cr ;"         "127"; \
	run_test "cs@ negative"     "variable x 255 x c! x cs@ . cr ;"         "-1"; \
	run_test "cs@ sign"         "variable x 128 x c! x cs@ . cr ;"         "-128"; \
	run_test "w@ basic"         "variable x 4660 x ! x w@ . cr ;"          "4660"; \
	run_test "ws@ positive"     "variable x 4660 x ! x ws@ . cr ;"         "4660"; \
	run_test "ws@ negative"     "variable x 65535 x ! x ws@ . cr ;"        "-1"; \
	run_test "dup@ preserves"   "variable x 42 x ! x dup@ swap drop . cr ;" "42"; \
	run_test "dup@ fetches"     "variable x 99 x ! x dup@ drop @ . cr ;"   "99"; \
	run_test "dupc@ basic"      "variable x 171 x ! x dupc@ . drop cr ;"   "171"; \
	run_test "dupw@ basic"      "variable x 4660 x ! x dupw@ . drop cr ;"  "4660"; \
	run_test "bswap"            "1 bswap . cr ;"                            "72057594037927936"; \
	run_test "flip"             "256 flip . cr ;"                           "1"; \
	run_test "8+"               "100 8+ . cr ;"                             "108"; \
	run_test "8-"               "100 8- . cr ;"                             "92"; \
	run_test "c@+ basic"        "variable b 65 b c! b c@+ . drop cr ;"     "65"; \
	run_test "c@+ chained"     "variable b 65 b c! 66 b 1 + c! b c@+ swap c@+ nip . . cr ;" "66 65"; \
	run_test "bounds"           "4096 256 bounds . . cr ;"                  "4096 4352"; \
	run_test "w! store"         "variable x 0 x ! 4660 x w! x @ . cr ;"    "4660"; \
	run_test "2! 2@"            "variable d 0 , 10 20 d 2! d 2@ . . cr ;"  "20 10"; \
	if [ $$FAIL -eq 0 ]; then echo "PASS"; else echo "$$FAIL FAILED ($$PASS passed)"; exit 1; fi

clean:
	@rm -f $(TMP)
