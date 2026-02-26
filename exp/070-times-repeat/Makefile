FF = ../../ff64

.PHONY: test
test:
	@echo "=== Exp 070: TIMES...REPEAT compatibility ==="
	@PASS=0; FAIL=0; \
	run() { \
		result=$$(printf '%s\n' "$$2" | $(FF) 2>/dev/null \
		  | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' \
		  | grep -v '^$$' | tail -1); \
		if [ "$$result" = "$$3" ]; then \
			echo "  PASS: $$1"; PASS=$$((PASS+1)); \
		else \
			echo "  FAIL: $$1 (expected '$$3', got '$$result')"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	}; \
	run "TIMES REPEAT basic" \
		': t 3 TIMES 42 . REPEAT cr ; t ;' \
		'42 42 42 '; \
	run "TIMES LOOP still works" \
		': t 3 TIMES 42 . LOOP cr ; t ;' \
		'42 42 42 '; \
	run "TIMES REPEAT zero count" \
		': t 0 TIMES 42 . REPEAT cr ; t ;' \
		''; \
	run "TIMES REPEAT with r" \
		': t 4 TIMES r . REPEAT cr ; t ;' \
		'3 2 1 0 '; \
	run "TIMES REPEAT nested" \
		': t 2 TIMES 3 TIMES 1 . REPEAT REPEAT cr ; t ;' \
		'1 1 1 1 1 1 '; \
	run "TIMES REPEAT stack clean" \
		': t 99 3 TIMES drop 42 REPEAT . cr ; t ;' \
		'42 '; \
	run "BEGIN WHILE REPEAT unaffected" \
		': t BEGIN dup 0- 0> WHILE 1- REPEAT ; 5 t . cr ;' \
		'0 '; \
	run "BEGIN UNTIL unaffected" \
		': t BEGIN 1- dup 0- 0= UNTIL ; 3 t . cr ;' \
		'0 '; \
	run "BEGIN AGAIN unaffected" \
		': t BEGIN 1- dup 0- 0= IF ;THEN AGAIN ; 3 t . cr ;' \
		'0 '; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0
