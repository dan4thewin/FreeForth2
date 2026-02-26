SHELL=/bin/bash

## Experiment 052: Forth-based REPL (_top)
## Tests _top: catch/throw error handling, error recovery, prompt, definitions

FF = ../../ff64

.PHONY: test
test:
	@PASS=0; FAIL=0; \
	echo "=== 052: Forth REPL (_top) ==="; \
	NL=$$'\n'; \
	run() { \
	  INPUT=""; \
	  for line; do INPUT="$${INPUT}$$(printf '%-80s' "$$line")$$NL"; done; \
	  printf '%s' "$$INPUT" | timeout 5 $(FF) 2>&1; \
	}; \
	chk() { \
	  PAT="$$1"; shift; DESC="$$1"; shift; \
	  R=$$(run "$$@"); \
	  if echo "$$R" | grep -qF "$$PAT"; then \
	    echo "  PASS: $$DESC"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$DESC (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	}; \
	chkre() { \
	  PAT="$$1"; shift; DESC="$$1"; shift; \
	  R=$$(run "$$@"); \
	  if echo "$$R" | grep -q "$$PAT"; then \
	    echo "  PASS: $$DESC"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$DESC (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	}; \
	echo "  --- basic evaluation ---"; \
	chk '42' 'literal-print' '42 . cr'; \
	chk '7' 'addition' '3 4 + . cr'; \
	chk '20' 'multi-define' ': double dup + ;' ': quad double double ;' '5 quad . cr'; \
	echo "  --- error handling ---"; \
	chk '<-error: ???' 'error-message' 'badword'; \
	chk 'badword' 'error-context' 'badword'; \
	chk '99' 'error-recovery' 'badword' '99 . cr'; \
	echo "  --- stack balance ---"; \
	chk ' 0' 'depth-after-success' '42 drop' 'depth . cr'; \
	chk ' 0' 'depth-after-error' 'badword' 'depth . cr'; \
	echo "  --- prompt ---"; \
	chkre ' 1;' 'prompt-shows-depth' '42' '. cr'; \
	echo "  --- error cleanup ---"; \
	chk '42' 'error-cleanup-runs' ': broken badword ;' '42 . cr'; \
	chk ' 0' 'error-cleanup-depth' ': broken badword ;' '42 . cr' 'depth . cr'; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	if [ "$$FAIL" -gt 0 ]; then exit 1; fi
