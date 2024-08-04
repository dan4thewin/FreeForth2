# FreeForth2
Derived from FreeForth by Christophe Lavarenne (1956-2011)

## New Features
* turnkey support
* simple locals
* segfault handler
* see disassembles words - Improved! resolves calls/jumps and handles inline strings
* simple approach to arguments
* library search path
* debug compiler makes verbose words

## Changes
* interactive input automatically terminated
* quoted literals may contain spaces
* abandoned windows support
* require explicit conditions before IF

## Docs
* Christophe Lavarenne's writings about the original FreeForth with some notes
  pointing out differences in FreeForth2
  * [FreeForth Home](/docs/FreeForth.md)
  * [FreeForth Primer](/docs/FreeForth_Primer.md)
  * [FreeForth Code Generation](/docs/FreeForth_Code_Generation.md)
* Exploration of FreeForth criticism: [Criticism.md](/docs/Criticism.md)

## Dependencies
* GCC toolchain and 32-bit libraries
  * For example, on Ubuntu LTS run `sudo apt install build-essential gcc-multilib`
* flat assembler, a.k.a. fasm: https://flatassembler.net/
  * Likely available in your Linux distro, e.g., `sudo apt install fasm`

## Build
* run `make` which should create `ff`

## Install
* run `make install` to install `ff` in `$HOME/.local/bin`
  * supporting files install to `$HOME/.local/share/ff`
  * to install to a different directory, set `PREFIX`
    * e.g., `make PREFIX=/opt install`

## Library Search Path
* Interactive `ff` uses files like `ff.ff` and `ff.help` at runtime
* by default it searches:
  * `$HOME/.local/share/ff`
  * `/usr/local/share/ff`
  * `.`
* prepend directories to the search path with the environment variable `FFPATH`
  * e.g., `export FFPATH=/opt/local/ff:/opt/ff`

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
