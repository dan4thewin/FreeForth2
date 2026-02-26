FF=../../ff64
SHELL=/bin/bash

test: $(FF)
	@echo "=== Exp 040: Character literals and prompt cleanup ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(echo "$$2" | $(FF) 2>/dev/null); \
		if echo "$$result" | grep -q "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; \
			echo "    Expected: $$3"; \
			echo "    Got: $$result"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	run "char A" "'A' . cr ;" '65'; \
	run "char zero" "'0' . cr ;" '48'; \
	run "char tilde" "'~' . cr ;" '126'; \
	run "char semicolon" "';' . cr ;" '59'; \
	run "char in word" ": t 'Z' emit cr ; t ;" 'Z'; \
	run "char in expression" ": t 'A' 1 + emit cr ; t ;" 'B'; \
	run "char with IF" ": t 'Y' 0- 0<> IF emit THEN cr ; t ;" 'Y'; \
	run "prompt uses char" '.s ;' ';'; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"

.PHONY: test
