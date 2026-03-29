# Experiment 009 — Comparators and Selectors
#
# Sacrificial compare pattern: ALU ops end with `return tos == 0`
# which coerces GCC to emit flag-setting instructions (SUBS/ADDS
# on ARM64).  Self-calibrating extraction trims sacrifice bytes.
#
# Full matrix: all ALU ops × all Jcc selectors (0=, 0<>, 0<, 0>)
# plus non-consuming binary CMP for equality/inequality/ordering.

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
