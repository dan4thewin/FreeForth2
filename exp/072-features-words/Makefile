FF64 = ../../ff64
SHELL := /bin/bash

.PHONY: test
test:
	@echo "=== Exp 072: features buffer and new words ==="
	@# Test 1: -v shows base features
	@OUT=$$(printf '%s\n' '-v ;' | $(FF64) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'features:.*boot.*help.*dynlink'; then \
		echo "  PASS: -v shows boot help dynlink"; \
	else echo "  FAIL: -v output: $$OUT"; exit 1; fi
	@# Test 2: append adds to features
	@OUT=$$(printf '%s\n' '"_testing" features append ;' '-v ;' | $(FF64) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'features:.*testing'; then \
		echo "  PASS: append adds to features"; \
	else echo "  FAIL: append: $$OUT"; exit 1; fi
	@# Test 3: appendc adds single char
	@OUT=$$(printf '%s\n' '$$41 features appendc ;' 'features c@+ type cr ;' | $(FF64) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'A'; then \
		echo "  PASS: appendc adds char"; \
	else echo "  FAIL: appendc: $$OUT"; exit 1; fi
	@# Test 4: zt zero-terminates
	@OUT=$$(printf '%s\n' '"hello" zt zlen . . cr ;' | $(FF64) 2>/dev/null); \
	if echo "$$OUT" | grep -q '5'; then \
		echo "  PASS: zt zero-terminates"; \
	else echo "  FAIL: zt: $$OUT"; exit 1; fi
	@# Test 5: 2swap works inline
	@OUT=$$(printf '%s\n' ': t 1 2 3 4 2swap ; t . . . . cr ;' | $(FF64) 2>/dev/null); \
	if echo "$$OUT" | grep -q '2 1 4 3'; then \
		echo "  PASS: 2swap inline"; \
	else echo "  FAIL: 2swap: $$OUT"; exit 1; fi
	@# Test 6: features survives hidepvt (not private)
	@OUT=$$(printf '%s\n' 'words bye ;' | $(FF64) 2>/dev/null | tr ' ' '\n'); \
	if echo "$$OUT" | grep -qaxF 'features'; then \
		echo "  PASS: features is public"; \
	else echo "  FAIL: features not in words"; exit 1; fi
	@# Test 7: -v is public
	@OUT=$$(printf '%s\n' 'words bye ;' | $(FF64) 2>/dev/null | tr ' ' '\n'); \
	if echo "$$OUT" | grep -qaF -- '-v'; then \
		echo "  PASS: -v is public"; \
	else echo "  FAIL: -v not in words"; exit 1; fi
	@# Test 8: count reads counted string
	@OUT=$$(printf '%s\n' 'features count type cr ;' | $(FF64) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'boot'; then \
		echo "  PASS: count reads counted string"; \
	else echo "  FAIL: count: $$OUT"; exit 1; fi
	@# Test 9: move copies forward
	@OUT=$$(printf '%s\n' 'create b1 20 allot ;' '"hello" drop b1 5 move ;' 'b1 5 type cr ;' | $(FF64) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'hello'; then \
		echo "  PASS: move forward"; \
	else echo "  FAIL: move: $$OUT"; exit 1; fi
	@# Test 10: pad returns address above here
	@OUT=$$(printf '%s\n' 'pad here - . cr ;' | $(FF64) 2>/dev/null); \
	if echo "$$OUT" | grep -q '256'; then \
		echo "  PASS: pad = here + 256"; \
	else echo "  FAIL: pad: $$OUT"; exit 1; fi
	@# Test 11: dump formats 16-byte lines
	@OUT=$$(printf '%s\n' '"0123456789ABCDEF0123" drop 32 dump ;' | $(FF64) 2>/dev/null); \
	if echo "$$OUT" | grep -cq ':.*30.*31.*32'; then \
		echo "  PASS: dump 16-byte lines"; \
	else echo "  FAIL: dump: $$OUT"; exit 1; fi
	@echo "  ----"
	@echo "  11 passed, 0 failed"
