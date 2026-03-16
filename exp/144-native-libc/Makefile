.PHONY: test
TMP = /tmp/ff64-test-144.ff

test:
	@echo "=== Exp 144: Native libc replacements ==="
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
	run_grep() { \
		local desc="$$1" input="$$2" pattern="$$3"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(timeout 5 ./ff64- $(TMP) 2>/dev/null); \
		if echo "$$actual" | grep -q "$$pattern"; then \
			printf '  %-50s PASS\n' "$$desc"; pass=$$((pass+1)); \
		else \
			printf '  %-50s FAIL\n' "$$desc"; \
			echo "    Expected pattern: [$$pattern]"; \
			echo "    Got:      [$$actual]"; \
			fail=$$((fail+1)); \
		fi; \
	} && \
	run_env() { \
		local desc="$$1" input="$$2" expected="$$3" env="$$4"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(timeout 5 env $$env ./ff64- $(TMP) 2>/dev/null); \
		if [ "$$actual" = "$$expected" ]; then \
			printf '  %-50s PASS\n' "$$desc"; pass=$$((pass+1)); \
		else \
			printf '  %-50s FAIL\n' "$$desc"; \
			echo "    Expected: [$$expected]"; \
			echo "    Got:      [$$actual]"; \
			fail=$$((fail+1)); \
		fi; \
	} && \
	run "system echo" \
		'needs shell.ff "echo_HELLO" system drop 0 exit ;' \
		'HELLO' && \
	run "system exit code 0" \
		'needs shell.ff "true" system 0- 0= drop IF ."ZERO" THEN cr 0 exit ;' \
		'ZERO' && \
	run "system exit code 1" \
		'needs shell.ff "false" system 0- 0<> drop IF ."NONZERO" THEN cr 0 exit ;' \
		'NONZERO' && \
	run_grep "shell reports error" \
		'needs shell.ff "false" shell ."OK" cr 0 exit ;' \
		'OK' && \
	run_grep "strerror ENOENT" \
		'needs ior.ff -2 strerror 0 exit ;' \
		'ENOENT' && \
	run_grep "strerror EACCES" \
		'needs ior.ff -13 strerror 0 exit ;' \
		'EACCES' && \
	run_grep "strerror unknown" \
		'needs ior.ff -99 strerror 0 exit ;' \
		'errno' && \
	run_env "FFHIDE=0 exposes privates" \
		'hide @ 0- 0= drop IF ."OFF" THEN cr 0 exit ;' \
		'OFF' \
		'FFHIDE=0' && \
	run "hide on by default" \
		'hide @ 0- 0<> drop IF ."ON" THEN cr 0 exit ;' \
		'ON' && \
	echo "  ----" && \
	echo "  $$pass passed, $$fail failed" && \
	rm -f $(TMP) && \
	[ $$fail -eq 0 ]
