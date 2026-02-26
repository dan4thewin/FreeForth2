SHELL=/bin/bash
## Experiment 053: Boot sequence, argc/argv, hidepvt, _boot
## Tests the boot infrastructure for standalone ff64

FF = ../../ff64

.PHONY: test
test:
	@PASS=0; FAIL=0; \
	echo "=== 053: Boot sequence ==="; \
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
	chk_err() { \
	  DESC="$$1"; shift; \
	  R=$$(run "$$@"); \
	  if echo "$$R" | grep -qF '<-error:'; then \
	    echo "  PASS: $$DESC"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$DESC (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	}; \
	echo "  --- _boot starts Forth REPL ---"; \
	chk '42' 'boot-arith' '42 . cr'; \
	chk '7' 'boot-addition' '3 4 + . cr'; \
	chk '49' 'boot-define' ': sq dup * ;' '7 sq . cr'; \
	echo "  --- hidepvt via _boot ---"; \
	chk_err 'pvt-hidden' '_auto'; \
	chk_err 'pvt-hidden-recover' '_recover'; \
	chk_err 'pvt-hidden-eval' '_eval'; \
	chk '42' 'pub-survives' '42 . cr'; \
	echo "  --- argc/argv ---"; \
	ARGC=$$(echo 'argc . cr' | timeout 5 $(FF) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | tr -d '[:space:]'); \
	if [ "$$ARGC" = "1" ]; then \
	  echo "  PASS: argc-count"; PASS=$$((PASS+1)); \
	else echo "  FAIL: argc-count (expected 1, got $$ARGC)"; FAIL=$$((FAIL+1)); fi; \
	R=$$(echo '0 argv type cr' | timeout 5 $(FF) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | head -1 | tr -s ' '); \
	if echo "$$R" | grep -qF 'ff64'; then \
	  echo "  PASS: argv0-is-ff64"; PASS=$$((PASS+1)); \
	else echo "  FAIL: argv0-is-ff64 (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	if [ "$$FAIL" -gt 0 ]; then exit 1; fi
