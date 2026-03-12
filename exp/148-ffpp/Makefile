TESTS = test-comments test-whitespace test-strings test-include \
        test-nested test-incerr test-mixed test-cond64 test-cond32 \
        test-condelse

.PHONY: test clean

ffpp: ffpp.asm
	fasm ffpp.asm ffpp
	chmod +x ffpp

test: ffpp
	@pass=0; fail=0; \
	for t in $(TESTS); do \
		echo -n "$$t: "; \
		case $$t in \
			test-cond64) ./ffpp --64 test-cond.in > /tmp/ffpp-out;; \
			test-cond32) ./ffpp test-cond.in > /tmp/ffpp-out;; \
			test-condelse) ./ffpp --64 test-condelse.in > /tmp/ffpp-out;; \
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
