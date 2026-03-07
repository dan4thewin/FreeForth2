.PHONY: test
TMP = /tmp/ff64-test-145.ff

test:
	@echo "=== Exp 145: Shared mmap and boot syscall wrappers ==="
	@cd ../.. && pass=0 && fail=0 && \
	run() { \
		local desc="$$1" input="$$2" expected="$$3" bin="$$4"; \
		[ -z "$$bin" ] && bin=./ff64; \
		printf '%s\n' "$$input" > $(TMP); \
		actual=$$(timeout 5 $$bin ': prompt ;' -f $(TMP) 2>/dev/null); \
		if [ "$$actual" = "$$expected" ]; then \
			printf '  %-52s PASS\n' "$$desc"; pass=$$((pass+1)); \
		else \
			printf '  %-52s FAIL\n' "$$desc"; \
			echo "    Expected: [$$expected]"; \
			echo "    Got:      [$$actual]"; \
			fail=$$((fail+1)); \
		fi; \
	} && \
	run "cell* x86-64" \
		'3 cell* . 0 exit ;' \
		'24 ' && \
	run "cell* i386" \
		'3 cell* . 0 exit ;' \
		'12 ' \
		./ff && \
	run "fileops loads (x86-64)" \
		'needs fileops.ff ."OK" cr 0 exit ;' \
		'OK' && \
	run "fileops loads (i386)" \
		'needs fileops.ff ."OK" cr 0 exit ;' \
		'OK' \
		./ff && \
	run "time loads (x86-64)" \
		'needs time.ff now 0- 0<> drop IF ."OK" THEN cr 0 exit ;' \
		'OK' && \
	run "time loads (i386)" \
		'needs time.ff now 0- 0<> drop IF ."OK" THEN cr 0 exit ;' \
		'OK' \
		./ff && \
	run "shell loads (x86-64)" \
		'needs shell.ff ."OK" cr 0 exit ;' \
		'OK' && \
	run "shell loads (i386)" \
		'needs shell.ff ."OK" cr 0 exit ;' \
		'OK' \
		./ff && \
	run "mmap.ff loads (x86-64)" \
		'needs lib/mmap.ff ."OK" cr 0 exit ;' \
		'OK' && \
	run "mmap.ff loads (i386)" \
		'needs lib/mmap.ff ."OK" cr 0 exit ;' \
		'OK' \
		./ff && \
	run "mmap stat+read (x86-64)" \
		'needs lib/mmap.ff mkmm m ; "Makefile" m mmapr drop m mm.sz+ @ 0- 0> drop IF ."OK" THEN cr 0 exit ;' \
		'OK' && \
	run "mmap stat+read (i386)" \
		'needs lib/mmap.ff mkmm m ; "Makefile" m mmapr drop m mm.sz+ @ 0- 0> drop IF ."OK" THEN cr 0 exit ;' \
		'OK' \
		./ff && \
	run "ms delay (x86-64)" \
		'needs time.ff ms@ 50 ms ms@ swap - 40 > drop IF ."OK" THEN cr 0 exit ;' \
		'OK' && \
	run "ms delay (i386)" \
		'needs time.ff ms@ 50 ms ms@ swap - 40 > drop IF ."OK" THEN cr 0 exit ;' \
		'OK' \
		./ff && \
	echo "  ----" && \
	echo "  $$pass passed, $$fail failed" && \
	rm -f $(TMP) && \
	[ $$fail -eq 0 ]
