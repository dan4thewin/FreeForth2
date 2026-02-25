FF = ../../ff64
BOOT = ../../ff64.boot
PAD = %-80s

# Each test uses printf with 80-byte padding for multi-line REPL input
.PHONY: test
test: test-within-yes test-within-no test-within-lo test-within-hi \
      test-abs-neg test-abs-pos test-max test-min \
      test-s2d-neg test-s2d-pos test-d-add test-dnegate test-dabs \
      test-pick0 test-pick1 test-pick2 test-pick3 test-2over

test-within-yes:
	@echo "--- $@ ---"
	@result=$$(printf '$(PAD)$(PAD)' \
	  ': yes 1 . cr ; : no 0 . cr ; : tw within yes ? no ;' \
	  '5 3 8 tw' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '1' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-within-no:
	@echo "--- $@ ---"
	@result=$$(printf '$(PAD)$(PAD)' \
	  ': yes 1 . cr ; : no 0 . cr ; : tw within yes ? no ;' \
	  '2 3 8 tw' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '^> 0' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-within-lo:
	@echo "--- $@ ---"
	@result=$$(printf '$(PAD)$(PAD)' \
	  ': yes 1 . cr ; : no 0 . cr ; : tw within yes ? no ;' \
	  '3 3 8 tw' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '1' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-within-hi:
	@echo "--- $@ ---"
	@result=$$(printf '$(PAD)$(PAD)' \
	  ': yes 1 . cr ; : no 0 . cr ; : tw within yes ? no ;' \
	  '8 3 8 tw' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '^> 0' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-abs-neg:
	@echo "--- $@ ---"
	@result=$$(echo ': t -42 abs . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-abs-pos:
	@echo "--- $@ ---"
	@result=$$(echo ': t 42 abs . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '42' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-max:
	@echo "--- $@ ---"
	@result=$$(echo ': t 5 3 max . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '5' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-min:
	@echo "--- $@ ---"
	@result=$$(echo ': t 5 3 min . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '3' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-s2d-neg:
	@echo "--- $@ ---"
	@result=$$(echo ': t -1 s>d . . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '\-1 \-1' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-s2d-pos:
	@echo "--- $@ ---"
	@result=$$(echo ': t 42 s>d . . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '0 42' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-d-add:
	@echo "--- $@ ---"
	@result=$$(echo ': t 3 0 2 0 d+ . . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '0 5' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-dnegate:
	@echo "--- $@ ---"
	@result=$$(echo ': t 1 0 dnegate . . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '\-1 \-1' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-dabs:
	@echo "--- $@ ---"
	@result=$$(echo ': t -1 -1 dabs . . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '0 1' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-pick0:
	@echo "--- $@ ---"
	@result=$$(echo ': t 42 0 pick . . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '42 42' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-pick1:
	@echo "--- $@ ---"
	@result=$$(echo ': t 10 20 1 pick . . . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '10 20 10' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-pick2:
	@echo "--- $@ ---"
	@result=$$(echo ': t 10 20 30 2 pick . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '10' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-pick3:
	@echo "--- $@ ---"
	@result=$$(echo ': t 10 20 30 40 3 pick . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '10' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-2over:
	@echo "--- $@ ---"
	@result=$$(echo ': t 1 2 3 4 2over . . . . . . cr ; t' | timeout 3 $(FF) -f $(BOOT) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '2 1 4 3 2 1' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)
