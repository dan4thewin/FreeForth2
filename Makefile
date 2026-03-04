SHELL=/bin/bash
LD=ld -m elf_i386 -lc --dynamic-linker=/lib/ld-linux.so.2 -s
LD64=ld -m elf_x86_64 -lc -ldl --dynamic-linker=/lib64/ld-linux-x86-64.so.2

all: ff ff64 ff64s

ff.o: fflin.asm ff.asm fflinio.asm ff.boot fflin.boot
	fasm $< $@

ff: ff.o
	$(LD) -o $@ $<

ff64.boot.min: ff64.boot fflin64.boot
	grep -h '^[: _$$A-Za-z0-9]' $^ > $@

ff64.o: fflin64.asm ff64.asm ff64.boot.min
	fasm $< $@

ff64: ff64.o
	$(LD64) -o $@ $<

ff64s: fflin64s.asm ff64.asm ff64.boot.min
	fasm $< $@
	chmod +x $@

cmpl dict: ff
	./ff -f mkimage.ff

cmpl64 cmpl64.cfg: ff64
	./ff64 -f lib/64/mkimage.ff

fftk.o: fftk.asm cmpl dict
	fasm $< $@

fftk: fftk.o
	$(LD) -o $@ $<

fftk64.o: fftk64.asm cmpl64 cmpl64.cfg
	fasm $< $@

fftk64: fftk64.o
	$(LD64) -o $@ $<

clean:
	rm -f ff ff64 ff64s fftk fftk64 *.o ff64.boot.min cmpl64 cmpl64.cfg

test1:
	@set -o pipefail; \
	for d in `ls test/* | grep -v 64`; do \
		echo -n $$d; printf %$$((20-$${#d}))s; \
		$(FF) $(ARGS) -f $$d | tail -1; let e+=$$?; \
	done; exit $$e

test64: ff64
	@set -o pipefail; e=0; \
	skip="core1.ff core2.ff mmap.ff"; \
	for d in test/*; do \
		b=$$(basename $$d); \
		echo -n $$d; printf %$$((20-$${#d}))s; \
		case " $$skip " in *" $$b "*) echo "SKIPPED"; continue;; esac; \
		r=$$(timeout 10 ./ff64 ': prompt ;' -f $$d 2>&1 | tail -1); \
		echo "$$r"; \
		echo "$$r" | grep -q PASSED || echo "$$r" | grep -q SKIPPED || let e+=1; \
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
