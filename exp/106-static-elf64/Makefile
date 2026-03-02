FASM = fasm

.PHONY: test clean

hello: hello.asm
	$(FASM) $< $@
	chmod +x $@

test: hello
	@echo "=== Exp 106: Static ELF64 via FASM ==="
	@pass=0; fail=0; \
	actual=$$(./hello); \
	expected="Hello from static ELF64!"; \
	if [ "$$actual" = "$$expected" ]; then \
		echo "  PASS: hello output"; pass=$$((pass+1)); \
	else \
		echo "  FAIL: hello output"; \
		echo "    expected: [$$expected]"; \
		echo "    actual:   [$$actual]"; \
		fail=$$((fail+1)); \
	fi; \
	if readelf -d hello 2>&1 | grep -q "not found\|no dynamic"; then \
		echo "  PASS: no dynamic section"; pass=$$((pass+1)); \
	else \
		echo "  FAIL: has dynamic section"; \
		readelf -d hello; \
		fail=$$((fail+1)); \
	fi; \
	size=$$(stat -c%s hello); \
	echo "  INFO: binary size = $$size bytes"; \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	test $$fail -eq 0

clean:
	rm -f hello
