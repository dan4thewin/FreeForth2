ROOT=../..
FF64=./ff64

.PHONY: test clean

test: test-lib test-fun test-call test-libc-puts test-libc-getpid test-libc-abs test-dlerror
	@echo "All 068-dynlink tests passed."

test-lib:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s\n' '"libc.so.6" #lib 0- 0<> IF ."ok" THEN cr' | $(FF64) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q 'ok' && \
	echo "  PASS: $@ (#lib returns nonzero handle)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-fun:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$({ printf '%-80s\n' 'variable libc "libc.so.6" #lib libc !'; \
	  printf '%-80s\n' '"puts" libc @ #fun 0- 0<> IF ."ok" THEN cr'; } \
	  | $(FF64) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q 'ok' && \
	echo "  PASS: $@ (#fun resolves puts)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-call:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s\n' '-42 1 libc. abs .' | $(FF64) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q '42' && \
	echo "  PASS: $@ (#call via libc. abs(-42)=42)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-libc-puts:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s\n' '"hello" drop 1 libc. strlen .' | $(FF64) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q '5' && \
	echo "  PASS: $@ (libc. strlen works)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-libc-getpid:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s\n' '0 libc. getpid 0- 0> IF ."ok" THEN cr' \
	  | $(FF64) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q 'ok' && \
	echo "  PASS: $@ (libc. getpid returns positive)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-libc-abs:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$(printf '%-80s\n' '-7 1 libc. abs .' | $(FF64) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q '7' && \
	echo "  PASS: $@ (libc. abs(-7) = 7)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

test-dlerror:
	@echo "--- $@ ---"
	@cd $(ROOT) && OUT=$$({ printf '%-80s\n' ': _t "nonexistent.so" #lib ;'; \
	  printf '%-80s\n' '_t '"'"' catch 0- drop 0<> IF ."caught" THEN cr'; } \
	  | $(FF64) 2>&1); \
	printf '%s\n' "$$OUT" | grep -q 'caught' && \
	echo "  PASS: $@ (bad #lib throws, catch catches)" || \
	{ echo "  FAIL: $@"; printf '%s\n' "$$OUT"; exit 1; }

clean:
	@true
