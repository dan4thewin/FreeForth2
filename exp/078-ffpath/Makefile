FF = ../../ff64-
ROOT = ../..
TMP = /tmp/ff-078.ff

.PHONY: test clean
test:
	@echo "=== Exp 078: FFPATH and openlib ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(cd $(ROOT) && eval "$$2" 2>&1) || true; \
		if echo "$$result" | grep -qF "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; echo "    expected: $$3"; echo "    got: $$result"; fail=$$((fail+1)); \
		fi; \
	}; \
	run "help via ffpath" \
		'echo "help dup 0 exit" > $(TMP); ./ff64- $(TMP)' \
		"duplicates TOS"; \
	run "lib/x86-64 precedence" \
		'printf "\"testfp.ff\" needed ;\nfrom64 0 exit\n" > $(TMP); ./ff64- $(TMP)' \
		"lib/x86-64"; \
	run "lib fallback" \
		'printf "\"shell.ff\" needed ;\n-v\nbye\n" > $(TMP); ./ff64- $(TMP)' \
		"shell"; \
	run "relative path passthrough" \
		'printf "\"./lib/x86-64/help.ff\" needed ;\nhelp + 0 exit\n" > $(TMP); ./ff64- $(TMP)' \
		"pops-add"; \
	run "needed guard" \
		'printf "\"testfp.ff\" needed ;\n\"testfp.ff\" needed ;\nfrom64 0 exit\n" > $(TMP); ./ff64- $(TMP)' \
		"lib/x86-64"; \
	run "not found error" \
		'echo "\"nosuchfile.ff\" needed 0 exit" > $(TMP); ./ff64- $(TMP)' \
		"open file"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	test $$fail -eq 0

clean:
	@rm -f $(TMP)
