FF = ../../ff64
BOOT = ../../ff64.boot

.PHONY: test clean

test: test-decimal test-hex test-uppercase-hex test-hashmore \
      test-sign-neg test-sign-pos test-hold test-nztrue test-zfalse

test-decimal:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s' '<# 42 0 #s 0 0 #> type cr' | $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-hex:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s' '<# 255 0 x#s 0 0 #> type cr' | $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q 'ff' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-uppercase-hex:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s' '<# 255 0 X#s 0 0 #> type cr' | $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q 'FF' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-hashmore:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s' '<# 12345 0 #s 0 0 #> type cr' | $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '12345' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-sign-neg:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s%-80s' \
	  ': abs dup 0- 0< IF negate THEN ;' \
	  '<# -42 dup >r abs 0 #s r> sign #> type cr' \
	  | $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '\-42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-sign-pos:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s%-80s' \
	  ': abs dup 0- 0< IF negate THEN ;' \
	  '<# 42 dup >r abs 0 #s r> sign #> type cr' \
	  | $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '> 42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-hold:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s' '<# 36 hold 0 0 #> type cr' | $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '$$' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-nztrue:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s' ': tst nzTRUE ? ."no" cr ; ."A" tst ."B" cr' | $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q 'AB' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-zfalse:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s' 'zFALSE nzTRUE ."ok" cr' | $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q 'ok' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

clean:
	@true
