.PHONY: test clean
TMP = /tmp/ff64-test-142

test:
	@cd ../.. && pass=0 && fail=0 && \
	run() { \
		local desc="$$1" input="$$2" expected="$$3"; \
		printf '%s' "$$input" > $(TMP).ff; \
		actual=$$(timeout 5 ./ff64- $(TMP).ff 2>/dev/null); \
		if [ "$$actual" = "$$expected" ]; then \
			pass=$$((pass+1)); \
		else \
			printf '  FAIL: %s\n' "$$desc" >&2; \
			printf '    expected: [%s]\n' "$$expected" >&2; \
			printf '    actual:   [%s]\n' "$$actual" >&2; \
			fail=$$((fail+1)); \
		fi; \
	} && \
	run "CS0 is nonzero" \
		'CS0@ 0- 0<> drop IF ."PASS" ELSE ."FAIL" THEN cr 0 exit' \
		'PASS' && \
	run "envp returns pointer" \
		'envp @ 0- 0<> drop IF ."PASS" ELSE ."FAIL" THEN cr 0 exit' \
		'PASS' && \
	run "getenv HOME" \
		'"HOME" getenv 0- 0<> drop IF ."PASS" ELSE ."FAIL" THEN nip cr 0 exit' \
		'PASS' && \
	run "getenv nonexistent" \
		'"ZZNONEXIST" getenv 0- 0= drop IF ."PASS" ELSE ."FAIL" THEN nip cr 0 exit' \
		'PASS' && \
	run "argc matches" \
		'argc 0- 0> drop IF ."PASS" ELSE ."FAIL" THEN cr 0 exit' \
		'PASS' && \
	run "argv 0 is non-empty" \
		'0 argv 0- 0> drop IF ."PASS" ELSE ."FAIL" THEN nip cr 0 exit' \
		'PASS' && \
	[ $$fail -eq 0 ]

clean:
	@rm -f $(TMP).ff
