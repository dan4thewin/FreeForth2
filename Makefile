SHELL=/bin/bash
LD=ld -m elf_i386 -lc --dynamic-linker=/lib/ld-linux.so.2 -s

all: ff

ff.o: fflin.asm ff.asm fflinio.asm ff.boot fflin.boot
	fasm $< $@

ff: ff.o
	$(LD) -o $@ $<

cmpl dict: ff
	./ff -f mkimage.ff

fftk.o: fftk.asm cmpl dict
	fasm $< $@

fftk: fftk.o
	$(LD) -o $@ $<

clean:
	rm -f ff fftk *.o

test1:
	@set -o pipefail; \
	for d in test/*; do \
		echo -n $$d; printf %$$((20-$${#d}))s; \
		$(FF) $(ARGS) -f $$d | tail -1; let e+=$$?; \
	done; exit $$e

test: ff
	@echo ff; \
	$(MAKE) -s ff FF=./ff test1; \
	echo ff +longconds; \
	$(MAKE) -s ff FF='./ff +longconds' test1; \
	echo fftk; \
	./ff -f test.ff -f mkimage.ff && $(MAKE) -s fftk >/dev/null; \
	$(MAKE) -s FF=./fftk test1; \
	echo fftk +longconds; \
	./ff +longconds -f test.ff -f mkimage.ff && $(MAKE) -s fftk >/dev/null; \
	$(MAKE) -s FF=./fftk test1

ci:
	sudo apt-get install -y fasm gcc-multilib
	$(MAKE) ARGS=nocolor test

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
