FF = ../../ff64
PAD = %-80s

.PHONY: test
test: test-times test-rtimes test-rtimes-0 test-dump

test-times:
	@echo "--- $@ ---"
	@result=$$(echo ': t 5 TIMES r . space LOOP cr ; t' | timeout 3 $(FF) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '4  3  2  1  0' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-rtimes:
	@echo "--- $@ ---"
	@result=$$(echo ': t 5 >r RTIMES r . space LOOP cr ; t' | timeout 3 $(FF) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '4  3  2  1  0' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-rtimes-0:
	@echo "--- $@ ---"
	@result=$$(echo ': t 0 >r RTIMES r . space LOOP 99 . cr ; t' | timeout 3 $(FF) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '99' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)

test-dump:
	@echo "--- $@ ---"
	@result=$$(echo '$$401000 16 dump' | timeout 3 $(FF) 2>&1 | tr -d '\r'); \
	echo "$$result" | grep -q '00401000:' && echo "  PASS: $@" || (echo "  FAIL: $@ => $$result"; exit 1)
