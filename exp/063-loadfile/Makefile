FF=../../ff64
BOOT=../../ff64.boot
TIMEOUT=3

all: test

test: test-loadfile test-loadfile-value test-loadfile-multi test-loadfile-nofile

test-loadfile:
	@echo "--- $@ ---"
	@echo ': hello 42 ;' > /tmp/lftest1.ff
	@result=$$({ printf '%s\n' '"/tmp/lftest1.ff" loadfile'; sleep 0.1; printf '%s\n' 'hello .'; sleep 0.1; } \
	  | timeout $(TIMEOUT) $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }
	@rm -f /tmp/lftest1.ff

test-loadfile-value:
	@echo "--- $@ ---"
	@echo ': answer 99 ;' > /tmp/lftest2.ff
	@result=$$({ printf '%s\n' '"/tmp/lftest2.ff" loadfile'; sleep 0.1; printf '%s\n' 'answer .'; sleep 0.1; } \
	  | timeout $(TIMEOUT) $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '99' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }
	@rm -f /tmp/lftest2.ff

test-loadfile-multi:
	@echo "--- $@ ---"
	@printf ': aaa 10 ;\n: bbb 20 ;\n: ccc aaa bbb + ;\n' > /tmp/lftest3.ff
	@result=$$({ printf '%s\n' '"/tmp/lftest3.ff" loadfile'; sleep 0.1; printf '%s\n' 'ccc .'; sleep 0.1; } \
	  | timeout $(TIMEOUT) $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -q '30' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }
	@rm -f /tmp/lftest3.ff

test-loadfile-nofile:
	@echo "--- $@ ---"
	@result=$$({ printf '%s\n' '"/tmp/nosuchfile.ff" loadfile'; sleep 0.1; } \
	  | timeout $(TIMEOUT) $(FF) -f $(BOOT) 2>&1); \
	echo "$$result" | grep -qi 'error\|cannot' && echo "  PASS: $@" || { echo "  FAIL: $@ (got: $$result)"; exit 1; }

.PHONY: all test test-loadfile test-loadfile-value test-loadfile-multi test-loadfile-nofile
