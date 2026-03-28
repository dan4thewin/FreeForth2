# Experiment 003 — Copy and Execute
#
# Compose primitive bytes into an executable buffer, call it.
# Requires: clang

CC = gcc
CFLAGS = -O2 -fomit-frame-pointer -fcf-protection=none

.PHONY: all test clean

all: copyexec

copyexec: copyexec.c
	$(CC) $(CFLAGS) -o $@ $<

test: copyexec
	@./copyexec

clean:
	rm -f copyexec
