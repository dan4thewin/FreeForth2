FF64 = ../../ff64-
TMP = /tmp/ff-072.ff
SHELL := /bin/bash

.PHONY: test clean
test:
	@echo "=== Exp 072: features buffer and new words ==="
	@# Test 1: -v shows base features
	@printf '%s\n' '-v ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'features:.*locals.*hidepvt'; then \
		echo "  PASS: -v shows locals hidepvt"; \
	else echo "  FAIL: -v output: $$OUT"; exit 1; fi
	@# Test 2: append adds to features
	@printf '%s\n' '"_testing" features append ;' '-v ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'features:.*testing'; then \
		echo "  PASS: append adds to features"; \
	else echo "  FAIL: append: $$OUT"; exit 1; fi
	@# Test 3: appendc adds single char
	@printf '%s\n' '$$41 features appendc ;' 'features c@+ type cr ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'A'; then \
		echo "  PASS: appendc adds char"; \
	else echo "  FAIL: appendc: $$OUT"; exit 1; fi
	@# Test 4: zt zero-terminates
	@printf '%s\n' '"hello" zt zlen . . cr ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q '5'; then \
		echo "  PASS: zt zero-terminates"; \
	else echo "  FAIL: zt: $$OUT"; exit 1; fi
	@# Test 5: 2swap works inline
	@printf '%s\n' ': t 1 2 3 4 2swap ; t . . . . cr ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q '2 1 4 3'; then \
		echo "  PASS: 2swap inline"; \
	else echo "  FAIL: 2swap: $$OUT"; exit 1; fi
	@# Test 6: features survives hidepvt (not private)
	@printf '%s\n' 'words bye ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null | tr ' ' '\n'); \
	if echo "$$OUT" | grep -qaxF 'features'; then \
		echo "  PASS: features is public"; \
	else echo "  FAIL: features not in words"; exit 1; fi
	@# Test 7: -v is public
	@printf '%s\n' 'words bye ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null | tr ' ' '\n'); \
	if echo "$$OUT" | grep -qaF -- '-v'; then \
		echo "  PASS: -v is public"; \
	else echo "  FAIL: -v not in words"; exit 1; fi
	@# Test 8: c@+ reads counted string (count removed)
	@printf '%s\n' 'features c@+ type cr ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'locals'; then \
		echo "  PASS: c@+ reads counted string"; \
	else echo "  FAIL: c@+: $$OUT"; exit 1; fi
	@# Test 9: move copies forward
	@printf '%s\n' 'create b1 20 allot ;' '"hello" drop b1 5 move ;' 'b1 5 type cr ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'hello'; then \
		echo "  PASS: move forward"; \
	else echo "  FAIL: move: $$OUT"; exit 1; fi
	@# Test 10: pad returns address above here
	@printf '%s\n' 'pad here - . cr ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q '256'; then \
		echo "  PASS: pad = here + 256"; \
	else echo "  FAIL: pad: $$OUT"; exit 1; fi
	@# Test 11: dump formats 16-byte lines
	@printf '%s\n' '"0123456789ABCDEF0123" drop 32 dump ;' > $(TMP); OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -cq ':.*30.*31.*32'; then \
		echo "  PASS: dump 16-byte lines"; \
	else echo "  FAIL: dump: $$OUT"; exit 1; fi
	@echo "  ----"
	@echo "  11 passed, 0 failed"

clean:
	@rm -f $(TMP)
