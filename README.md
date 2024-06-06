# FreeForth2
Derived from FreeForth by Christophe Lavarenne (1956-2011)

## New Features
* turnkey support
* simple locals
* segfault handler
* see disassembles words
* simple approach to arguments
* library search path

## Changes
* interactive input automatically terminated
* quoted literals may contain spaces
* abandoned windows support

## Dependencies
* GCC toolchain and 32-bit libraries
  * For example, on Ubuntu LTS run `sudo apt install build-essential gcc-multilib`
* flat assembler, a.k.a. fasm: https://flatassembler.net/
  * Likely available in your Linux distro, e.g., `sudo apt install fasm`

## Building
* run `make` which should create `ff`

## Building a turnkey binary
* NB. the source should have a `main` word
* run `ff` with `-f` for each source file and `-f mkimage` at the end
  * `mkimage` exports the dictionary to `dict` and compiled code to `cmpl`
* run `make fftk`
  * this assembles `fftk.asm` which includes `dict` and `cmpl`
* rename `fftk` as desired

```
$ cat cat.ff
doargv n^
mkmm m
: ?ior  dup $FF | -1 = 2drop IF strerror rdrop ELSE drop THEN ;
: cat   m mmapr ?ior m @ m mm.sz @ type m munmap 2drop ;
: main  0 argc 1- TIMES 1+ dup argv cat REPEAT ;
$ ./ff -f full.ff -f cat.ff -f mkimage
$ make fftk
fasm fftk.asm fftk.o
flat assembler  version 1.73.27  (16384 kilobytes memory)
3 passes, 23484 bytes.
ld -m elf_i386 -lc --dynamic-linker=/lib/ld-linux.so.2 -s -o fftk fftk.o
$ mv fftk ffcat
$ ./ffcat cat.ff
doargv n^
mkmm m
: ?ior  dup $FF | -1 = 2drop IF strerror rdrop ELSE drop THEN ;
: cat   m mmapr ?ior m @ m mm.sz @ type m munmap 2drop ;
: main  0 argc 1- TIMES 1+ dup argv cat REPEAT ;
```
