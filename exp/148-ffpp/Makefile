TESTS = test-comments test-whitespace test-strings test-include \
        test-nested test-incerr test-mixed

.PHONY: test clean

ffpp: ffpp.asm
	fasm ffpp.asm ffpp
	chmod +x ffpp

test: ffpp
	@pass=0; fail=0; \
	for t in $(TESTS); do \
		echo -n "$$t: "; \
		if [ "$$t" = "test-incerr" ]; then \
			./ffpp $$t.in 2>/dev/null | diff -u $$t.exp - > /dev/null 2>&1; \
		else \
			./ffpp $$t.in | diff -u $$t.exp - > /dev/null 2>&1; \
		fi; \
		if [ $$? -eq 0 ]; then \
			echo "ok"; pass=$$((pass+1)); \
		else \
			echo "FAIL"; fail=$$((fail+1)); \
			echo "  expected:"; cat $$t.exp; \
			echo "  got:"; \
			if [ "$$t" = "test-incerr" ]; then \
				./ffpp $$t.in 2>/dev/null; \
			else \
				./ffpp $$t.in; \
			fi; \
		fi; \
	done; \
	if [ $$fail -eq 0 ]; then echo "PASSED"; else echo "$$fail FAILED"; exit 1; fi

clean:
	rm -f ffpp
