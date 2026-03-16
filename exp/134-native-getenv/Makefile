.PHONY: test
TMP = /tmp/ff64-test-134.ff

test:
	@echo "=== Exp 134: Native getenv ==="
	@cd ../.. && pass=0 && fail=0 && \
	run() { \
		local desc="$$1" input="$$2" expected="$$3"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(timeout 5 ./ff64- $(TMP) 2>/dev/null); \
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
		'"HOME" getenv 0- 0<> drop IF ."PASS" ELSE ."FAIL" THEN cr 0 exit' \
		'PASS' && \
	run "USER found" \
		'"USER" getenv 0- 0<> drop IF ."PASS" ELSE ."FAIL" THEN cr 0 exit' \
		'PASS' && \
	run "nonexistent returns length 0" \
		'"ZZNONEXIST" getenv 0- 0= drop IF ."PASS" ELSE ."FAIL" THEN nip cr 0 exit' \
		'PASS' && \
	run "partial key no match" \
		'"HOM" getenv 0- 0= drop IF ."PASS" ELSE ."FAIL" THEN nip cr 0 exit' \
		'PASS' && \
	echo "  ----" && \
	echo "  $$pass passed, $$fail failed" && \
	[ $$fail -eq 0 ]
