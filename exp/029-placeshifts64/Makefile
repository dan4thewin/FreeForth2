FF = ../../ff64
BOOT = ../../ff64.boot
MACROS = macros.ff

.PHONY: test clean

test:
	@echo "=== Exp 029: place/cmove and shift arithmetic ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		desc="$$1"; input="$$2"; expect="$$3"; \
		actual=$$(printf '%s\n' "$$input" | cat $(MACROS) - | $(FF) -f $(BOOT) 2>/dev/null | sed '/^> ok$$/d;/^ok$$/d;/^> *$$/d;s/^> //' | tr -d '\n' | sed 's/ *$$//'); \
		if [ "$$actual" = "$$expect" ]; then \
			echo "PASS: $$desc"; PASS=$$((PASS+1)); \
		else \
			echo "FAIL: $$desc"; \
			echo "  expected: [$$expect]"; \
			echo "  got:      [$$actual]"; FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "2*: double" \
		"25 2* . cr ;" \
		"50"; \
	run_test "2/: halve" \
		"50 2/ . cr ;" \
		"25"; \
	run_test "2/: negative" \
		"-7 2/ . cr ;" \
		"-4"; \
	run_test "4+: add 4" \
		"100 4+ . cr ;" \
		"104"; \
	run_test "4*: quadruple" \
		"10 4* . cr ;" \
		"40"; \
	run_test "4/: quarter" \
		"40 4/ . cr ;" \
		"10"; \
	run_test "8*: octuple" \
		"10 8* . cr ;" \
		"80"; \
	run_test "8/: eighth" \
		"80 8/ . cr ;" \
		"10"; \
	run_test "place: copy 5 bytes" \
		"variable src variable dst 65 src c! 66 src 1 + c! 67 src 2 + c! 68 src 3 + c! 69 src 4 + c! src 5 dst place dst c@ . dst 1 + c@ . dst 2 + c@ . cr ;" \
		"65 66 67"; \
	run_test "cmove: copy 3 bytes" \
		"variable s variable d 72 s c! 73 s 1 + c! 74 s 2 + c! s d 3 cmove d c@ . d 1 + c@ . d 2 + c@ . cr ;" \
		"72 73 74"; \
	run_test "cmove: different data" \
		"variable a variable b 48 a c! 49 a 1 + c! a b 2 cmove b c@ . b 1 + c@ . cr ;" \
		"48 49"; \
	run_test "cmove: zero count" \
		"variable p variable q 99 p c! 0 q c! p q 0 cmove q c@ . cr ;" \
		"0"; \
	echo "---"; \
	echo "$$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

clean:
	@echo "Nothing to clean (uses production ff64)"
