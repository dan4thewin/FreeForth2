FF=../../ff64
SHELL=/bin/bash

test: $(FF)
	@echo "=== Exp 044: Flow control: BEGIN/CASE/BREAK/END and loops ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(echo "$$2" | $(FF) 2>/dev/null); \
		if echo "$$result" | grep -qF -- "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; \
			echo "    Expected: $$3"; \
			echo "    Got: $$result"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	run "begin-again loop with break exit" \
		': t 5 BEGIN 1- dup . space 0- 0= IF BREAK AGAIN drop cr ; t ;' \
		'4  3  2  1  0'; \
	run "start-enter-while-repeat countdown" \
		': t 5 START 1- dup . space ENTER dup 0- 0<> drop WHILE REPEAT drop cr ; t ;' \
		'4  3  2  1  0'; \
	run "begin-while-repeat countup" \
		': t 0 START 1+ dup . space ENTER dup 5 - 0- 0<> drop WHILE REPEAT drop cr ; t ;' \
		'1  2  3  4  5'; \
	run "begin-case-break-end dispatch" \
		': t BEGIN 1 CASE 10 BREAK 2 CASE 20 BREAK drop 99 END ; 1 t .\ 32 emit 2 t .\ 32 emit 7 t .\ cr ;' \
		'10 20 99'; \
	run "nested begin-case-break-end" \
		': inner BEGIN 1 CASE 10 BREAK 2 CASE 20 BREAK drop 0 END ; : t inner .\ cr ; 1 t 2 t 7 t ;' \
		'10'; \
	run "begin-while-repeat loop" \
		': t 5 BEGIN 1- dup . space dup 0- 0<> drop WHILE REPEAT drop cr ; t ;' \
		'4  3  2  1  0'; \
	run "nested begin-while-repeat" \
		': inner 3 BEGIN 1- dup . dup 0- 0<> drop WHILE REPEAT drop ; : outer 3 BEGIN dup . space 1- inner 32 emit dup 0- 0<> drop WHILE REPEAT drop cr ; outer ;' \
		'3  2 1 0  2  2 1 0  1  2 1 0'; \
	run "begin-end no-loop dispatch" \
		': t 0 BEGIN 0- 0= IF BREAK 1+ END . cr ; t ;' \
		'0'; \
	run "mrk-save-restore nested" \
		': t 5 BEGIN 1- 0- 0= IF BREAK AGAIN drop 3 BEGIN 1- 0- 0= IF BREAK AGAIN drop 42 . cr ; t ;' \
		'42'; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	test $$fail -eq 0

.PHONY: test
