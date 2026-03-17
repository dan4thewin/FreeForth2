FF = ../../ff
FF64 = ../../ff64

.PHONY: test clean

test:
	@echo "Experiment 150: boot alignment verification"
	@echo "--- i386 REPL echo test ---"
	@echo '."hello" cr ;' | $(FF) -f ff.boot 2>/dev/null | grep -q hello && echo "  i386 echo: PASS" || echo "  i386 echo: FAIL"
	@echo "--- x86-64 REPL echo test ---"
	@echo '."hello" cr ;' | $(FF64) 2>/dev/null | grep -q hello && echo "  ff64 echo: PASS" || echo "  ff64 echo: FAIL"
	@echo "--- i386 -f test ---"
	@echo '."from-f" cr ; t bye' > /tmp/exp150.ff && $(FF) -f /tmp/exp150.ff 2>/dev/null | grep -q from-f && echo "  i386 -f:   PASS" || echo "  i386 -f:   FAIL"
	@echo "--- x86-64 -f test ---"
	@$(FF64) -f /tmp/exp150.ff 2>/dev/null | grep -q from-f && echo "  ff64 -f:   PASS" || echo "  ff64 -f:   FAIL"
	@rm -f /tmp/exp150.ff
	@echo "PASSED"

clean:
	@rm -f /tmp/exp150.ff
