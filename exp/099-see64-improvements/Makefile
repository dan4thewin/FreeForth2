FF = ../../ff64-
TIMEOUT = 5
TMP = /tmp/ff-099.ff

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
		"printf 'hide off\nneeds see.ff\nsee dump depth .\\ cr bye\n' > $(TMP); timeout $(TIMEOUT) $(FF) $(TMP) | sed '/^$$/d' | tail -1" \
		"0"; \
	run "see . clean stack" \
		"printf 'hide off\nneeds see.ff\nsee . depth .\\ cr bye\n' > $(TMP); timeout $(TIMEOUT) $(FF) $(TMP) | sed '/^$$/d' | tail -1" \
		"0"; \
	run "see words clean stack" \
		"printf 'hide off\nneeds see.ff\nsee words\` depth .\\ cr bye\n' > $(TMP); timeout $(TIMEOUT) $(FF) $(TMP) | sed '/^$$/d' | tail -1" \
		"0"; \
	run "see max clean stack" \
		"printf 'hide off\nneeds see.ff\nsee max\` depth .\\ cr bye\n' > $(TMP); timeout $(TIMEOUT) $(FF) $(TMP) | sed '/^$$/d' | tail -1" \
		"0"; \
	run "see h.next clean stack" \
		"printf 'hide off\nneeds see.ff\nsee h.next depth .\\ cr bye\n' > $(TMP); timeout $(TIMEOUT) $(FF) $(TMP) | sed '/^$$/d' | tail -1" \
		"0"; \
	run "findnm resolves cr" \
		"printf 'hide off\nneeds see.ff\n\"cr\" findxt drop findnm cr bye\n' > $(TMP); timeout $(TIMEOUT) $(FF) $(TMP) | sed '/^$$/d' | tail -1 | sed 's/^ *0; //'" \
		"cr"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	rm -f $(TMP); \
	[ $$fail -eq 0 ]

clean:
	@rm -f $(TMP)
