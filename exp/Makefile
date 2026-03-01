EXPERIMENTS = 023-forthmacros64 \
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
              041-vectors64 \
              042-tailcall64 \
              043-shifts64 \
              044-startloop64 \
              045-markvar64 \
              046-callvec64 \
              047-syswords64 \
              048-suffix64 \
              049-hidepvt64 \
              050-cstack64 \
              051-repl-autoexec \
              052-repl-forth \
              053-boot64 \
054-dots64 \
055-strcmp64 \
056-condcomp \
057-dotcond \
058-picnum \
059-misc \
060-rtimes-dump \
061-peephole \
062-fileio \
063-loadfile \
064-segv \
065-needed \
066-doargv \
067-help \
068-dynlink \
              070-times-repeat \
              071-hidepvt-compact \
              072-features-words \
              073-turnkey \
              074-fflin64-boot \
              078-ffpath \
              079-fixup \
              080-lib64 \
              081-numlit \
              082-restore-lits \
              086-shrink \
              087-features \
              088-segv-fix \
              089-anon-flush \
              090-remove-fast-paths \
              091-remove-inline-words \
              092-remove-comparisons \
              093-remove-dead-runtime \
              095-locals-and-test

test:
	@fail=0; for d in $(EXPERIMENTS); do \
		$(MAKE) -s -C $$d test 2>&1 || fail=$$((fail+1)); \
	done; \
	if [ $$fail -ne 0 ]; then \
		echo "*** $$fail experiment(s) FAILED ***"; exit 1; \
	fi

clean:
	@for d in $(EXPERIMENTS); do \
		$(MAKE) -s -C $$d clean 2>&1; \
	done

.PHONY: test clean
