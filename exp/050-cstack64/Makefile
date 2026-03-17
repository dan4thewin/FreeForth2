FF = ../../ff64-
TMP = /tmp/ff-050.ff
.PHONY: test
test:
	@PASS=0; FAIL=0; \
	echo "=== 050: Compile-time stack (cstack) ==="; \
	run() { printf '%s\n' "$$1" > $(TMP); $(FF) $(TMP) 2>/dev/null | head -1; }; \
	chk() { \
	  R=$$(run "$$1"); \
	  if [ "$$R" = "$$2" ]; then \
	    echo "  PASS: $$3"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$3 (expected '$$2', got '$$R')"; FAIL=$$((FAIL+1)); fi; \
	}; \
	echo "  --- cstack basics ---"; \
	chk '1 >cs cs> . cr ;' '1 ' 'cs push/pop round-trip'; \
	chk '1 2 3 >cs >cs >cs cs> . cs> . cs> . cr ;' '1 2 3 ' 'cs round-trip 3 items'; \
	chk '1 >cs 2 >cs 3 >cs cs> . cs> . cs> . cr ;' '3 2 1 ' 'cs LIFO order'; \
	echo "  --- BEGIN/BREAK with loops ---"; \
	chk ': t 5 BEGIN 1- 0- 0= IF BREAK AGAIN ; t . cr ;' '0 ' 'BEGIN/BREAK/AGAIN countdown'; \
	chk ': t 0 BEGIN 1+ dup 5 - 0- 0= drop IF BREAK AGAIN ; t . cr ;' '5 ' 'BEGIN/BREAK/AGAIN countup'; \
	chk ': t 10 BEGIN 1- dup 7 - 0- 0= drop IF BREAK 0- 0= IF BREAK AGAIN ; t . cr ;' '7 ' 'double BREAK'; \
	chk ': t 10 START 1- 0- 0= TILL ; t 42 . cr ;' '42 ' 'START/TILL exit'; \
	echo "  --- BEGIN/WHILE/REPEAT ---"; \
	chk ': t 0 BEGIN 1+ dup 5 - 0- 0<> drop WHILE REPEAT . cr ; t ;' '5 ' 'BEGIN/WHILE/REPEAT'; \
	chk ': t 0 BEGIN 1+ dup 5 - 0- 0= drop UNTIL . cr ; t ;' '5 ' 'BEGIN/UNTIL'; \
	echo "  --- TIMES/REPEAT ---"; \
	chk ': t 0 5 TIMES 1+ REPEAT . cr ; t ;' '5 ' 'TIMES/REPEAT 5x'; \
	echo "  --- depth clean after boot ---"; \
	chk 'depth . cr ;' '0 ' 'depth is 0 after boot'; \
	echo "  --- nested loops ---"; \
	chk ': t 0 BEGIN 0 BEGIN 1+ dup 3 - 0- 0= drop IF BREAK AGAIN + dup 9 - 0- 0= drop IF BREAK AGAIN ; t . cr ;' '9 ' 'nested BEGIN/AGAIN'; \
	echo "  --- ui vector ---"; \
	chk 'ui ;' ' 0;  0; ' 'ui calls prompt'; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0

clean:
	@rm -f $(TMP)
