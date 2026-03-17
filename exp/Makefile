EXPERIMENTS = 025-loadvariants64 \
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
              047-syswords64 \
              048-suffix64 \
              049-hidepvt64 \
              050-cstack64 \
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
064-segv \
065-needed \
066-doargv \
067-help \
068-dynlink \
              070-times-repeat \
              071-hidepvt-compact \
              072-features-words \
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
              095-locals-and-test \
              099-see64-improvements \
              102-s2d-fix \
              113-asm-reduction \
              134-native-getenv \
              135-loop-cond-audit \
              139-eval-fileload \
              140-tib-eob \
              141-rm-loadfile \
              142-cs0-getenv \
              145-shared-mmap \
              149-fflin-unify \
              046-callvec64 \
              051-repl-autoexec \
              052-repl-forth \
              143-openlib-port \
              144-native-libc \
              153-openlib

# Known-broken experiments — listed so we know they exist.
# Fix and move back to EXPERIMENTS when passing.
SKIP = 073-turnkey

test:
	@fail=0; for d in $(EXPERIMENTS); do \
		printf "%-30s" "$$d"; \
		if $(MAKE) --no-print-directory -s -C $$d test >/dev/null 2>&1; then \
			echo "PASSED"; \
		else \
			echo "FAILED"; fail=$$((fail+1)); \
		fi; \
	done; \
	for d in $(SKIP); do \
		printf "%-30s%s\n" "$$d" "SKIPPED"; \
	done; \
	$(MAKE) --no-print-directory -s clean 2>/dev/null; \
	if [ $$fail -ne 0 ]; then \
		echo "*** $$fail experiment(s) FAILED ***"; exit 1; \
	fi

clean:
	@for d in $(EXPERIMENTS) $(SKIP); do \
		$(MAKE) --no-print-directory -s -C $$d clean >/dev/null 2>&1 || true; \
	done

.PHONY: test clean
