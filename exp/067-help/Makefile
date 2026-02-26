ROOT=../..
FF64=./ff64

.PHONY: test clean

test: test-help-bye test-help-dup test-help-noarg test-help-notfound test-help-second
	@echo "All 067-help tests passed."

test-help-bye:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s\n' 'help bye' | $(FF64) 2>&1); \
	echo "$$OUT" | grep -q 'terminate the FreeForth session' && \
	echo "  PASS: $@ (help bye shows exit description)" || \
	{ echo "  FAIL: $@"; echo "$$OUT"; exit 1; }

test-help-dup:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s\n' 'help dup' | $(FF64) 2>&1); \
	echo "$$OUT" | grep -q 'duplicates TOS' && \
	echo "  PASS: $@ (help dup shows dup description)" || \
	{ echo "  FAIL: $@"; echo "$$OUT"; exit 1; }

test-help-noarg:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s\n' 'help' | $(FF64) 2>&1); \
	echo "$$OUT" | grep -q 'displays name' && \
	echo "  PASS: $@ (help with no arg shows help topic)" || \
	{ echo "  FAIL: $@"; echo "$$OUT"; exit 1; }

test-help-notfound:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s\n' 'help zzzznonexistent' | $(FF64) 2>&1); \
	echo "$$OUT" | grep -q 'no help found' && \
	echo "  PASS: $@ (unknown keyword shows not found)" || \
	{ echo "  FAIL: $@"; echo "$$OUT"; exit 1; }

test-help-second:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s%-80s' 'help bye' 'help dup' | $(FF64) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q 'terminate' && \
	printf '%s\n' "$$OUT" | grep -q 'duplicates TOS' && \
	echo "  PASS: $@ (second help call works)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

clean:
	@true
