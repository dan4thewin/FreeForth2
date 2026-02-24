# Exp 036: Flow control migrated from assembly to Forth
# Tests that Forth-defined IF/THEN/ELSE/BEGIN/UNTIL/WHILE/REPEAT
# produce correct code after removing ~140 lines of assembly

FF=../../ff64
BOOT=../../ff64.boot

.PHONY: test clean

test:
	@echo "=== Exp 036: Flow control in Forth ==="
	@PASS=0; FAIL=0; \
	run_test() { \
		local desc="$$1" input="$$2" expect="$$3"; \
		result=$$(echo "$$input" | $(FF) -f $(BOOT) 2>/dev/null | head -1 | sed 's/^> //'); \
		if [ "$$result" = "$$expect" ]; then \
			echo "  PASS: $$desc"; \
			PASS=$$((PASS+1)); \
		else \
			echo "  FAIL: $$desc (expected '$$expect', got '$$result')"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run_test "IF true" ": t 0- 0= IF 42 THEN ; 0 t . ;" "42 ok"; \
	run_test "IF false" ": t 0- 0= IF 42 THEN ; 5 t . ;" "5 ok"; \
	run_test "IF/ELSE true" ": t 0- 0= IF 42 ELSE 99 THEN ; 0 t . ;" "42 ok"; \
	run_test "IF/ELSE false" ": t 0- 0= IF 42 ELSE 99 THEN ; 5 t . ;" "99 ok"; \
	run_test "IF less-than" ": t 10 < IF 1 ELSE 0 THEN ; 5 t . ;" "1 ok"; \
	run_test "IF greater" ": t 10 > IF 1 ELSE 0 THEN ; 15 t . ;" "1 ok"; \
	run_test "BEGIN/UNTIL" ": t BEGIN 1 - dup 0- 0= UNTIL ; 5 t . ;" "0 ok"; \
	run_test "BEGIN/WHILE/REPEAT" ": t BEGIN dup 0- 0> WHILE 1 - REPEAT ; 5 t . ;" "0 ok"; \
	run_test "nested IF" ": t 0- 0> IF 0- 10 > IF 99 ELSE 42 THEN ELSE 0 THEN ; 5 t . ;" "42 ok"; \
	run_test "WHILE countdown" ": t BEGIN dup 0- 0<> WHILE 1 - REPEAT ; 5 t . ;" "0 ok"; \
	run_test ";THEN early exit" ": t dup 0- 0= IF drop 42 ;THEN ; 0 t . ;" "42 ok"; \
	run_test ";THEN no exit" ": t dup 0- 0= IF drop 42 ;THEN ; 5 t . ;" "5 ok"; \
	run_test "0; zero" ": t 42 swap 0; drop 99 ; 0 t . ;" "42 ok"; \
	run_test "0; nonzero" ": t 42 swap 0; drop 99 ; 5 t . ;" "99 ok"; \
	run_test "BOOL eq" ": t 0- 0= BOOL ; 0 t . ;" "-1 ok"; \
	run_test "BOOL neq" ": t 0- 0= BOOL ; 5 t . ;" "0 ok"; \
	run_test "BOOL compare" ": t 3 < BOOL ; 1 t . ;" "-1 ok"; \
	run_test "SKIP/ELSE long" ": t 0- 0= IF 42 ELSE 1 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + THEN ; 5 t . ;" "45 ok"; \
	run_test "CASE match" ": t 0 CASE drop 10 ;THEN 1 CASE drop 20 ;THEN drop 99 ; 0 t . ;" "10 ok"; \
	run_test "CASE nomatch" ": t 0 CASE drop 10 ;THEN 1 CASE drop 20 ;THEN drop 99 ; 2 t . ;" "99 ok"; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

clean:
	@echo "Nothing to clean"
