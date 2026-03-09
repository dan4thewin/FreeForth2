TESTS = test-comments test-whitespace test-strings test-include \
        test-nested test-incerr test-mixed test-macro64-on test-macro64-off

.PHONY: test clean

ffpp: ffpp.asm
	fasm ffpp.asm ffpp
	chmod +x ffpp

test: ffpp
	@pass=0; fail=0; \
	for t in $(TESTS); do \
		echo -n "$$t: "; \
		case $$t in \
			*-on) ./ffpp --64 test-macro64.in > /tmp/ffpp-out;; \
			*-off) ./ffpp test-macro64.in > /tmp/ffpp-out;; \
			test-incerr) ./ffpp $$t.in > /tmp/ffpp-out 2>/dev/null;; \
			*) ./ffpp $$t.in > /tmp/ffpp-out;; \
		esac; \
		if diff -u $$t.exp /tmp/ffpp-out > /dev/null 2>&1; then \
			echo "ok"; pass=$$((pass+1)); \
		else \
			echo "FAIL"; fail=$$((fail+1)); \
			diff -u $$t.exp /tmp/ffpp-out; \
		fi; \
	done; \
	rm -f /tmp/ffpp-out; \
	if [ $$fail -eq 0 ]; then echo "PASSED"; else echo "$$fail FAILED"; exit 1; fi

clean:
	rm -f ffpp
