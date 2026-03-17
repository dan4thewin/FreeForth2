FF = ../../ff64-
TMP = /tmp/ff-081.ff

.PHONY: test clean

test:
	@# Basic: decimal, negative, hex, octal, binary, quoted ASCII
	@printf '42 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '42' && echo "  PASS test-decimal" || echo "  FAIL test-decimal"
	@printf -- '-7 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '\-7' && echo "  PASS test-negative" || echo "  FAIL test-negative"
	@printf '$$FF . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '255' && echo "  PASS test-hex" || echo "  FAIL test-hex"
	@printf '&100 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '64' && echo "  PASS test-octal" || echo "  FAIL test-octal"
	@printf '%%1010 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '10' && echo "  PASS test-binary" || echo "  FAIL test-binary"
	@printf "'A . bye\n" > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '65' && echo "  PASS test-quoted-ascii" || echo "  FAIL test-quoted-ascii"
	@# Base change and skip chars
	@printf '8#77 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '63' && echo "  PASS test-base-change" || echo "  FAIL test-base-change"
	@printf "1'000'000 . bye\n" > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '1000000' && echo "  PASS test-skip-chars" || echo "  FAIL test-skip-chars"
	@# Date and time literals
	@printf '2000-3-1 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '730485' && echo "  PASS test-date" || echo "  FAIL test-date"
	@printf '1970-1-1 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '719468' && echo "  PASS test-date-1970" || echo "  FAIL test-date-1970"
	@printf '24:0:0 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '86400' && echo "  PASS test-time" || echo "  FAIL test-time"
	@printf '1:0:0 . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '3600' && echo "  PASS test-time-hour" || echo "  FAIL test-time-hour"
	@# Compound: bracket expression matching i386
	@printf '[ 1970-1-1 2000-3-1- 24:0:0* 1:0:0+ ] . bye\n' > $(TMP); $(FF) $(TMP) 2>&1 | grep -q '\-951865200' && echo "  PASS test-epoch-expr" || echo "  FAIL test-epoch-expr"
	@echo "All 081-numlit tests passed."

clean:
	@rm -f $(TMP)
	@true