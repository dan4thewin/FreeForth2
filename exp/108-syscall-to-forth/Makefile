FF=../../ff64-
FFs=../../ff64s

.PHONY: test clean

test: test-io-ff64 test-io-ff64s
	@echo "  ----"
	@echo "  2 passed, 0 failed"

test-io-ff64:
	@printf "%-48s" "syscall I/O (ff64)"
	@$(FF) -f syscall-io.ff 2>&1 | grep -q "^ok" && echo "PASS" || (echo "FAIL"; exit 1)
	@rm -f test-108-tmp

test-io-ff64s:
	@printf "%-48s" "syscall I/O (ff64s)"
	@$(FFs) -f syscall-io.ff 2>&1 | grep -q "^ok" && echo "PASS" || (echo "FAIL"; exit 1)
	@rm -f test-108-tmp

clean:
	rm -f test-108-tmp
