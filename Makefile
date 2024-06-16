LD=ld -m elf_i386 -lc --dynamic-linker=/lib/ld-linux.so.2 -s

all: ff

ff.o: fflin.asm ff.asm fflinio.asm ff.boot fflin.boot
	fasm $< $@

ff: ff.o
	$(LD) -o $@ $<

cmpl dict: ff
	./ff -f mkimage

fftk.o: fftk.asm cmpl dict
	fasm $< $@

fftk: fftk.o
	$(LD) -o $@ $<

clean:
	rm -f ff fftk *.o


PREFIX=$$HOME/.local
FFBIN=$(PREFIX)/bin
install-bin: ff
	install -m 775 -d $(FFBIN)
	install -m 775 $^ $(FFBIN)

FFSHARE=$(PREFIX)/share/ff
install-share: ff.ff full.ff ff.help see
	install -m 775 -d $(FFSHARE)
	install -m 664 $^ $(FFSHARE)

install: install-bin install-share

.PHONY: clean install install-bin install-share
