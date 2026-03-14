FF = ../../ff64

.PHONY: test
test:
	@PASS=0; FAIL=0; \
	echo "=== 051: REPL auto-execute ==="; \
	run() { printf '%s\n' "$$1" | timeout 2 $(FF) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | tr '\n' ' ' | sed 's/  */ /g;s/ $$//'; }; \
	chk() { \
	  R=$$(run "$$1"); \
	  if [ "$$R" = "$$2" ]; then \
	    echo "  PASS: $$3"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$3 (expected '$$2', got '$$R')"; FAIL=$$((FAIL+1)); fi; \
	}; \
	echo "  --- auto-execute without semicolon ---"; \
	chk '42 . cr' '42' 'print literal'; \
	chk '3 4 + . cr' '7' 'arithmetic'; \
	chk '65 emit 10 emit' 'A' 'emit char'; \
	echo "  --- auto-execute with semicolon ---"; \
	chk '42 . cr ;' '42' 'print with semicolon'; \
	echo "  --- define and call ---"; \
	chk ': sq dup * ; 5 sq . cr' '25' 'define and call same line'; \
	echo "  --- depth clean ---"; \
	chk 'depth . cr' '0' 'depth is 0'; \
	echo "  ----"; \
	echo "$$PASS passed, $$FAIL failed"; \
	if [ "$$FAIL" -gt 0 ]; then exit 1; fi

