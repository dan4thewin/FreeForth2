ROOT = ../..
FF = cd $(ROOT) && timeout 5 ./ff64

.PHONY: test clean
test: test-needs-simple test-needs-nested test-needs-guard test-eval-basic test-loadfile-removed
	@echo "  All 141-rm-loadfile tests passed."

# needs loads a simple file
test-needs-simple:
	@echo '--- $@ ---'
	@echo ': simple-w 42 ;' > /tmp/141-simple.ff
	@printf 'needs /tmp/141-simple.ff\nsimple-w . cr\n0 exit ;\n' > /tmp/141-test1.ff
	@$(FF) ': prompt ;' -f /tmp/141-test1.ff 2>&1 | grep -q '^ *42 *$$' && \
	  echo '  PASS: $@' || { echo '  FAIL: $@'; exit 1; }

# needs with nested needs (inner file uses needs)
test-needs-nested:
	@echo '--- $@ ---'
	@echo ': dep-w 77 ;' > /tmp/141-dep.ff
	@printf 'needs /tmp/141-dep.ff\n: nest-w dep-w 10 + ;\n' > /tmp/141-nest.ff
	@printf 'needs /tmp/141-nest.ff\nnest-w . cr\n0 exit ;\n' > /tmp/141-test2.ff
	@$(FF) ': prompt ;' -f /tmp/141-test2.ff 2>&1 | grep -q '^ *87 *$$' && \
	  echo '  PASS: $@' || { echo '  FAIL: $@'; exit 1; }

# needs guard: second load is a no-op
test-needs-guard:
	@echo '--- $@ ---'
	@echo ': guard-w 55 ;' > /tmp/141-guard.ff
	@printf 'needs /tmp/141-guard.ff\nneeds /tmp/141-guard.ff\nguard-w . cr\n0 exit ;\n' > /tmp/141-test3.ff
	@$(FF) ': prompt ;' -f /tmp/141-test3.ff 2>&1 | grep -q '^ *55 *$$' && \
	  echo '  PASS: $@' || { echo '  FAIL: $@'; exit 1; }

# eval works for inline source
test-eval-basic:
	@echo '--- $@ ---'
	@printf '": eval-w 99 ;" eval ;\neval-w . cr\n0 exit ;\n' > /tmp/141-test4.ff
	@$(FF) ': prompt ;' -f /tmp/141-test4.ff 2>&1 | grep -q '^ *99 *$$' && \
	  echo '  PASS: $@' || { echo '  FAIL: $@'; exit 1; }

# loadfile no longer exists
test-loadfile-removed:
	@echo '--- $@ ---'
	@printf '"x" loadfile\n' > /tmp/141-test5.ff
	@$(FF) ': prompt ;' -f /tmp/141-test5.ff 2>&1 | grep -q 'error\|???' && \
	  echo '  PASS: $@' || { echo '  FAIL: $@'; exit 1; }

clean:
	@rm -f /tmp/141-*.ff
