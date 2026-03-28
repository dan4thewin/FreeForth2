# Experiment 004 — Minimal Forth Compiler
#
# A tiny Forth compiler in C that discovers primitive bytes at
# runtime and compiles definitions by copying them.
# Requires: gcc

CC = gcc
CFLAGS = -O2 -fomit-frame-pointer -fcf-protection=none

.PHONY: all test clean

all: minicompiler

minicompiler: minicompiler.c
	$(CC) $(CFLAGS) -o $@ $<

test: minicompiler
	@./minicompiler

clean:
	rm -f minicompiler
