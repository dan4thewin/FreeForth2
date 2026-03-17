FF = ../../ff64-
TMP = /tmp/ff-058.ff
ROOT = ../..

.PHONY: test clean

test: test-decimal test-hex test-uppercase-hex test-hashmore \
      test-sign-neg test-sign-pos test-hold test-nztrue test-zfalse

test-decimal:
	@echo "--- $@ ---"
	@result=$$(cd $(ROOT) && printf '"pno.ff" needed ;\n<# 42 0 #s 0 0 #> type cr\nbye\n' > $(TMP); ./ff64- $(TMP) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-hex:
	@echo "--- $@ ---"
	@result=$$(cd $(ROOT) && printf '"pno.ff" needed ;\n<# 255 0 x#s 0 0 #> type cr\nbye\n' > $(TMP); ./ff64- $(TMP) 2>&1); \
	echo "$$result" | grep -q 'ff' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-uppercase-hex:
	@echo "--- $@ ---"
	@result=$$(cd $(ROOT) && printf '"pno.ff" needed ;\n<# 255 0 X#s 0 0 #> type cr\nbye\n' > $(TMP); ./ff64- $(TMP) 2>&1); \
	echo "$$result" | grep -q 'FF' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-hashmore:
	@echo "--- $@ ---"
	@result=$$(cd $(ROOT) && printf '"pno.ff" needed ;\n<# 12345 0 #s 0 0 #> type cr\nbye\n' > $(TMP); ./ff64- $(TMP) 2>&1); \
	echo "$$result" | grep -q '12345' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-sign-neg:
	@echo "--- $@ ---"
	@result=$$(cd $(ROOT) && printf '"pno.ff" needed ;\n: abs dup 0- 0< IF negate THEN ;\n<# -42 dup >r abs 0 #s r> sign #> type cr\nbye\n' > $(TMP); ./ff64- $(TMP) 2>&1); \
	echo "$$result" | grep -q '\-42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-sign-pos:
	@echo "--- $@ ---"
	@result=$$(cd $(ROOT) && printf '"pno.ff" needed ;\n: abs dup 0- 0< IF negate THEN ;\n<# 42 dup >r abs 0 #s r> sign #> type cr\nbye\n' > $(TMP); ./ff64- $(TMP) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-hold:
	@echo "--- $@ ---"
	@result=$$(cd $(ROOT) && printf '"pno.ff" needed ;\n<# 36 hold 0 0 #> type cr\nbye\n' > $(TMP); ./ff64- $(TMP) 2>&1); \
	echo "$$result" | grep -q '$$' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-nztrue:
	@echo "--- $@ ---"
	@printf '%s\n' ': tst nzTRUE ? ."no" cr ; ."A" tst ."B" cr' > $(TMP); \
	result=$$($(FF) $(TMP) 2>&1); \
	echo "$$result" | grep -q 'AB' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-zfalse:
	@echo "--- $@ ---"
	@printf '%s\n' 'zFALSE nzTRUE ."ok" cr' > $(TMP); \
	result=$$($(FF) $(TMP) 2>&1); \
	echo "$$result" | grep -q 'ok' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

clean:
	@rm -f $(TMP)
	@true