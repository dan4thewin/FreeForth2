FF = ../../ff64
BOOT = ../../ff64.boot
MACROS = macros.ff

.PHONY: test clean

test:
	@echo "=== Exp 033: Dictionary manipulation ==="
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
	run_test "h.ct constant" \
		"h.ct . cr ;" \
		"8"; \
	run_test "h.sz constant" \
		"h.sz . cr ;" \
		"9"; \
	run_test "h.nm constant" \
		"h.nm . cr ;" \
		"10"; \
	run_test "H@ returns non-zero" \
		"H@ 0- 0<> BOOL . cr ;" \
		"-1"; \
	run_test "anon@ returns value" \
		"anon@ drop ;" \
		""; \
	run_test "H @ ct of variable (ct=1)" \
		"variable tv H@ 8 + c@ 7 & . cr ;" \
		"1"; \
	run_test "H @ ct of colon def (ct=0)" \
		": tw ; H@ 8 + c@ 7 & . cr ;" \
		"0"; \
	run_test "H @ h.sz name length 2" \
		": tw ; H@ 9 + c@ . cr ;" \
		"2"; \
	run_test "H @ h.sz name length 5" \
		": abcde ; H@ 9 + c@ . cr ;" \
		"5"; \
	run_test "H @ h.nm first char" \
		": xy ; H@ 10 + c@ . cr ;" \
		"120"; \
	run_test "ct|! ORs value into ct" \
		": tw ; 4 H@ ct|! H@ 8 + c@ 7 & . cr ;" \
		"4"; \
	run_test "pvt sets bit 3" \
		": tw ; pvt H@ 8 + c@ 8 & . cr ;" \
		"8"; \
	echo ""; \
	echo "Results: $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0

clean:
	@echo "Nothing to clean"
