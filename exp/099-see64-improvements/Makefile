FF = ../../ff64
TIMEOUT = 5

test:
	@echo "=== Exp 099: see improvements ==="
	@pass=0; fail=0; \
	run () { \
		printf "  %-40s" "$$1"; \
		actual=$$(eval "$$2" 2>/dev/null) || true; \
		if [ "$$actual" = "$$3" ]; then \
			echo "PASS"; pass=$$((pass+1)); \
		else \
			echo "FAIL"; fail=$$((fail+1)); \
			echo "    expected: [$$3]"; \
			echo "    actual:   [$$actual]"; \
		fi; \
	}; \
	run "see dump clean stack" \
		"echo 'see dump depth .\ cr bye' | timeout $(TIMEOUT) $(FF) 'hide off' -f ../../lib/x86-64/see.ff | sed '/^$$/d' | tail -1" \
		"0"; \
	run "see . clean stack" \
		"echo 'see . depth .\ cr bye' | timeout $(TIMEOUT) $(FF) 'hide off' -f ../../lib/x86-64/see.ff | sed '/^$$/d' | tail -1" \
		"0"; \
	run "see words clean stack" \
		"echo 'see words\` depth .\ cr bye' | timeout $(TIMEOUT) $(FF) 'hide off' -f ../../lib/x86-64/see.ff | sed '/^$$/d' | tail -1" \
		"0"; \
	run "see max clean stack" \
		"echo 'see max\` depth .\ cr bye' | timeout $(TIMEOUT) $(FF) 'hide off' -f ../../lib/x86-64/see.ff | sed '/^$$/d' | tail -1" \
		"0"; \
	run "see h.next clean stack" \
		"echo 'see h.next depth .\ cr bye' | timeout $(TIMEOUT) $(FF) 'hide off' -f ../../lib/x86-64/see.ff | sed '/^$$/d' | tail -1" \
		"0"; \
	run "findnm resolves cr" \
		"printf '\"cr\" findxt drop findnm cr bye\n' | timeout $(TIMEOUT) $(FF) 'hide off' -f ../../lib/x86-64/see.ff | sed '/^$$/d' | tail -1 | sed 's/^ *0; //'" \
		"cr"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]
