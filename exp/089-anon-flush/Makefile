FF = ../../ff64-
FF32 = ../../ff
TMP = /tmp/ff-089.ff
TIMEOUT = 3

.PHONY: test

test:
	@echo "=== Exp 089: anonymous block flush for variable/constant ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(eval "$$2" 2>&1); rc=$$?; \
		if echo "$$result" | grep -qF "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; echo "    expected: $$3"; echo "    got: $$result"; fail=$$((fail+1)); \
		fi; \
	}; \
	run "variable flushes anon" \
		"echo ': a .\"A\" ;' > /tmp/t089a.ff; echo a >> /tmp/t089a.ff; echo 'variable d89a' >> /tmp/t089a.ff; echo ': b .\"B\" ;' >> /tmp/t089a.ff; echo b >> /tmp/t089a.ff; echo 'bye' >> /tmp/t089a.ff; timeout $(TIMEOUT) $(FF) /tmp/t089a.ff" \
		"AB"; \
	run "constant flushes anon" \
		"echo ': a .\"A\" ;' > /tmp/t089b.ff; echo a >> /tmp/t089b.ff; echo '42 constant d89b' >> /tmp/t089b.ff; echo ': b .\"B\" ;' >> /tmp/t089b.ff; echo b >> /tmp/t089b.ff; echo 'bye' >> /tmp/t089b.ff; timeout $(TIMEOUT) $(FF) /tmp/t089b.ff" \
		"AB"; \
	run "colon still flushes" \
		"echo ': a .\"A\" ;' > /tmp/t089c.ff; echo a >> /tmp/t089c.ff; echo ': b .\"B\" ;' >> /tmp/t089c.ff; echo b >> /tmp/t089c.ff; echo 'bye' >> /tmp/t089c.ff; timeout $(TIMEOUT) $(FF) /tmp/t089c.ff" \
		"AB"; \
	run "loadfile variable flush" \
		"echo ': foo .\"foo\" ;' > /tmp/t089.ff; echo 'foo' >> /tmp/t089.ff; echo 'variable dummy89' >> /tmp/t089.ff; echo ': bar .\"bar\" ;' >> /tmp/t089.ff; echo 'bar' >> /tmp/t089.ff; echo 'bye' >> /tmp/t089.ff; timeout $(TIMEOUT) $(FF) /tmp/t089.ff" \
		"foobar"; \
	run "t1 matches i386" \
		"cat t1 > $(TMP); echo bye >> $(TMP); timeout $(TIMEOUT) $(FF) $(TMP)" \
		"foobar"; \
	run "segv still works" \
		"printf '0@ . cr\n0 exit\n' > $(TMP); timeout $(TIMEOUT) $(FF) $(TMP)" \
		"SEGV caught"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	test $$fail -eq 0
