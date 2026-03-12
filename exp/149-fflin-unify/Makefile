FF = ../../ff
FF64 = ../../ff64

test:
	@echo "=== Exp 149: fflin unification ==="
	@pass=0; fail=0; \
	run () { \
		printf "  %-42s" "$$1"; \
		actual=$$(eval "$$2" 2>/dev/null) || true; \
		if echo "$$actual" | grep -q "$$3"; then \
			echo "PASS"; pass=$$((pass+1)); \
		else \
			echo "FAIL"; fail=$$((fail+1)); \
			echo "    expected pattern: [$$3]"; \
			echo "    actual: [$$actual]"; \
		fi; \
	}; \
	run "i386 SEGV catches null deref" \
		"echo '0 @ ;' | timeout 5 $(FF)" \
		"SEGV caught"; \
	run "i386 SEGV recovers to REPL" \
		"echo '0 @ 42 . cr ;' | timeout 5 $(FF)" \
		"42"; \
	run "i386 envp via cell*" \
		"echo 'envp @ zlen type cr ;' | timeout 5 $(FF)" \
		"="; \
	run "i386 features has boot" \
		"echo '-v ;' | timeout 5 $(FF)" \
		"boot"; \
	run "i386 features has segv" \
		"echo '-v ;' | timeout 5 $(FF)" \
		"segv"; \
	run "ff64 SEGV still works" \
		"echo '0 @ ;' | timeout 5 $(FF64)" \
		"SEGV caught"; \
	run "ff64 features has segv" \
		"echo '-v ;' | timeout 5 $(FF64)" \
		"segv"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	test $$fail -eq 0
