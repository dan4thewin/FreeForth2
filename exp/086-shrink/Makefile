FF=../../ff64
ROOT=../..

.PHONY: test
test: test-boot test-pno-absent test-pno-load test-pno-see test-size
	@echo "=== All exp/086-shrink tests PASSED ==="

# Boot still works without PNO
test-boot:
	@echo '1 2+ . bye' | $(FF) | grep -q '3' && echo "PASS $@" || (echo "FAIL $@"; exit 1)

# PNO words are NOT in boot anymore
test-pno-absent:
	@echo '<# bye' | $(FF) 2>&1 | grep -q '???' && echo "PASS $@" || (echo "FAIL $@"; exit 1)

# PNO words load from lib/pno.ff (run from repo root for FFPATH)
test-pno-load:
	@cd $(ROOT) && printf '"pno.ff" needed ;\n42 0 <# #s #> type cr\nbye\n' | ./ff64 | grep -q '42' && echo "PASS $@" || (echo "FAIL $@"; exit 1)

# see.ff loads pno.ff automatically (run from repo root for FFPATH)
# Use "cr" (always in dictionary) rather than "nip" (now backtick-only)
test-pno-see:
	@cd $(ROOT) && printf '"see.ff" needed ;\nsee cr\nbye\n' | ./ff64 2>&1 | grep -q 'push' && echo "PASS $@" || (echo "FAIL $@"; exit 1)

# Binary is smaller than 640000 (380000 baseline + 256KB tib + 1KB eob from exp 140)
test-size:
	@SIZE=$$(stat -c%s $(FF)); \
	if [ "$$SIZE" -lt 640000 ]; then echo "PASS $@ ($$SIZE < 640000, saved $$((640000 - $$SIZE)) bytes)"; \
	else echo "FAIL $@ ($$SIZE = $$SIZE, expected < 640000)"; exit 1; fi
