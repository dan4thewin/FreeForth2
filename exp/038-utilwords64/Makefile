FF=../../ff64
BOOT=../../ff64.boot
SHELL=/bin/bash

test: $(FF)
	@echo "=== Exp 038: Utility words (.#s, .b, .w, h.next, h.name, words) ==="
	@pass=0; fail=0; \
	run() { \
		result=$$(echo "$$2" | $(FF) -f $(BOOT) 2>/dev/null); \
		if echo "$$result" | grep -q "$$3"; then \
			echo "  PASS: $$1"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$1"; \
			echo "    Expected: $$3"; \
			echo "    Got: $$result"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	run ".b prints 2 hex digits" '$$AB .b cr ;' 'ab'; \
	run ".b prints leading zero" '$$0F .b cr ;' '0f'; \
	run ".w prints 4 hex digits" '$$ABCD .w cr ;' 'abcd'; \
	run ".w prints leading zeros" '$$1F .w cr ;' '001f'; \
	run ".#s custom width" '$$ABC 3 .#s cr ;' 'abc'; \
	run "h.next advances" ': t H@ h.next H@ - . cr ; t ;' '12'; \
	run "h.name prints name" ': t H@ h.name cr drop ; t ;' 't'; \
	run "h.name second entry" ': t H@ h.next dup h.name cr drop ; t ;' 'words'; \
	run "words lists dict" 'words cr ;' 'words'; \
	run "words has builtins" 'words cr ;' 'emit'; \
	run "words has macros" 'words cr ;' 'dup'; \
	run "ct=1 in loop" ': t 0 5 BEGIN 0- 0> WHILE swap h.sz + swap 1 - REPEAT drop . cr ; t ;' '45'; \
	run "ct=1 no stack corrupt" ': t 3 BEGIN 0- 0> WHILE h.sz drop 1 - REPEAT drop ; 42 t . cr ;' '42'; \
	run "type in loop" 'variable b $$41 b c! $$42 b 1 + c! $$43 b 2 + c! b 3 type cr ;' 'ABC'; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"

.PHONY: test
