FF=../../ff64
SHELL=/bin/bash

test: $(FF)
	@echo "=== Exp 039: Debug output (.s, .h, .l, .hdr, .hdrs, depth fix) ==="
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
	run "depth empty" ': t depth . cr ; t ;' '0'; \
	run "depth 1" ': t depth . cr drop ; 1 t ;' '1'; \
	run "depth 3" ': t depth . cr 2drop drop ; 1 2 3 t ;' '3'; \
	run ".s shows depth" '1 2 3 ; .s ;' '3;'; \
	run ".s shows items" '1 2 3 ; .s ;' '1 2 3'; \
	run ".h shows free" '.h ;' 'free:'; \
	run ".h shows SC" '.h ;' 'SC='; \
	run ".l prints 8 hex" '$$DEADBEEF .l cr ;' 'deadbeef'; \
	run ".hdr shows entry" ': test ; H@ .hdr ;' 'test'; \
	run ".hdr shows xt" ': test ; H@ .hdr ;' ':'; \
	run ".hdrs lists entries" '.hdrs ;' 'words'; \
	run ".hdrs shows ct" '.hdrs ;' ' 0 '; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"

.PHONY: test
