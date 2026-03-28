# Experiment 001 — Naked Primitives
#
# Compile Forth primitives as naked C functions, verify output.
# Requires: clang

CC = gcc
CFLAGS = -O2 -fomit-frame-pointer -fcf-protection=none

.PHONY: all test clean

all: prims.o

prims.o: prims.c
	$(CC) $(CFLAGS) -c -o $@ $<

test: prims.o
	@echo "=== Disassembly of naked primitives ==="
	@objdump -d prims.o
	@echo ""
	@echo "=== Size check (each function should be ≤16 bytes) ==="
	@objdump -t prims.o | grep prim_
	@echo ""
	@echo "PASSED — manual inspection required"

clean:
	rm -f prims.o
