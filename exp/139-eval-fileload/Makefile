FF64 = ../../ff64-

all: test

test: test-eval-fileload

test-eval-fileload:
	@cd ../.. && result=$$(printf ': prompt ;\n' | cat - exp/139-eval-fileload/test.ff \
	  | timeout 10 ./ff64 2>&1); \
	pass=$$(echo "$$result" | grep -c "PASS:"); \
	fail=$$(echo "$$result" | grep -c "FAIL:"); \
	if [ "$$fail" -gt 0 ]; then \
	  echo "FAIL eval-fileload ($$pass pass, $$fail fail)"; \
	  echo "$$result"; exit 1; \
	elif [ "$$pass" -ge 5 ]; then \
	  echo "PASS eval-fileload ($$pass tests)"; \
	else \
	  echo "FAIL eval-fileload (only $$pass/5 passed)"; \
	  echo "$$result"; exit 1; \
	fi

.PHONY: all test test-eval-fileload
