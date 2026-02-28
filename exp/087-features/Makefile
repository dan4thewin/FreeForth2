ROOT=../..
FF=$(ROOT)/ff64

.PHONY: test
test: test-base-features test-lib-features test-see-features \
      test-needed-guard test-ffhide-off test-ffhide-default test-v-shows
	@echo "=== All exp/087-features tests PASSED ==="

# Base features from boot
test-base-features:
	@result=$$(echo '-v bye' | $(FF) 2>&1); \
	echo "$$result" | grep -q 'boot help dynlink segv' && echo "PASS $@" || (echo "FAIL $@ (got: $$result)"; exit 1)

# Library files append to features
test-lib-features:
	@result=$$(cd $(ROOT) && printf '"shell.ff" needed ;\nfeatures c@+ type cr\nbye\n' | ./ff64 2>&1); \
	echo "$$result" | grep -q 'fixup' && echo "$$result" | grep -q 'ior' && echo "$$result" | grep -q 'shell' \
	&& echo "PASS $@" || (echo "FAIL $@ (got: $$result)"; exit 1)

# see64.ff loads pno.ff and shows in features
test-see-features:
	@result=$$(cd $(ROOT) && printf '"see64.ff" needed ;\n-v\nbye\n' | ./ff64 2>&1); \
	echo "$$result" | grep -q 'pno' && echo "$$result" | grep -q 'see' \
	&& echo "PASS $@" || (echo "FAIL $@ (got: $$result)"; exit 1)

# needed guard prevents double loading (features not duplicated)
test-needed-guard:
	@result=$$(cd $(ROOT) && printf '"fixup.ff" needed ;\n"fixup.ff" needed ;\nfeatures c@+ type cr\nbye\n' | ./ff64 2>&1); \
	count=$$(echo "$$result" | grep -o 'fixup' | wc -l); \
	[ "$$count" -eq 1 ] && echo "PASS $@" || (echo "FAIL $@ (fixup appeared $$count times: $$result)"; exit 1)

# FFHIDE=0 disables private word hiding
test-ffhide-off:
	@result=$$(printf 'hide@ . cr\nbye\n' | FFHIDE=0 $(FF) 2>&1 | head -1); \
	echo "$$result" | grep -q '0; 0' && echo "PASS $@" || (echo "FAIL $@ (got: $$result)"; exit 1)

# Without FFHIDE, hide is on (-1)
test-ffhide-default:
	@result=$$(printf 'hide@ . cr\nbye\n' | $(FF) 2>&1); \
	echo "$$result" | grep -q '\-1' && echo "PASS $@" || (echo "FAIL $@ (got: $$result)"; exit 1)

# -v displays loaded features
test-v-shows:
	@result=$$(cd $(ROOT) && printf '"time.ff" needed ;\n-v\nbye\n' | ./ff64 2>&1); \
	echo "$$result" | grep -q 'time' && echo "PASS $@" || (echo "FAIL $@ (got: $$result)"; exit 1)
