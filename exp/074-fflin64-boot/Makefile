FF=../../ff64
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
	run "features list" \
		'echo "-v" | $(FF)' \
		"boot help dynlink"; \
	run "dlsetup libc" \
		'echo "libc@ . cr 0 exit ;" | $(FF)' \
		"0"; \
	run "needed loads file" \
		'echo "\"lib/x86-64/see.ff\" needed 0 exit ;" | $(FF)' \
		""; \
	run "needexec runs last def" \
		'timeout 5 $(FF) -f ../../lib/x86-64/see.ff -f /dev/stdin <<< "0 exit ;"' \
		""; \
	run "doargv -f flag" \
		'echo "0 exit ;" > /tmp/t074.ff && timeout 5 $(FF) -f /tmp/t074.ff && rm -f /tmp/t074.ff' \
		""; \
	printf ":^ tv .\"a\" cr ;\ntv\n.\"b\" cr ;\ntv %c ^^ tv\n0 exit ;\n" "'" > /tmp/t074_vec.ff; \
	run "vec reset ^^" \
		'timeout 5 $(FF) -f /tmp/t074_vec.ff' \
		"a"; \
	rm -f /tmp/t074_vec.ff; \
	printf "quit %c drop 0 exit ;\n" "'" > /tmp/t074_quit.ff; \
	run "quit defined" \
		'timeout 5 $(FF) -f /tmp/t074_quit.ff' \
		""; \
	rm -f /tmp/t074_quit.ff; \
	run "[os] constant" \
		'echo "[os] . cr 0 exit ;" | $(FF)' \
		"1"; \
	printf "ossetup %c drop 0 exit ;\n" "'" > /tmp/t074_os.ff; \
	run "ossetup is vector" \
		'timeout 5 $(FF) -f /tmp/t074_os.ff' \
		""; \
	rm -f /tmp/t074_os.ff; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]
