# Experiment 007 — Minimal Flow Control
#
# IF...THEN and BEGIN...UNTIL with stack booleans.
# Per-arch branch emission + C reference functions for porting.

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
