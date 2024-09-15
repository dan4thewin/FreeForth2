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

test: ff
	@echo ff
	@for d in test/*; do echo -ne $$d \\e[21G; ./ff -f $$d | tail -1; done
	@echo ff +longconds
	@for d in test/*; do echo -ne $$d \\e[21G; ./ff +longconds -f $$d | tail -1; done
	@echo fftk
	@./ff -f test.ff -f mkimage.ff
	@$(MAKE) fftk >/dev/null
	@for d in test/*; do echo -ne $$d \\e[21G; ./fftk -f $$d | tail -1; done
	@echo fftk +longconds
	@./ff +longconds -f test.ff -f mkimage.ff
	@$(MAKE) fftk >/dev/null
	@for d in test/*; do echo -ne $$d \\e[21G; ./fftk -f $$d | tail -1; done

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

.PHONY: clean test install install-bin install-share
