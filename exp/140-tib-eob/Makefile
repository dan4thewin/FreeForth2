FF64 = ../../ff64-

all: test

test:
	@cd ../.. && result=$$(printf ': prompt ;\n' | cat - exp/140-tib-eob/test.ff \
	  | timeout 10 ./ff64 2>&1); \
	pass=$$(echo "$$result" | grep -c "PASS:"); \
	fail=$$(echo "$$result" | grep -c "FAIL:"); \
	if [ "$$fail" -gt 0 ]; then \
	  echo "FAIL tib-eob ($$pass pass, $$fail fail)"; \
	  echo "$$result"; exit 1; \
	elif [ "$$pass" -ge 3 ]; then \
	  echo "PASS tib-eob ($$pass tests)"; \
	else \
	  echo "FAIL tib-eob (only $$pass/3 passed)"; \
	  echo "$$result"; exit 1; \
	fi

.PHONY: all test
