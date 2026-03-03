FF=../../ff64
FFs=../../ff64s
BOOT=': prompt ;'
DIR=exp/110-perl-parity

.PHONY: test clean

test: test-syscalls-ff64 test-syscalls-ff64s test-net-ff64 test-net-ff64s
@echo "  ----"
@echo "  4 passed, 0 failed"

test-syscalls-ff64:
@printf "%-48s" "Tier 1+2 syscalls (ff64)"
@$(FF) $(BOOT) -f syscalls.ff 2>&1 | grep -q "^ok" && echo "PASS" || ($(FF) $(BOOT) -f syscalls.ff 2>&1; echo "FAIL"; exit 1)

test-syscalls-ff64s:
@printf "%-48s" "Tier 1+2 syscalls (ff64s)"
@$(FFs) $(BOOT) -f syscalls.ff 2>&1 | grep -q "^ok" && echo "PASS" || ($(FFs) $(BOOT) -f syscalls.ff 2>&1; echo "FAIL"; exit 1)

test-net-ff64:
@printf "%-48s" "networking library (ff64)"
@cd ../.. && ./ff64 $(BOOT) -f $(DIR)/net.ff 2>&1 | grep -q "^ok" && echo "PASS" || (cd ../.. && ./ff64 $(BOOT) -f $(DIR)/net.ff 2>&1; echo "FAIL"; exit 1)

test-net-ff64s:
@printf "%-48s" "networking library (ff64s)"
@cd ../.. && ./ff64s $(BOOT) -f $(DIR)/net.ff 2>&1 | grep -q "^ok" && echo "PASS" || (cd ../.. && ./ff64s $(BOOT) -f $(DIR)/net.ff 2>&1; echo "FAIL"; exit 1)

clean:
rm -f test110*
