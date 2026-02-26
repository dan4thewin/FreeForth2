FF = ../../ff64

.PHONY: test clean

test: test-if-true test-if-false test-while-loop test-until-loop \
      test-till-loop test-if-else

test-if-true:
	@echo "--- $@ ---"
	@echo ': tst -1 IF. 42 . cr THEN ; tst' | $(FF) 2>&1 | grep -q '^> 42'
	@echo "  PASS: $@"

test-if-false:
	@echo "--- $@ ---"
	@result=$$(echo ': tst 0 IF. 42 . cr THEN 99 . cr ; tst' | $(FF) 2>&1); \
	echo "$$result" | grep -q '99' && ! echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-while-loop:
	@echo "--- $@ ---"
	@result=$$(echo ': tst 5 BEGIN dup WHILE. dup . 1- REPEAT drop cr ; tst' | $(FF) 2>&1); \
	echo "$$result" | grep -q '5 4 3 2 1' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-until-loop:
	@echo "--- $@ ---"
	@result=$$(echo ': tst 3 BEGIN dup . 1- dup 0= BOOL UNTIL. drop cr ; tst' | $(FF) 2>&1); \
	echo "$$result" | grep -q '3 2 1' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-till-loop:
	@echo "--- $@ ---"
	@result=$$(echo ': tst 3 START dup . 1- dup 0= BOOL TILL. drop cr ; tst' | $(FF) 2>&1); \
	echo "$$result" | grep -q '3 2 1' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

test-if-else:
	@echo "--- $@ ---"
	@result=$$(echo ': tst IF. 42 . ELSE 99 . THEN cr ; -1 tst 0 tst' | $(FF) 2>&1); \
	echo "$$result" | grep -q '42' && echo "$$result" | grep -q '99' && echo "  PASS: $@" || (echo "  FAIL: $@ (got: $$result)"; exit 1)

clean:
	@true
