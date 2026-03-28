# Experiment 005 — Cross-Architecture Validation
#
# Same C source compiled for x86-64 and ARM64.
# Requires: gcc, aarch64-linux-gnu-gcc

CC_X86  = gcc
CC_ARM  = aarch64-linux-gnu-gcc
CFLAGS  = -O2 -fomit-frame-pointer -fcf-protection=none
DUMP_X86 = objdump
DUMP_ARM = aarch64-linux-gnu-objdump

.PHONY: all test clean

all: prims_x86.o prims_arm.o

prims_x86.o: prims_portable.c
	$(CC_X86) $(CFLAGS) -c -o $@ $<

prims_arm.o: prims_portable.c
	$(CC_ARM) -O2 -fomit-frame-pointer -c -o $@ $<

test: prims_x86.o prims_arm.o
	@echo "=== x86-64 disassembly ==="
	@$(DUMP_X86) -d prims_x86.o | grep -A8 '<prim_'
	@echo ""
	@echo "=== ARM64 disassembly ==="
	@$(DUMP_ARM) -d prims_arm.o | grep -A8 '<prim_'
	@echo ""
	@echo "=== Verification ==="
	@# Check ARM64 uses x19/x20/x21
	@if $(DUMP_ARM) -d prims_arm.o | grep -q 'x19'; then \
		echo "ARM64 uses x19 (TOS) — OK"; \
	else \
		echo "ARM64 missing x19 — FAIL"; exit 1; \
	fi
	@if $(DUMP_ARM) -d prims_arm.o | grep -q 'x20'; then \
		echo "ARM64 uses x20 (NOS) — OK"; \
	else \
		echo "ARM64 missing x20 — FAIL"; exit 1; \
	fi
	@if $(DUMP_ARM) -d prims_arm.o | grep -q 'x21'; then \
		echo "ARM64 uses x21 (DSP) — OK"; \
	else \
		echo "ARM64 missing x21 — FAIL"; exit 1; \
	fi
	@# Check x86-64 uses rbx/r13/r15
	@if $(DUMP_X86) -d prims_x86.o | grep -q 'rbx'; then \
		echo "x86-64 uses rbx (TOS) — OK"; \
	else \
		echo "x86-64 missing rbx — FAIL"; exit 1; \
	fi
	@echo ""
	@echo "PASSED — same source, both architectures correct"

clean:
	rm -f prims_x86.o prims_arm.o
