FF=../../ff64
BOOT=../../ff64.boot
SHELL=/bin/bash

test: $(FF)
	@echo "=== Exp 045: create/variable/mark/marker ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(echo "$$2" | $(FF) -f $(BOOT) 2>/dev/null); \
		if echo "$$result" | grep -qF -- "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; \
			echo "    Expected: $$3"; \
			echo "    Got: $$result"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	run "create-allot" \
		'create buf 8 allot 42 buf ! buf @ . cr ;' \
		'42'; \
	run "variable-store-fetch" \
		'variable x 99 x ! x @ . cr ;' \
		'99'; \
	run "variable-init-zero" \
		'variable x x @ . cr ;' \
		'0'; \
	run "mark-basic" \
		'mark foo : t 42 . cr ; t foo ." ok" cr ;' \
		'ok'; \
	run "mark-forgets-word" \
		'mark foo : t 42 . cr ; t foo t ;' \
		'error:'; \
	run "mark-nested" \
		'mark m1 : a 10 . ; mark m2 : b 20 . ; a b m2 a m1 ." ok" cr ;' \
		'ok'; \
	run "mark-self-forgets" \
		'mark m1 : t 1 ; m1 m1 ;' \
		'error:'; \
	run "pvtmargin-basic" \
		'pvtmargin ." ok" cr ;' \
		'ok'; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]
