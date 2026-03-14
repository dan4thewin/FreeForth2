SHELL=/bin/bash
LD=ld -m elf_i386 -lc --dynamic-linker=/lib/ld-linux.so.2 -s
LD64=ld -m elf_x86_64 -lc -ldl --dynamic-linker=/lib64/ld-linux-x86-64.so.2

all: ff ff64 ff64s

ffpp: ffpp.asm
	fasm $< $@
	chmod +x $@

ff.o: fflin.asm ff.asm fflinio.asm ff.boot fflin2.boot
	fasm $< $@

ff: ff.o
	$(LD) -o $@ $<

ff.boot: ff2.boot fflin2.boot openlib.ff ffpp
	./ffpp $< > $@

ff64.boot: ff2.boot fflin2.boot openlib.ff ffpp
	./ffpp --64 $< > $@

ff64.o: fflin64.asm ff64.asm ff64.boot fflin2.boot
	fasm $< $@

ff64: ff64.o
	$(LD64) -o $@ $<

ff64s: fflin64s.asm ff64.asm ff64.boot fflin2.boot
	fasm $< $@
	chmod +x $@

cmpl dict: ff
	./ff -f mkimage.ff

cmpl64 cmpl64.cfg: ff64
	./ff64 -f lib/x86-64/mkimage.ff

fftk.o: fftk.asm cmpl dict
	fasm $< $@

fftk: fftk.o
	$(LD) -o $@ $<

fftk64.o: fftk64.asm cmpl64 cmpl64.cfg
	fasm $< $@

fftk64: fftk64.o
	$(LD64) -o $@ $<

fftk64s: fftk64s.asm
	fasm $< $@
	chmod +x $@

clean:
	rm -f ff ff64 ff64s fftk fftk64 fftk64s ffpp *.o ff64.boot.min cmpl64 cmpl64.cfg

test1:
	@set -o pipefail; \
	for d in `ls test/*.ff | grep -v 64`; do \
		echo -n $$d; printf %$$((20-$${#d}))s; \
		timeout 10 $(FF) $(ARGS) -f $$d | tail -1; let e+=$$?; \
	done; exit $$e

test64: ff64
	@set -o pipefail; e=0; \
	skip="core1.ff core2.ff"; \
	for d in test/*.ff; do \
		b=$$(basename $$d); \
		echo -n $$d; printf %$$((20-$${#d}))s; \
		case " $$skip " in *" $$b "*) echo "SKIPPED"; continue;; esac; \
		r=$$(timeout 10 ./ff64 ': prompt ;' -f $$d 2>&1 | tail -1); \
		echo "$$r"; \
		echo "$$r" | grep -q PASSED || echo "$$r" | grep -q SKIPPED || let e+=1; \
	done; exit $$e

testexp: ff64
	timeout 60 $(MAKE) -C exp test

test: ff
	@echo ff; \
	$(MAKE) -s ff FF=./ff test1; \
	echo ff +longconds; \
	$(MAKE) -s ff FF='./ff +longconds' test1; \
	echo fftk; \
	timeout 10 ./ff -f test.ff -f mkimage.ff && $(MAKE) -s fftk >/dev/null; \
	$(MAKE) -s FF=./fftk test1; \
	echo fftk +longconds; \
	timeout 10 ./ff +longconds -f test.ff -f mkimage.ff && $(MAKE) -s fftk >/dev/null; \
	$(MAKE) -s FF=./fftk test1

testnc:
	$(MAKE) 'ARGS=needs console.ff nocolor' test

testall:
	@timeout 60 $(MAKE) testnc testexp 2>/dev/null | \
	perl -lne 'print "$$1$$2" if m/^(not.*)|^(?!make)\S+\s+([A-Z].*)/' | \
	sort | uniq -c

ci:
	sudo apt-get install -y fasm gcc-multilib
	$(MAKE) testnc

PREFIX=$$HOME/.local
FFBIN=$(PREFIX)/bin
install-bin: ff
	install -m 775 -d $(FFBIN)
	install -m 775 $^ $(FFBIN)

FFSHARE=$(PREFIX)/share/ff
install-share: ff.ff ff.help lib/*
	install -m 775 -d $(FFSHARE)
	install -m 664 $^ $(FFSHARE)

install: install-bin install-share

.PHONY: clean test1 test ci install install-bin install-share
