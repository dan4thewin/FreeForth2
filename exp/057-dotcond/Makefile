FF = ../../ff64-
TMP = /tmp/ff-057.ff

.PHONY: test clean

test: test-if-true test-if-false test-while-loop test-until-loop \
      test-till-loop test-if-else

test-if-true:
	@echo "--- $@ ---"
	@echo ': tst -1 IF. 42 . cr THEN ; tst' > $(TMP); $(FF) $(TMP) 2>/dev/null | grep -q '42'
	@echo "  PASS: $@"

test-if-false:
	@echo "--- $@ ---"
	@echo ': tst 0 IF. 42 . cr THEN 99 . cr ; tst' > $(TMP); result=$$($(FF) $(TMP) 2>/dev/null); \
	echo "$$result" | grep -q '99' && ! echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-while-loop:
	@echo "--- $@ ---"
	@echo ': tst 5 BEGIN dup WHILE. dup . 1- REPEAT drop cr ; tst' > $(TMP); result=$$($(FF) $(TMP) 2>/dev/null); \
	echo "$$result" | grep -q '5 4 3 2 1' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-until-loop:
	@echo "--- $@ ---"
	@echo ': tst 3 BEGIN dup . 1- dup 0= BOOL UNTIL. drop cr ; tst' > $(TMP); result=$$($(FF) $(TMP) 2>/dev/null); \
	echo "$$result" | grep -q '3 2 1' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-till-loop:
	@echo "--- $@ ---"
	@echo ': tst 3 START dup . 1- dup 0= BOOL TILL. drop cr ; tst' > $(TMP); result=$$($(FF) $(TMP) 2>/dev/null); \
	echo "$$result" | grep -q '3 2 1' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-if-else:
	@echo "--- $@ ---"
	@echo ': tst IF. 42 . ELSE 99 . THEN cr ; -1 tst 0 tst' > $(TMP); result=$$($(FF) $(TMP) 2>/dev/null); \
	echo "$$result" | grep -q '42' && echo "$$result" | grep -q '99' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

clean:
	@rm -f $(TMP)
	@true