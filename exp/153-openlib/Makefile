FF=../../ff64

.PHONY: test
test: test-default test-subdir test-full test-tilde test-ffpp-debug test-ffpp-passthru
	@echo PASSED

# Test 1: default FFPATH from repo root
test-default:
	@echo -n "test-default: "
	@cd ../.. && timeout 5 ./ff64 -f exp/153-openlib/test.ff

# Test 2: running from exp dir — # resolves via /proc/self/exe
test-subdir:
	@echo -n "test-subdir: "
	@timeout 5 ../../ff64 -f test.ff

# Test 3: full directory entries (no ?), exercises full/expand/exp#
test-full:
	@echo -n "test-full: "
	@cd ../.. && FFPATH='?:?.ff:#/lib/x86-64:#/lib' timeout 5 ./ff64 -f exp/153-openlib/test-full.ff

# Test 3: ~ sigil expansion, exercises exp~ in both partial and full entries
test-tilde:
	@echo -n "test-tilde: "
	@cd ../.. && HOME=$$(pwd) FFPATH='?:?.ff:~/lib/?.ff:~/lib' timeout 5 ./ff64 -f exp/153-openlib/test-tilde.ff

# Test 4: ffpp [DEBUG] conditional — --debug flag
test-ffpp-debug:
	@echo -n "test-ffpp-debug: "
	@echo '[DEBUG] [IF] DBGWORD [THEN] ALWAYS' | ../../ffpp --debug | grep -q 'DBGWORD ALWAYS'
	@echo '[DEBUG] [IF] DBGWORD [THEN] ALWAYS' | ../../ffpp | grep -q '^ALWAYS$$'
	@echo '[DEBUG] [IF] D [ELSE] R [THEN] C' | ../../ffpp --debug | grep -q 'D C'
	@echo '[DEBUG] [IF] D [ELSE] R [THEN] C' | ../../ffpp | grep -q 'R C'
	@echo "ok"

# Test 5: ffpp [~] passthru — outputs [~] block verbatim
test-ffpp-passthru:
	@echo -n "test-ffpp-passthru: "
	@echo '[~] [IF] body [THEN] after' | ../../ffpp | grep -q '^\[~\] \[IF\] body \[THEN\] after$$'
	@echo '[0] [IF] [~] [IF] hidden [THEN] [THEN] after' | ../../ffpp | grep -q '^after$$'
	@echo "ok"
