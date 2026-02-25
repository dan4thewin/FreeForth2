## Experiment 053: Boot sequence, argc/argv, hidepvt, _boot
## Tests the boot infrastructure for standalone ff64

FF = ../../ff64
BOOT = ../../ff64.boot
LAUNCH_BOOT = /tmp/exp053_boot.ff
LAUNCH_TOP = /tmp/exp053_top.ff

.PHONY: test
test:
	@PASS=0; FAIL=0; \
	echo "=== 053: Boot sequence ==="; \
	printf '_boot ;\n' > $(LAUNCH_BOOT); \
	printf '_top ;\n' > $(LAUNCH_TOP); \
	pad() { printf '%-80s' "$$1"; }; \
	run_boot() { \
	  INPUT=""; \
	  for line; do INPUT="$$INPUT$$(pad "$$line")"; done; \
	  printf '%s' "$$INPUT" | timeout 5 $(FF) -f $(BOOT) -f $(LAUNCH_BOOT) 2>&1; \
	}; \
	run_top() { \
	  INPUT=""; \
	  for line; do INPUT="$$INPUT$$(pad "$$line")"; done; \
	  printf '%s' "$$INPUT" | timeout 5 $(FF) -f $(BOOT) -f $(LAUNCH_TOP) 2>&1; \
	}; \
	chk() { \
	  PAT="$$1"; shift; DESC="$$1"; shift; \
	  R=$$(run_boot "$$@"); \
	  if echo "$$R" | grep -qF "$$PAT"; then \
	    echo "  PASS: $$DESC"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$DESC (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	}; \
	chk_top() { \
	  PAT="$$1"; shift; DESC="$$1"; shift; \
	  R=$$(run_top "$$@"); \
	  if echo "$$R" | grep -qF "$$PAT"; then \
	    echo "  PASS: $$DESC"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$DESC (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	}; \
	chk_err() { \
	  DESC="$$1"; shift; \
	  R=$$(run_boot "$$@"); \
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
	echo "  --- _top without hidepvt ---"; \
	chk_top '42' 'top-arith' '42 . cr'; \
	echo "  --- argc/argv ---"; \
	R=$$(echo '' | timeout 5 $(FF) -f $(BOOT) 2>/dev/null | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -d '[:space:]'); \
	ARGC=$$(echo 'argc . cr' | timeout 5 $(FF) -f $(BOOT) 2>/dev/null | sed 's/^> //;/^ok$$/d;/^>$$/d' | tr -d '[:space:]'); \
	if [ "$$ARGC" = "3" ]; then \
	  echo "  PASS: argc-count"; PASS=$$((PASS+1)); \
	else echo "  FAIL: argc-count (expected 3, got $$ARGC)"; FAIL=$$((FAIL+1)); fi; \
	R=$$(echo '0 argv type cr' | timeout 5 $(FF) -f $(BOOT) 2>/dev/null | sed 's/^> //;/^ok$$/d;/^>$$/d' | head -1 | tr -s ' '); \
	if echo "$$R" | grep -qF 'ff64'; then \
	  echo "  PASS: argv0-is-ff64"; PASS=$$((PASS+1)); \
	else echo "  FAIL: argv0-is-ff64 (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	rm -f $(LAUNCH_BOOT) $(LAUNCH_TOP); \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	if [ "$$FAIL" -gt 0 ]; then exit 1; fi
