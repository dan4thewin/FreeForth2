FF = ../../ff-
FF64 = ../../ff64-
TMP = /tmp/ff-149.ff

test:
	@echo "=== Exp 149: fflin unification ==="
	@pass=0; fail=0; \
	run () { \
		printf "  %-42s" "$$1"; \
		actual=$$(eval "$$2" 2>&1) || true; \
		if echo "$$actual" | grep -q "$$3"; then \
			echo "PASS"; pass=$$((pass+1)); \
		else \
			echo "FAIL"; fail=$$((fail+1)); \
			echo "    expected pattern: [$$3]"; \
			echo "    actual: [$$actual]"; \
		fi; \
	}; \
	run "i386 SEGV catches null deref" \
		"echo '0 @ ;' > $(TMP); timeout 0.5 ../../ff < $(TMP)" \
		"SEGV caught"; \
	run "i386 SEGV recovers to REPL" \
		"printf '0 @\n42 . cr ;\n' > $(TMP); timeout 0.5 ../../ff < $(TMP)" \
		"42"; \
	run "i386 envp via cell*" \
		"echo 'envp @ zlen type cr ;' > $(TMP); timeout 0.5 $(FF) $(TMP)" \
		"="; \
	run "i386 features has locals" \
		"echo '-v ;' > $(TMP); timeout 0.5 $(FF) $(TMP)" \
		"locals"; \
	run "ff64 SEGV still works" \
		"echo '0 @ ;' > $(TMP); timeout 0.5 $(FF64) $(TMP)" \
		"SEGV caught"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	test $$fail -eq 0

clean:
	@rm -f $(TMP)
