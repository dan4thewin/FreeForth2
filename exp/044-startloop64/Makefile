FF=../../ff64
BOOT=../../ff64.boot
SHELL=/bin/bash

test: $(FF)
	@echo "=== Exp 044: START/ENTER/BREAK/END ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(echo "$$2" | $(FF) -f $(BOOT) 2>/dev/null); \
		if echo "$$result" | grep -qF -- "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; \
			echo "    Expected: $$3"; \
			echo "    Got: $$result"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	run "simple start-end countdown" \
		': t 5 START 1- dup . space 0- 0= IF BREAK END drop cr ; t ;' \
		'4  3  2  1  0'; \
	run "start-enter countdown" \
		': t 5 START 1- dup . space ENTER 0- 0= IF BREAK END drop cr ; t ;' \
		'4  3  2  1  0'; \
	run "start-enter first-skip countup" \
		': t 0 START 1+ dup . space ENTER dup 5 - 0- 0= IF drop BREAK drop END drop cr ; t ;' \
		'1  2  3  4  5'; \
	run "two-breaks first hit" \
		': t 10 START 1- dup . space dup 7 - 0- 0= IF drop BREAK drop 0- 0= IF BREAK END cr ; t ;' \
		'9  8  7'; \
	run "three-breaks third hit" \
		': t 10 START 1- dup . space dup 1 - 0- 0= IF drop BREAK drop dup 3 - 0- 0= IF drop BREAK drop dup 7 - 0- 0= IF drop BREAK drop 0- 0= IF BREAK END cr ; t ;' \
		'9  8  7'; \
	run "nested inline start-end" \
		': t 3 START dup . space 1- 3 START dup . 1- 0- 0= IF BREAK END drop 0- 0= IF BREAK END drop cr ; t ;' \
		'3  3 2 1 2  3 2 1 1  3 2 1'; \
	run "nested via separate words" \
		': inner 3 START dup . 1- 0- 0= IF BREAK END drop ; : outer 3 START dup . space 1- inner 32 emit 0- 0= IF BREAK END drop cr ; outer ;' \
		'3  3 2 1  2  3 2 1  1  3 2 1'; \
	run "start-end no iterations" \
		': t 0 START 0- 0= IF BREAK 1+ END . cr ; t ;' \
		'0'; \
	run "mrk-save-restore" \
		': t 5 START 1- 0- 0= IF BREAK END drop 3 START 1- 0- 0= IF BREAK END drop 42 . cr ; t ;' \
		'42'; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"

.PHONY: test
