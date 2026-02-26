FF = ../../ff64
BOOT = ../../ff64.boot
MACROS = macros.ff

.PHONY: test clean

test:
	@echo "=== Exp 031: Utility words and flow control macros ==="
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
	run_test ";;: compile ret mid-definition" \
		": t 42 . ;; 99 . ; t cr ;" \
		"42"; \
	run_test "0;: zero returns early" \
		": t 0; 99 . cr ; 0 t ;" \
		""; \
	run_test "0;: non-zero continues" \
		": t 0; 99 . cr ; 5 t ;" \
		"99"; \
	run_test "0;: mixed calls 5 0 3" \
		": t 0; 99 . cr ; 5 t 0 t 3 t ;" \
		"99 99"; \
	run_test "0;: mixed calls 0 5 0" \
		": t 0; 99 . cr ; 0 t 5 t 0 t ;" \
		"99"; \
	run_test "0<>;: non-zero returns early" \
		": t 0<>; 88 . cr ; 5 t ;" \
		""; \
	run_test "0<>;: zero continues" \
		": t 0<>; 88 . cr ; 0 t ;" \
		"88"; \
	run_test "?dup: non-zero dups" \
		"5 ?dup 0- 0<> IF + THEN . cr ;" \
		"10"; \
	run_test "?dup: zero no dup" \
		"0 ?dup 0- 0<> IF + THEN . cr ;" \
		"0"; \
	run_test "type: print ABC" \
		"variable buf 65 buf c! 66 buf 1 + c! 67 buf 2 + c! buf 3 type cr ;" \
		"ABC"; \
	run_test "type: empty string" \
		"here 0 type cr ;" \
		""; \
	run_test "type: single char" \
		"variable b 90 b c! b 1 type cr ;" \
		"Z"; \
	run_test "c@+: counted string" \
		"variable buf 8 allot 3 buf c! 65 buf 1 + c! 66 buf 2 + c! 67 buf 3 + c! buf c@+ type cr ;" \
		"ABC"; \
	run_test "fill: fill 5 bytes" \
		"variable buf 8 allot buf 5 42 fill buf c@ . buf 1 + c@ . buf 4 + c@ . cr ;" \
		"42 42 42"; \
	run_test "erase: zero 3 bytes" \
		"variable buf 8 allot buf 3 65 fill buf 3 erase buf c@ . buf 1 + c@ . buf 2 + c@ . cr ;" \
		"0 0 0"; \
	run_test "reverse: turns call into jmp" \
		": hi 72 emit 73 emit ; : t reverse hi cr ; t ;" \
		"HI"; \
	echo "---"; \
	echo "$$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

clean:
	@echo "Nothing to clean (uses production ff64)"
