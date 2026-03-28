# exp-c Makefile — run all experiments
#
# Usage: make test

EXPERIMENTS = $(sort $(wildcard 0*))

.PHONY: all test clean

test:
	@passed=0; failed=0; total=0; \
	for d in $(EXPERIMENTS); do \
		if [ -f $$d/Makefile ]; then \
			total=$$((total + 1)); \
			printf "%-30s " "$$d..."; \
			if $(MAKE) -C $$d test > /tmp/exp-c-$$d.log 2>&1; then \
				echo "PASSED"; \
				passed=$$((passed + 1)); \
			else \
				echo "FAILED (see /tmp/exp-c-$$d.log)"; \
				failed=$$((failed + 1)); \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "$$passed/$$total passed, $$failed failed"

clean:
	@for d in $(EXPERIMENTS); do \
		[ -f $$d/Makefile ] && $(MAKE) -C $$d clean; \
	done
