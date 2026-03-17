FF = ../../ff64-
ROOT = ../..

.PHONY: test clean
test: test-fixup-resolve test-fixup-patched test-strerror test-strerror-needed test-qior
	@echo "All 079-fixup tests passed."

# Test: fixup resolves a libc symbol on first call
test-fixup-resolve:
	@printf ': fixup libc@ #fun here swap $$48 c, $$BB c, , $$C3 c, r> 5- dup>r - 5- r 1+ d! ;\n:. _xstrerror "strerror" fixup ;\n: strerror negate 1 dup _xstrerror #call zlen type cr ;\n2 strerror\n0 exit ;\n' > /tmp/079-fixup-resolve.ff
	@$(FF) /tmp/079-fixup-resolve.ff 2>&1 | grep -q "Unknown error" && echo "  PASS test-fixup-resolve" || (echo "  FAIL test-fixup-resolve"; exit 1)

# Test: second call uses patched trampoline (no re-resolution)
test-fixup-patched:
	@printf ': fixup libc@ #fun here swap $$48 c, $$BB c, , $$C3 c, r> 5- dup>r - 5- r 1+ d! ;\n:. _xstrerror "strerror" fixup ;\n: strerror negate 1 dup _xstrerror #call zlen type cr ;\n2 strerror\n3 strerror\n0 exit ;\n' > /tmp/079-fixup-patched.ff
	@OUT=$$($(FF) /tmp/079-fixup-patched.ff 2>&1); \
	echo "$$OUT" | head -1 | grep -q "Unknown error -2" && \
	echo "$$OUT" | tail -1 | grep -q "Unknown error -3" && \
	echo "  PASS test-fixup-patched" || (echo "  FAIL test-fixup-patched"; exit 1)

# Test: strerror displays correct error message for various codes
test-strerror:
	@printf 'needs ior.ff\n2 strerror\n-22 strerror\n0 exit ;\n' > /tmp/079-strerror.ff
	@OUT=$$(cd $(ROOT) && ./ff64- /tmp/079-strerror.ff 2>&1); \
	echo "$$OUT" | grep -q "errno -2" && \
	echo "$$OUT" | grep -q "EINVAL" && \
	echo "  PASS test-strerror" || (echo "  FAIL test-strerror"; echo "    got: $$OUT"; exit 1)

# Test: strerror works when loaded via needed (FFPATH resolves lib/x86-64)
test-strerror-needed:
	@printf 'needs ior.ff\n-13 strerror\n0 exit ;\n' > /tmp/079-needed.ff
	@cd $(ROOT) && ./ff64- /tmp/079-needed.ff 2>&1 | grep -q "EACCES" && \
	echo "  PASS test-strerror-needed" || (echo "  FAIL test-strerror-needed"; exit 1)

# Test: ?ior stores result in ior variable
test-qior:
	@printf 'needs ior.ff\n42 ?ior drop\nior @ . cr ;\n0 exit ;\n' > /tmp/079-qior.ff
	@cd $(ROOT) && ./ff64- /tmp/079-qior.ff 2>&1 | grep -q "42" && \
	echo "  PASS test-qior" || (echo "  FAIL test-qior"; exit 1)

clean:
	@rm -f /tmp/079-*.ff
