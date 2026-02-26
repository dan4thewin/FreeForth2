FF64 = ../../ff64

.PHONY: test
test: test-inc test-dec test-inc-var test-multi

test-inc:
	@echo "--- $@ ---"
	@result=$$(echo ': t 10 base! base@ ++ base@ .l cr 10 base! ; t' | $(FF64) 2>&1 | grep -o '[0-9a-f]\{8\}' | tail -1); if [ "$$result" = "0000000b" ]; then echo "  PASS: $@"; else echo "  FAIL: $@ (expected 0000000b, got $$result)"; exit 1; fi

test-dec:
	@echo "--- $@ ---"
	@result=$$(echo ': t 10 base! base@ -- base@ .l cr 10 base! ; t' | $(FF64) 2>&1 | grep -o '[0-9a-f]\{8\}' | tail -1); if [ "$$result" = "00000009" ]; then echo "  PASS: $@"; else echo "  FAIL: $@ (expected 00000009, got $$result)"; exit 1; fi

test-inc-var:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s%-80s' '0 variable v' ': t v@ ++ v@ .l cr ; t' | $(FF64) 2>&1 | grep -o '[0-9a-f]\{8\}' | tail -1); if [ "$$result" = "00000001" ]; then echo "  PASS: $@"; else echo "  FAIL: $@ (expected 00000001, got $$result)"; exit 1; fi

test-multi:
	@echo "--- $@ ---"
	@result=$$(printf '%-80s%-80s' '0 variable v' ': t v@ ++ v@ ++ v@ ++ v@ .l cr ; t' | $(FF64) 2>&1 | grep -o '[0-9a-f]\{8\}' | tail -1); if [ "$$result" = "00000003" ]; then echo "  PASS: $@"; else echo "  FAIL: $@ (expected 00000003, got $$result)"; exit 1; fi
