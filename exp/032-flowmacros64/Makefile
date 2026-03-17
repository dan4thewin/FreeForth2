FF = ../../ff64-
MACROS = macros.ff
TMP = /tmp/ff-032.ff

.PHONY: test clean

test:
	@echo "=== Exp 032: Flow control macros ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		desc="$$1"; input="$$2"; expect="$$3"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$($(FF) $(MACROS) $(TMP) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | tr -d '\n' | sed 's/ *$$//'); \
		if [ "$$actual" = "$$expect" ]; then \
			echo "PASS: $$desc"; PASS=$$((PASS+1)); \
		else \
			echo "FAIL: $$desc"; \
			echo "  expected: [$$expect]"; \
			echo "  got:      [$$actual]"; FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "BOOL: 0= true" \
		": t 0- 0= BOOL . cr ; 0 t ;" \
		"-1"; \
	run_test "BOOL: 0= false" \
		": t 0- 0= BOOL . cr ; 5 t ;" \
		"0"; \
	run_test "BOOL: < true" \
		": t < BOOL . cr ; 3 5 t ;" \
		"-1"; \
	run_test "BOOL: < false" \
		": t < BOOL . cr ; 5 3 t ;" \
		"0"; \
	run_test "BOOL: = true" \
		": t = BOOL . cr ; 7 7 t ;" \
		"-1"; \
	run_test "BOOL: = false" \
		": t = BOOL . cr ; 7 8 t ;" \
		"0"; \
	run_test "BOOL: > true" \
		": t > BOOL . cr ; 5 3 t ;" \
		"-1"; \
	run_test "BOOL: > false" \
		": t > BOOL . cr ; 3 5 t ;" \
		"0"; \
	run_test "SKIP: skips code" \
		": t skiptest . cr ; t ;" \
		"65"; \
	run_test "ELSE: true path" \
		": t 0- 0= IF 65 emit ELSE 66 emit THEN cr ; 0 t ;" \
		"A"; \
	run_test "ELSE: false path" \
		": t 0- 0= IF 65 emit ELSE 66 emit THEN cr ; 5 t ;" \
		"B"; \
	run_test "ELSE: macro composition" \
		": t ifelsetest emit cr ; 0 t 5 t ;" \
		"AB"; \
	run_test "CASE: first match" \
		": t 1 CASE 65 emit ELSE 2 CASE 66 emit ELSE 67 emit drop THEN THEN cr ; 1 t ;" \
		"A"; \
	run_test "CASE: second match" \
		": t 1 CASE 65 emit ELSE 2 CASE 66 emit ELSE 67 emit drop THEN THEN cr ; 2 t ;" \
		"B"; \
	run_test "CASE: default" \
		": t 1 CASE 65 emit ELSE 2 CASE 66 emit ELSE 67 emit drop THEN THEN cr ; 3 t ;" \
		"C"; \
	run_test "BOOL mixed: sequence" \
		": t 0- 0> BOOL . cr ; 5 t 0 t -3 t ;" \
		"-1 0 0"; \
	echo "---"; \
	echo "$$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

clean:
	@echo "Nothing to clean (uses production ff64)"

clean:
	@rm -f $(TMP)
