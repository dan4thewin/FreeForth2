ROOT=../..
FF64=./ff64-
TMP=/tmp/ff-068.ff

.PHONY: test clean

test: test-lib test-fun test-call test-libc-puts test-libc-getpid test-libc-abs test-dlerror
	@echo "All 068-dynlink tests passed."

test-lib:
	@echo "--- $@ ---"
	@echo '"libc.so.6" #lib 0- 0<> IF ."ok" THEN cr' > $(TMP); \
	cd $(ROOT) && OUT=$$($(FF64) $(TMP) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q 'ok' && \
	echo "  PASS: $@ (#lib returns nonzero handle)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-fun:
	@echo "--- $@ ---"
	@printf '%s\n' 'variable libc "libc.so.6" #lib libc !' '"puts" libc @ #fun 0- 0<> IF ."ok" THEN cr' > $(TMP); \
	cd $(ROOT) && OUT=$$($(FF64) $(TMP) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q 'ok' && \
	echo "  PASS: $@ (#fun resolves puts)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-call:
	@echo "--- $@ ---"
	@echo '-42 1 libc. abs .' > $(TMP); \
	cd $(ROOT) && OUT=$$($(FF64) $(TMP) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q '42' && \
	echo "  PASS: $@ (#call via libc. abs(-42)=42)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-libc-puts:
	@echo "--- $@ ---"
	@echo '"hello" drop 1 libc. strlen .' > $(TMP); \
	cd $(ROOT) && OUT=$$($(FF64) $(TMP) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q '5' && \
	echo "  PASS: $@ (libc. strlen works)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-libc-getpid:
	@echo "--- $@ ---"
	@echo '0 libc. getpid 0- 0> IF ."ok" THEN cr' > $(TMP); \
	cd $(ROOT) && OUT=$$($(FF64) $(TMP) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q 'ok' && \
	echo "  PASS: $@ (libc. getpid returns positive)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-libc-abs:
	@echo "--- $@ ---"
	@echo '-7 1 libc. abs .' > $(TMP); \
	cd $(ROOT) && OUT=$$($(FF64) $(TMP) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q '7' && \
	echo "  PASS: $@ (libc. abs(-7) = 7)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-dlerror:
	@echo "--- $@ ---"
	@printf '%s\n' ': _t "nonexistent.so" #lib ;' '_t '"'"' catch 0- drop 0<> IF ."caught" THEN cr' > $(TMP); \
	cd $(ROOT) && OUT=$$($(FF64) $(TMP) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q 'caught' && \
	echo "  PASS: $@ (bad #lib throws, catch catches)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

clean:
	@rm -f $(TMP)
