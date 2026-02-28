FF = ../../ff64
TIMEOUT = 3

.PHONY: test

test:
	@echo "=== Exp 088: SEGV recovery fix ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(eval "$$2" 2>&1); rc=$$?; \
		if eval "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; echo "    got (rc=$$rc): $$result"; fail=$$((fail+1)); \
		fi; \
	}; \
	run "segv-message" \
		"echo '0 @' | timeout $(TIMEOUT) $(FF)" \
		"echo \"\$$result\" | grep -qF 'SEGV caught'"; \
	run "segv-recovery" \
		"printf '0 @\n0 exit\n' | timeout $(TIMEOUT) $(FF)" \
		"[ \$$rc -eq 0 ]"; \
	run "segv-continue" \
		"printf '0 @\n42 .\n0 exit\n' | timeout $(TIMEOUT) $(FF)" \
		"echo \"\$$result\" | grep -q '42'"; \
	run "segv-not-assembly" \
		"printf '0 @\n0 exit\n' | timeout $(TIMEOUT) $(FF)" \
		"! echo \"\$$result\" | grep -qF '***'"; \
	run "sigaction-called" \
		"printf '0@ . cr 0 exit\n' | timeout $(TIMEOUT) $(FF)" \
		"echo \"\$$result\" | grep -qF 'SEGV caught'"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	test $$fail -eq 0
