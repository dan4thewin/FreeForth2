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

# PNO words load from lib/64/pno.ff (run from repo root for FFPATH)
test-pno-load:
	@cd $(ROOT) && printf '"pno.ff" needed ;\n42 0 <# #s #> type cr\nbye\n' | ./ff64 | grep -q '42' && echo "PASS $@" || (echo "FAIL $@"; exit 1)

# see64.ff loads pno.ff automatically (run from repo root for FFPATH)
test-pno-see:
	@cd $(ROOT) && printf '"see64.ff" needed ;\nsee nip\nbye\n' | ./ff64 2>&1 | grep -q 'jmp' && echo "PASS $@" || (echo "FAIL $@"; exit 1)

# Binary is smaller than 377224 (original with PNO in boot)
test-size:
	@SIZE=$$(stat -c%s $(FF)); \
	if [ "$$SIZE" -lt 377224 ]; then echo "PASS $@ ($$SIZE < 377224, saved $$((377224 - $$SIZE)) bytes)"; \
	else echo "FAIL $@ ($$SIZE = $$SIZE, expected < 377224)"; exit 1; fi
