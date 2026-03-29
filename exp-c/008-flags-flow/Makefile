# Experiment 008 — FLAGS-based Flow Control
#
# Decomposes primitives: C ALU ops + inline asm stack macros.
# FLAGS flow through LEA-based drop.  0= / 0<> are Jcc selectors.

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
