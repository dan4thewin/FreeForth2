# Experiment 006 — Portable mini-compiler (x86-64 + ARM64)
#
# Runs on Linux x86-64 and macOS ARM64.
# Requires: real GCC (not Apple clang) for global register variables.

# On macOS with Homebrew GCC, override: make CC=gcc-15
CC ?= gcc
CFLAGS = -O2 -fomit-frame-pointer -Wall -Wextra -Werror

.PHONY: all test clean

all: minicompiler

minicompiler: minicompiler.c
	$(CC) $(CFLAGS) -o $@ $<

test: minicompiler
	@./minicompiler

clean:
	rm -f minicompiler
