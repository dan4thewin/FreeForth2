ROOT = ../..
FF = cd $(ROOT) && ./ff64

.PHONY: test clean
test: test-malloc test-getenv test-getpid test-system test-stat test-console-load test-time-ms test-time-now
	@echo "All 080-lib64 tests passed."

# --- malloc.ff ---

test-malloc:
	@printf 'needs malloc.ff ;\n: test 256 malloc dup 42 swap ! dup @ . cr free ;\ntest\n0 exit ;\n' > /tmp/080-malloc.ff
	@$(FF) -f /tmp/080-malloc.ff 2>&1 | grep -q "^42" && \
	echo "  PASS test-malloc" || (echo "  FAIL test-malloc"; exit 1)

# --- shell.ff ---

test-getenv:
	@printf 'needs shell.ff ;\n: test "HOME" getenv type cr ;\ntest\n0 exit ;\n' > /tmp/080-getenv.ff
	@$(FF) -f /tmp/080-getenv.ff 2>&1 | grep -q "^/" && \
	echo "  PASS test-getenv" || (echo "  FAIL test-getenv"; exit 1)

test-getpid:
	@printf 'needs shell.ff ;\n: test getpid . cr ;\ntest\n0 exit ;\n' > /tmp/080-getpid.ff
	@OUT=$$($(FF) -f /tmp/080-getpid.ff 2>&1); \
	echo "$$OUT" | grep -qE "^[0-9]+" && \
	echo "  PASS test-getpid" || (echo "  FAIL test-getpid"; exit 1)

test-system:
	@printf 'needs shell.ff ;\n: test "echo_lib64_ok" system drop ;\ntest\n0 exit ;\n' > /tmp/080-system.ff
	@$(FF) -f /tmp/080-system.ff 2>&1 | grep -q "lib64 ok" && \
	echo "  PASS test-system" || (echo "  FAIL test-system"; exit 1)

# --- fileops.ff ---

test-stat:
	@printf 'needs fileops.ff ;\nvariable _st pvt 152 allot\n: test "/etc/hostname" _st stat drop _st 48 + @ . cr ;\ntest\n0 exit ;\n' > /tmp/080-stat.ff
	@OUT=$$($(FF) -f /tmp/080-stat.ff 2>&1 | tr -d ' '); \
	EXPECTED=$$(wc -c < /etc/hostname); \
	echo "$$OUT" | grep -q "^$$EXPECTED$$" && \
	echo "  PASS test-stat" || (echo "  FAIL test-stat (got: $$OUT, expected: $$EXPECTED)"; exit 1)

# --- console.ff ---

test-console-load:
	@printf 'needs console.ff ;\n."loaded" cr\n0 exit ;\n' > /tmp/080-console.ff
	@$(FF) -f /tmp/080-console.ff 2>&1 | grep -q "loaded" && \
	echo "  PASS test-console-load" || (echo "  FAIL test-console-load"; exit 1)

# --- time.ff ---

test-time-ms:
	@printf 'needs time.ff ;\n: test ms@ 100 ms ms@ swap - ;\ntest . cr\n0 exit ;\n' > /tmp/080-timems.ff
	@OUT=$$($(FF) -f /tmp/080-timems.ff 2>&1); \
	VAL=$$(echo "$$OUT" | tr -d ' '); \
	if [ "$$VAL" -ge 90 ] 2>/dev/null && [ "$$VAL" -le 200 ] 2>/dev/null; then \
		echo "  PASS test-time-ms ($$VAL ms)"; \
	else \
		echo "  FAIL test-time-ms (got: $$OUT)"; exit 1; \
	fi

test-time-now:
	@printf 'needs time.ff ;\n: test .now cr ;\ntest\n0 exit ;\n' > /tmp/080-timenow.ff
	@$(FF) -f /tmp/080-timenow.ff 2>&1 | grep -q "20[2-3][0-9]" && \
	echo "  PASS test-time-now" || (echo "  FAIL test-time-now"; exit 1)

clean:
	@rm -f /tmp/080-*.ff
