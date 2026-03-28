# Experiment 002 — Runtime Byte Extraction
#
# Read primitive bytes at runtime via pointer arithmetic.
# Requires: clang

CC = gcc
CFLAGS = -O2 -fomit-frame-pointer -fcf-protection=none

.PHONY: all test clean

all: extract

extract: extract.c
	$(CC) $(CFLAGS) -o $@ $<

test: extract
	@./extract

clean:
	rm -f extract
