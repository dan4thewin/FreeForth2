FF = ../../ff64-
TMP = /tmp/ff-049.ff
.PHONY: test
test:
	@PASS=0; FAIL=0; \
	echo "=== 049-hidepvt64 ==="; \
	run() { printf '%s\n' "$$1" > $(TMP); $(FF) $(TMP) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | grep -v '^$$' | tail -1; }; \
	chk() { \
	  R=$$(run "$$1"); \
	  if [ "$$R" = "$$2" ]; then \
	    echo "  PASS: $$3"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$3 (expected '$$2', got '$$R')"; FAIL=$$((FAIL+1)); fi; \
	}; \
	echo "  --- hidepvt ---"; \
	chk ':. secret 42 ; : pub secret . cr ; pub ;' '42 ' 'pvt word callable'; \
	chk ':. secret 42 ; : pub secret . cr ; hidepvt pub ;' '42 ' 'pub works after hidepvt'; \
	R=$$(printf '%s\n' ':. secret 42 ; hidepvt secret . cr ;' \
	  > $(TMP); $(FF) $(TMP) 2>&1 | head -1); \
	if echo "$$R" | grep -q 'error:'; then \
	  echo "  PASS: secret hidden after hidepvt"; PASS=$$((PASS+1)); \
	else echo "  FAIL: secret should be hidden (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	chk 'hide @ . cr ;' '-1 ' 'hide initially on'; \
	R=$$(printf '%s\n' '0 hide ! ;' 'hidepvt ;' '42 . cr ;' \
	  > $(TMP); $(FF) $(TMP) 2>/dev/null | sed 's/ *[0-9-]*; *//g' | grep -v '^$$' | tail -1); \
	if [ "$$R" = "42 " ]; then \
	  echo "  PASS: hide=0 disables hidepvt"; PASS=$$((PASS+1)); \
	else echo "  FAIL: hide=0 disables hidepvt (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	echo "  --- pvtmargin ---"; \
	R=$$(printf '%s\n' ':. early 1 ; : mid ; pvtmargin :. late 2 ; hidepvt early . cr ;' \
	  > $(TMP); $(FF) $(TMP) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | head -1); \
	if [ "$$R" = "1 " ]; then \
	  echo "  PASS: early protected by pvtmargin"; PASS=$$((PASS+1)); \
	else echo "  FAIL: early should be protected (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	R=$$(printf '%s\n' ':. early 1 ; pvtmargin :. late 2 ; hidepvt late . cr ;' \
	  > $(TMP); $(FF) $(TMP) 2>&1 | head -1); \
	if echo "$$R" | grep -q 'error:'; then \
	  echo "  PASS: late hidden by hidepvt"; PASS=$$((PASS+1)); \
	else echo "  FAIL: late should be hidden (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	R=$$(printf '%s\n' ':. early 1 ; pvtmargin :. late 2 ; : pub late . cr ; hidepvt pub ;' \
	  > $(TMP); $(FF) $(TMP) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | head -1); \
	if [ "$$R" = "2 " ]; then \
	  echo "  PASS: pub calls hidden late after hidepvt"; PASS=$$((PASS+1)); \
	else echo "  FAIL: pub should print 2 (got $$R)"; FAIL=$$((FAIL+1)); fi; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0

clean:
	@rm -f $(TMP)
