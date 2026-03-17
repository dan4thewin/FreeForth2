FF=../../ff64-
TMP=/tmp/t074
.PHONY: test
test:
	@echo "=== Exp 074: fflin64.boot separation ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(eval "$$2" 2>&1) || true; \
		if echo "$$result" | grep -qF "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; echo "    expected: $$3"; echo "    got: $$result"; fail=$$((fail+1)); \
		fi; \
	}; \
	echo '-v 0 exit ;' > $(TMP).ff; \
	run "features list" \
		'timeout 5 $(FF) $(TMP).ff' \
		"locals hidepvt"; \
	echo 'libc@ . cr 0 exit ;' > $(TMP).ff; \
	run "dlsetup libc" \
		'timeout 5 $(FF) $(TMP).ff' \
		"0"; \
	echo '"lib/x86-64/see.ff" needed 0 exit ;' > $(TMP).ff; \
	run "needed loads file" \
		'timeout 5 $(FF) $(TMP).ff' \
		""; \
	echo '0 exit ;' > $(TMP).ff; \
	run "needexec runs last def" \
		'timeout 5 $(FF) ../../lib/x86-64/see.ff $(TMP).ff' \
		""; \
	echo '0 exit ;' > $(TMP).ff; \
	run "doargv -f flag" \
		'timeout 5 $(FF) $(TMP).ff' \
		""; \
	printf ":^ tv .\"a\" cr ;\ntv\n.\"b\" cr ;\ntv %c ^^ tv\n0 exit ;\n" "'" > $(TMP).ff; \
	run "vec reset ^^" \
		'timeout 5 $(FF) $(TMP).ff' \
		"a"; \
	printf "quit %c drop 0 exit ;\n" "'" > $(TMP).ff; \
	run "quit defined" \
		'timeout 5 $(FF) $(TMP).ff' \
		""; \
	echo '[os] . cr 0 exit ;' > $(TMP).ff; \
	run "[os] constant" \
		'timeout 5 $(FF) $(TMP).ff' \
		"1"; \
	printf "ossetup %c drop 0 exit ;\n" "'" > $(TMP).ff; \
	run "ossetup is vector" \
		'timeout 5 $(FF) $(TMP).ff' \
		""; \
	rm -f $(TMP).ff; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]
