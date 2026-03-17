SHELL=/bin/bash
## Experiment 053: Boot sequence, argc/argv, hidepvt, _boot
## Tests the boot infrastructure for standalone ff64

FF = ../../ff64-
TMP = /tmp/ff-053.ff

.PHONY: test clean
test:
	@PASS=0; FAIL=0; \
	echo "=== 053: Boot sequence ==="; \
	run() { \
	  printf '%s\n' "$$@" > $(TMP); \
	  timeout 5 $(FF) $(TMP) 2>&1; \
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
	chk_not0() { \
	  DESC="$$1"; shift; \
	  R=$$(run "$$@" | head -1 | tr -d '[:space:]'); \
	  if [ "$$R" != "0" ] && [ -n "$$R" ]; then \
	    echo "  PASS: $$DESC"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$DESC (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	}; \
	echo "  --- _boot starts Forth REPL ---"; \
	chk '42' 'boot-arith' '42 . cr ;'; \
	chk '7' 'boot-addition' '3 4 + . cr ;'; \
	chk '49' 'boot-define' ': sq dup * ; 7 sq . cr ;'; \
	echo "  --- hidepvt ---"; \
	chk_not0 'pvt-hidden' 'hidepvt` "_auto" find nip . cr ;'; \
	chk_not0 'pvt-hidden-recover' 'hidepvt` "_recover" find nip . cr ;'; \
	chk_not0 'pvt-hidden-eval' 'hidepvt` "_eval" find nip . cr ;'; \
	chk '42' 'pub-survives' 'hidepvt` 42 . cr ;'; \
	echo "  --- argc/argv ---"; \
	echo 'argc . cr ;' > $(TMP); \
	ARGC=$$(timeout 5 $(FF) $(TMP) 2>/dev/null | head -1 | tr -d '[:space:]'); \
	if [ "$$ARGC" = "3" ]; then \
	  echo "  PASS: argc-count"; PASS=$$((PASS+1)); \
	else echo "  FAIL: argc-count (expected 3, got $$ARGC)"; FAIL=$$((FAIL+1)); fi; \
	echo '0 argv type cr ;' > $(TMP); \
	R=$$(timeout 5 $(FF) $(TMP) 2>/dev/null | head -1 | tr -s ' '); \
	if echo "$$R" | grep -qF 'ff64'; then \
	  echo "  PASS: argv0-is-ff64"; PASS=$$((PASS+1)); \
	else echo "  FAIL: argv0-is-ff64 (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	if [ "$$FAIL" -gt 0 ]; then exit 1; fi

clean:
	@rm -f $(TMP)
