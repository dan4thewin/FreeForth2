.PHONY: test
TMP = /tmp/ff64-test-143.ff

test:
	@echo "=== Exp 143: openlib/ffpath/needed port ==="
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
	runenv() { \
		local desc="$$1" input="$$2" expected="$$3" env="$$4"; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(timeout 5 env $$env ./ff64 ': prompt ;' -f $(TMP) 2>/dev/null); \
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
		actual=$$(timeout 5 ./ff64 ': prompt ;' -f $(TMP) 2>/dev/null); \
		if echo "$$actual" | grep -q "$$pattern"; then \
			printf '  %-50s PASS\n' "$$desc"; pass=$$((pass+1)); \
		else \
			printf '  %-50s FAIL\n' "$$desc"; \
			echo "    Expected pattern: [$$pattern]"; \
			echo "    Got:      [$$actual]"; \
			fail=$$((fail+1)); \
		fi; \
	} && \
	run "needs shell.ff loads" \
		'needs shell.ff ."OK" cr 0 exit' \
		'OK' && \
	run "needs shell.ff idempotent" \
		'needs shell.ff needs shell.ff ."OK" cr 0 exit' \
		'OK' && \
	run "needs syscalls.ff loads" \
		'needs syscalls.ff ."OK" cr 0 exit' \
		'OK' && \
	run "needs ior.ff loads" \
		'needs ior.ff ."OK" cr 0 exit' \
		'OK' && \
	run "needed: not-found prints error" \
		'"nonexistent.ff" needed 0 exit' \
		"nonexistent.ff Can't open file." && \
	run "getenv HOME still works" \
		'"HOME" getenv 0- 0<> drop IF ."YES" ELSE ."NO" THEN cr 0 exit' \
		'YES' && \
	runenv "FFPATH env var override" \
		'"FFPATH" getenv 0- 0<> IF type ELSE drop THEN cr 0 exit' \
		'/tmp/test:/opt' \
		'FFPATH=/tmp/test:/opt' && \
	runenv "FFPATH override finds files" \
		'needs syscalls.ff ."OK" cr 0 exit' \
		'OK' \
		'FFPATH=lib/x86-64:lib:.' && \
	run_grep "see triggers autoload via needexec" \
		'see cr 0 exit ;' \
		'ret' && \
	echo "  ----" && \
	echo "  $$pass passed, $$fail failed" && \
	rm -f $(TMP) && \
	[ $$fail -eq 0 ]
