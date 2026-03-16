FF=../../ff64-
FFs=../../ff64s

.PHONY: test clean

test: test-syscalls-ff64 test-syscalls-ff64s
	@echo "  ----"
	@echo "  2 passed, 0 failed"

test-syscalls-ff64:
	@printf "%-48s" "syscall library (ff64)"
	@$(FF) -f syscalls.ff 2>&1 | grep -q "^ok" && echo "PASS" || ($(FF) -f syscalls.ff 2>&1; echo "FAIL"; exit 1)
	@rm -f test109tmp

test-syscalls-ff64s:
	@printf "%-48s" "syscall library (ff64s)"
	@$(FFs) -f syscalls.ff 2>&1 | grep -q "^ok" && echo "PASS" || ($(FFs) -f syscalls.ff 2>&1; echo "FAIL"; exit 1)
	@rm -f test109tmp

clean:
	rm -f test109tmp
