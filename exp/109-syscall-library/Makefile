FF=../../ff64
FFs=../../ff64s
BOOT=': prompt ;'

.PHONY: test clean

test: test-syscalls-ff64 test-syscalls-ff64s
	@echo "  ----"
	@echo "  2 passed, 0 failed"

test-syscalls-ff64:
	@printf "%-48s" "syscall library (ff64)"
	@$(FF) $(BOOT) -f syscalls.ff 2>&1 | grep -q "^ok" && echo "PASS" || ($(FF) $(BOOT) -f syscalls.ff 2>&1; echo "FAIL"; exit 1)
	@rm -f test109tmp

test-syscalls-ff64s:
	@printf "%-48s" "syscall library (ff64s)"
	@$(FFs) $(BOOT) -f syscalls.ff 2>&1 | grep -q "^ok" && echo "PASS" || ($(FFs) $(BOOT) -f syscalls.ff 2>&1; echo "FAIL"; exit 1)
	@rm -f test109tmp

clean:
	rm -f test109tmp
