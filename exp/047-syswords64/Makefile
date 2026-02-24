FF = ../../ff64
BOOT = ../../ff64.boot
PASS = 0
FAIL = 0

.PHONY: test
test:
	@echo "=== 047-syswords64 ==="
	@PASS=0; FAIL=0; \
	\
	echo "  --- catch/throw ---"; \
	\
	R=$$(printf '%s\n' ': ok 42 . cr ; ok '"'"' catch . cr ;' \
	     | $(FF) -f $(BOOT) 2>/dev/null); \
	if echo "$$R" | grep -q "42"; then \
	  if echo "$$R" | grep -q "^0 "; then \
	    echo "  PASS: catch returns 0 on success"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: catch returns 0 on success"; FAIL=$$((FAIL+1)); fi; \
	else echo "  FAIL: catch returns 0 on success"; FAIL=$$((FAIL+1)); fi; \
	\
	R=$$(printf '%s\n' ': bomb 99 throw ; bomb '"'"' catch . cr ;' \
	     | $(FF) -f $(BOOT) 2>/dev/null); \
	if echo "$$R" | grep -q "99"; then \
	  echo "  PASS: throw returns exception to catch"; PASS=$$((PASS+1)); \
	else echo "  FAIL: throw returns exception to catch"; FAIL=$$((FAIL+1)); fi; \
	\
	R=$$(printf '%s\n' ': inner 55 throw ; : outer inner '"'"' catch ; outer . cr ;' \
	     | $(FF) -f $(BOOT) 2>/dev/null); \
	if echo "$$R" | grep -q "55"; then \
	  echo "  PASS: nested catch/throw"; PASS=$$((PASS+1)); \
	else echo "  FAIL: nested catch/throw"; FAIL=$$((FAIL+1)); fi; \
	\
	echo "  --- write/type ---"; \
	\
	R=$$(printf '%s\n' 'create buf 16 allot 72 buf c! 73 buf 1 + c! buf 2 stdout write drop cr ;' \
	     | $(FF) -f $(BOOT) 2>/dev/null); \
	if echo "$$R" | grep -q "HI"; then \
	  echo "  PASS: write outputs bytes"; PASS=$$((PASS+1)); \
	else echo "  FAIL: write outputs bytes"; FAIL=$$((FAIL+1)); fi; \
	\
	R=$$(printf '%s\n' 'create buf 16 allot 65 buf c! 66 buf 1 + c! 67 buf 2 + c! buf 3 type cr ;' \
	     | $(FF) -f $(BOOT) 2>/dev/null); \
	if echo "$$R" | grep -q "ABC"; then \
	  echo "  PASS: type outputs string"; PASS=$$((PASS+1)); \
	else echo "  FAIL: type outputs string"; FAIL=$$((FAIL+1)); fi; \
	\
	R=$$(printf '%s\n' 'create buf 16 allot 65 buf c! 66 buf 1 + c! : t buf 2 type ; t cr ;' \
	     | $(FF) -f $(BOOT) 2>/dev/null); \
	if echo "$$R" | grep -q "AB"; then \
	  echo "  PASS: type works inside definition"; PASS=$$((PASS+1)); \
	else echo "  FAIL: type works inside definition"; FAIL=$$((FAIL+1)); fi; \
	\
	echo "  --- allot preservation ---"; \
	\
	R=$$(printf '%s\n' 'create buf 16 allot 65 buf c! 66 buf 1 + c! : t 0 ; buf c@ . cr buf 1 + c@ . cr ;' \
	     | $(FF) -f $(BOOT) 2>/dev/null); \
	if echo "$$R" | grep -q "65" && echo "$$R" | grep -q "66"; then \
	  echo "  PASS: create+allot data survives colon def"; PASS=$$((PASS+1)); \
	else echo "  FAIL: create+allot data survives colon def"; FAIL=$$((FAIL+1)); fi; \
	\
	R=$$(printf '%s\n' 'variable x 42 x ! : t x @ . cr ; t ;' \
	     | $(FF) -f $(BOOT) 2>/dev/null); \
	if echo "$$R" | grep -q "42"; then \
	  echo "  PASS: variable data survives colon def"; PASS=$$((PASS+1)); \
	else echo "  FAIL: variable data survives colon def"; FAIL=$$((FAIL+1)); fi; \
	\
	echo "  --- bye ---"; \
	\
	R=$$(printf '%s\n' 'bye' \
	     | timeout 5 $(FF) -f $(BOOT) 2>/dev/null; echo "EXIT=$$?"); \
	if echo "$$R" | grep -q "EXIT=0"; then \
	  echo "  PASS: bye exits cleanly"; PASS=$$((PASS+1)); \
	else echo "  FAIL: bye exits cleanly"; FAIL=$$((FAIL+1)); fi; \
	\
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0
