FF = ../../ff64

.PHONY: test clean

test: test-decimal test-hex test-uppercase-hex test-hashmore \
      test-sign-neg test-sign-pos test-hold test-nztrue test-zfalse

test-decimal:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s\n' '<# 42 0 #s 0 0 #> type cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-hex:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s\n' '<# 255 0 x#s 0 0 #> type cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q 'ff' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-uppercase-hex:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s\n' '<# 255 0 X#s 0 0 #> type cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q 'FF' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-hashmore:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s\n' '<# 12345 0 #s 0 0 #> type cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q '12345' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-sign-neg:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s%-80s' \
	  ': abs dup 0- 0< IF negate THEN ;' \
	  '<# -42 dup >r abs 0 #s r> sign #> type cr' \
	  | $(FF) 2>&1); \
	echo "$$result" | grep -q '\-42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-sign-pos:
	@echo "--- $@ ---"
	@result=$$(printf '%s\n' \
	  ': abs dup 0- 0< IF negate THEN ;' \
	  '<# 42 dup >r abs 0 #s r> sign #> type cr ;' \
	  | $(FF) 2>/dev/null); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-hold:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s\n' '<# 36 hold 0 0 #> type cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q '$$' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-nztrue:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s\n' ': tst nzTRUE ? ."no" cr ; ."A" tst ."B" cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q 'AB' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-zfalse:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s\n' 'zFALSE nzTRUE ."ok" cr' | $(FF) 2>&1); \
	echo "$$result" | grep -q 'ok' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

clean:
	@true
