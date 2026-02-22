EXPERIMENTS = 001-hello64 002-stack64 003-codegen64 004-subrthread64 \
              005-regswap64 006-headers64 007-minicompiler64 \
              008-interactive64 009-nameddef64 010-flowcontrol64 \
              011-memory64 012-variables64 013-fileio64 \
              014-retstack64 015-swapbit64

test:
	@for d in $(EXPERIMENTS); do \
		$(MAKE) -s -C $$d test 2>&1; \
	done

clean:
	@for d in $(EXPERIMENTS); do \
		$(MAKE) -s -C $$d clean 2>&1; \
	done

.PHONY: test clean
