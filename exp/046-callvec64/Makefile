FF=../../ff64
SHELL=/bin/bash

test: $(FF)
	@echo "=== Exp 046: -call, tick, vector manipulation ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(echo "$$2" | $(FF) 2>/dev/null); \
		if echo "$$result" | grep -qF -- "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; \
			echo "    Expected: $$3"; \
			echo "    Got: $$result"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	run "tick basic" \
		': hi 42 . cr ; : t hi '"'"' execute ; t ;' \
		'42'; \
	run "tick lit value" \
		': hi 42 . cr ; : t hi '"'"' ; t .x cr ;' \
		'0;'; \
	run "vector redirect !^" \
		':^ g ." hello" cr ; : nb ." nb" cr ; nb '"'"' g '"'"' !^ g ;' \
		'nb'; \
	run "vector @^" \
		':^ g ." hello" cr ; g '"'"' @^ .x cr ;' \
		'0;'; \
	run "vector n^" \
		':^ g ." hello" cr ; g '"'"' n^ g ." done" cr ;' \
		'done'; \
	run "vector x^" \
		':^ g ." hello" cr ; : nb ." nb" cr ; nb '"'"' g '"'"' !^ g g '"'"' x^ ;' \
		'hello'; \
	run "callmark cleared by -c" \
		': t 42 . ; t -c drop callmark @ . cr ;' \
		'0'; \
	run "? conditional keeps call" \
		': hw ." hw" cr ; : t hw ? ; t ;' \
		'hw'; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]
