EXPERIMENTS = 001-hello64 002-stack64 003-codegen64 004-subrthread64 \
              005-regswap64 006-headers64 007-minicompiler64 \
              008-interactive64 009-nameddef64 010-flowcontrol64 \
              011-memory64 012-variables64 013-fileio64 \
              014-retstack64 015-swapbit64 016-inline64 \
              017-swapbit-deep 018-moreinline64 019-cmpinline64 020-flagscond64 \
              021-litcomma64 022-backtick64 023-forthmacros64 \
              024-moremacros64 025-loadvariants64 \
              026-lit64 027-compilemacros64 \
              028-stackdivmod64 \
              029-placeshifts64 \
              030-extarith64 \
              031-utility64 \
              032-flowmacros64 \
              033-dictops64 \
              034-execalias64 \
              035-numout64 \
              036-flowforth64 \
              037-countedloops64 \
              038-utilwords64 \
              039-debugout64 \
              040-charliteral64 \
              041-vectors64

test:
	@for d in $(EXPERIMENTS); do \
		$(MAKE) -s -C $$d test 2>&1; \
	done

clean:
	@for d in $(EXPERIMENTS); do \
		$(MAKE) -s -C $$d clean 2>&1; \
	done

.PHONY: test clean
