FF = ../../ff64
FFTK = ../../fftk64
MKIMAGE = ../../lib/x86-64/mkimage.ff
ROOT = ../..
FASM = fasm
LD = ld -m elf_x86_64 -lc -ldl --dynamic-linker=/lib64/ld-linux-x86-64.so.2

.PHONY: test
test:
	@echo "=== Exp 073: Turnkey builder ==="
	@pass=0; fail=0; \
	run() { \
		name="$$1"; shift; \
		input="$$1"; shift; \
		expected="$$1"; shift; \
		actual=$$(printf '%-80s' "$$input" | eval "$$@" 2>&1) || true; \
		if echo "$$actual" | grep -qF "$$expected"; then \
			echo "  PASS: $$name"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$name"; \
			echo "    Expected: $$expected"; \
			echo "    Got: $$actual"; \
			fail=$$((fail+1)); \
		fi; \
	}; \
	build_turnkey() { \
		rm -f $(ROOT)/cmpl64 $(ROOT)/cmpl64.cfg; \
		if [ -n "$$1" ]; then \
			cd $(ROOT) && ./ff64 -f "$$1" -f lib/x86-64/mkimage.ff && \
			$(FASM) fftk64.asm fftk64.o >/dev/null && \
			$(LD) -o fftk64 fftk64.o 2>/dev/null; \
			cd - >/dev/null; \
		else \
			cd $(ROOT) && ./ff64 -f lib/x86-64/mkimage.ff && \
			$(FASM) fftk64.asm fftk64.o >/dev/null && \
			$(LD) -o fftk64 fftk64.o 2>/dev/null; \
			cd - >/dev/null; \
		fi; \
	}; \
	echo ': main ."Hello,_turnkey!" cr ;' > /tmp/tk_hello.ff; \
	build_turnkey /tmp/tk_hello.ff; \
	run "turnkey hello" "" "Hello, turnkey!" $(FFTK); \
	echo ': main 42 . cr ;' > /tmp/tk_42.ff; \
	build_turnkey /tmp/tk_42.ff; \
	run "turnkey 42" "" "42" $(FFTK); \
	echo ': main dup . cr ;' > /tmp/tk_dup.ff; \
	build_turnkey /tmp/tk_dup.ff; \
	run "turnkey dup-on-empty" "" "0" $(FFTK); \
	build_turnkey; \
	run "repl arithmetic" '42 . cr' "42" $(FFTK); \
	run "repl string" '"Hello" type cr' "Hello" $(FFTK); \
	run "repl definition" ': sq dup * ; 7 sq . cr' "49" $(FFTK); \
	echo "  ----"; \
	echo "  $$pass passed, $$fail failed"; \
	test $$fail -eq 0
