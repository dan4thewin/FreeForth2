.PHONY: test
TMP = /tmp/ff64-test-134.ff

test:
	@echo "=== Exp 134: Native getenv ==="
	@cd ../.. && pass=0 && fail=0 && \
	run() { \
		local desc="$$1" input="$$2" expected="$$3"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(timeout 5 ./ff64 ': prompt ;' -f $(TMP) 2>/dev/null); \
		if [ "$$actual" = "$$expected" ]; then \
			printf '  %-50s PASS\n' "$$desc"; pass=$$((pass+1)); \
		else \
			printf '  %-50s FAIL\n' "$$desc"; \
			echo "    Expected: [$$expected]"; \
			echo "    Got:      [$$actual]"; \
			fail=$$((fail+1)); \
		fi; \
	} && \
	run "HOME found" \
		'needs shell.ff "HOME" getenv 0- 0<> drop IF ."PASS" ELSE ."FAIL" THEN cr bye' \
		'PASS' && \
	run "USER found" \
		'needs shell.ff "USER" getenv 0- 0<> drop IF ."PASS" ELSE ."FAIL" THEN cr bye' \
		'PASS' && \
	run "nonexistent returns 0 0" \
		'needs shell.ff "ZZNONEXIST" getenv + 0- 0= drop IF ."PASS" ELSE ."FAIL" THEN cr bye' \
		'PASS' && \
	run "partial key no match" \
		'needs shell.ff "HOM" getenv + 0- 0= drop IF ."PASS" ELSE ."FAIL" THEN cr bye' \
		'PASS' && \
	echo "  ----" && \
	echo "  $$pass passed, $$fail failed" && \
	[ $$fail -eq 0 ]
