# FreeForth2
[![Tests Status](https://github.com/dan4thewin/FreeForth2/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/dan4thewin/FreeForth2/actions/workflows/ci.yml?query=branch%3Amaster)

Derived from FreeForth by Christophe Lavarenne (1956-2011)

FreeForth2 offers a novel, lightweight Forth for x86 Linux that deftly blends assembly and Forth.

## Features
FreeForth2 inherits its most distinctive features from FreeForth.
* interactivity through compiled anonymous functions (no separate interpret mode)
* macros generate inline x86 code
* top two stack elements use registers
* register renaming means zero-cost swap
* tail-call optimized to jump
* allows multiple entry-points to a function
* built-in help system

## New Features
FreeForth2 improves usability, Linux integration, and quality controls.
* stat, mmap, getenv, getpid, getppid, system
* turnkey support
* simple locals
* segfault handler
* see disassembles words - Improved! resolves calls/jumps and handles inline strings
* simple approach to arguments
* library search path
* debug compiler makes verbose words
* alternate versions of conditionals use Booleans on the stack
* pictured numeric output
* unit tests
  * with optional `compat.ff`, passes 90% of the core words tests from the Forth 2012 test suite

## Changes from FreeForth
* interactive input automatically terminated (closing `;` assumed)
* quoted literals may contain spaces
* abandoned windows support
* requires explicit conditions before `IF`
  * avoids source of faulty assumptions (see criticism below)
* features separated into files in lib
* leading backquote for hiding headers replaced with `:.` `pvt` and `hidepvt`

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
  * `.`
  * `lib`
  * `$HOME/.local/share/ff`
  * `/usr/local/share/ff`
* insert directories into the search path with the environment variable `FFPATH`
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
needs mmap.ff
mkmm m
: ok?   dup $FF | 1+ drop 0= IF strerror rdrop ;THEN drop ;
: cat   m mmapr ok? m @ m mm.sz+ @ type m munmap 2drop ;
: main  0 argc 1- TIMES 1+ dup argv cat REPEAT ;
$ ./ff -f cat.ff -f mkimage.ff
$ make fftk
fasm fftk.asm fftk.o
flat assembler  version 1.73.27  (16384 kilobytes memory)
3 passes, 23484 bytes.
ld -m elf_i386 -lc --dynamic-linker=/lib/ld-linux.so.2 -s -o fftk fftk.o
$ mv fftk ffcat
$ ./ffcat cat.ff
needs mmap.ff
mkmm m
: ok?   dup $FF | 1+ drop 0= IF strerror rdrop ;THEN drop ;
: cat   m mmapr ok? m @ m mm.sz+ @ type m munmap 2drop ;
: main  0 argc 1- TIMES 1+ dup argv cat REPEAT ;
```
