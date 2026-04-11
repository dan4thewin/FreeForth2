DIR := $(dir $(lastword $(MAKEFILE_LIST)))

CC := gcc
CFLAGS := -O2 -Wall -Wextra -Wno-unused-parameter

.PHONY: test clean

test: $(DIR)minicompiler
	$(DIR)minicompiler

$(DIR)minicompiler: $(DIR)minicompiler.c $(wildcard $(DIR)overrides_*.h)
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(DIR)minicompiler
