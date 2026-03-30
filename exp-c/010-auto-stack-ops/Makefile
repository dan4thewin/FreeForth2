# Experiment 010 — Auto-Calibrating Stack Operations
#
# Tests whether C-compiled stack ops preserve CPU flags.
# Uses C version when they do (ARM64), falls back to inline asm
# when they don't (x86-64 dsp++ → ADD clobbers flags).

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
