FF64 = ../../ff64-
TMP = /tmp/ff-071.ff
SHELL := /bin/bash

.PHONY: test clean
test:
	@echo "=== Exp 071: hidepvt compaction ==="
	@# Tests 1-2: auto-hidepvt — bare ff64 with stdin redirect
	@echo 'words bye ;' > $(TMP)
	@# Test 1: No NUL-prefixed names in words output
	@OUT=$$(../../ff64 < $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -qaP '\x00'; then \
		echo "  FAIL: NUL-prefixed names found"; exit 1; \
	else echo "  PASS: no NUL-prefixed names"; fi
	@# Test 2: Private words are gone (boot, _pick_detect, etc.)
	@OUT=$$(../../ff64 < $(TMP) 2>/dev/null | tr ' ' '\n'); \
	FOUND=0; \
	for w in _boot _pick_detect _resolve_breaks saved_here noauto _auto _hdr_size _remove_hdr _hidepvt; do \
		if echo "$$OUT" | grep -qaxF "$$w"; then echo "  FAIL: private word $$w still visible"; FOUND=1; fi; \
	done; \
	if [ $$FOUND -eq 0 ]; then echo "  PASS: private words removed"; fi; \
	[ $$FOUND -eq 0 ]
	@# Tests 3-7: explicit hidepvt via wrapper
	@# Test 3: Public words still work after compaction
	@echo 'hidepvt` 42 . cr ;' > $(TMP); \
	OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q '42'; then \
		echo "  PASS: public words work after compaction"; \
	else echo "  FAIL: public words broken"; exit 1; fi
	@# Test 4: TIMES REPEAT works after compaction
	@echo 'hidepvt` 3 TIMES 7 . REPEAT cr ;' > $(TMP); \
	OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q '7 7 7'; then \
		echo "  PASS: TIMES REPEAT works after compaction"; \
	else echo "  FAIL: TIMES REPEAT broken"; exit 1; fi
	@# Test 5: H@ is valid (compaction reclaimed space)
	@echo 'hidepvt` H@ .x cr bye ;' > $(TMP); \
	OUT=$$($(FF64) $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -qP '[1-9a-fA-F]'; then \
		echo "  PASS: H@ valid after compaction"; \
	else echo "  FAIL: H@ looks invalid: $$OUT"; exit 1; fi
	@# Test 6: help still works (run from repo root for file access)
	@echo 'hidepvt` help dup ;' > $(TMP); \
	OUT=$$(cd ../.. && ./ff64- $(TMP) 2>/dev/null); \
	if echo "$$OUT" | grep -q 'dup.*dup'; then \
		echo "  PASS: help works after compaction"; \
	else echo "  FAIL: help broken: $$OUT"; exit 1; fi
	@# Test 7: move word exists (Forth, replaced asm cmove>)
	@echo 'hidepvt` words bye ;' > $(TMP); \
	OUT=$$($(FF64) $(TMP) 2>/dev/null | tr ' ' '\n'); \
	if echo "$$OUT" | grep -qaxF 'move'; then \
		echo "  PASS: move in dictionary"; \
	else echo "  FAIL: move missing"; exit 1; fi
	@echo "  ----"
	@echo "  7 passed, 0 failed"

clean:
	@rm -f $(TMP)
