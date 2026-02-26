FF = ../../ff64
.PHONY: test
test:
	@PASS=0; FAIL=0; \
	echo "=== 048-suffix64 ==="; \
	run() { printf '%s\n' "$$1" | $(FF) 2>/dev/null | sed 's/^ *[0-9-]*; *//;s/ *[0-9-]*; *$$//' | head -1; }; \
	chk() { \
	  R=$$(run "$$1"); \
	  if [ "$$R" = "$$2" ]; then \
	    echo "  PASS: $$3"; PASS=$$((PASS+1)); \
	  else echo "  FAIL: $$3 (expected '$$2', got '$$R')"; FAIL=$$((FAIL+1)); fi; \
	}; \
	echo "  --- arithmetic suffixes ---"; \
	chk ': t 10 5+ . cr ; t ;' '15 ' '5+ add'; \
	chk ': t 10 3- . cr ; t ;' '7 ' '3- sub'; \
	chk ': t 6 7* . cr ; t ;' '42 ' '7* mul'; \
	chk ': t 20 4/ . cr ; t ;' '5 ' '4/ div'; \
	chk ': t 17 5% . cr ; t ;' '2 ' '5% %'; \
	echo "  --- bitwise suffixes ---"; \
	chk ': t $$FF $$0F& . cr ; t ;' '15 ' '$$0F& and'; \
	chk ': t $$F0 $$0F| . cr ; t ;' '255 ' '$$0F| or'; \
	chk ': t $$FF $$0F^ . cr ; t ;' '240 ' '$$0F^ xor'; \
	echo "  --- @ ! _ suffixes ---"; \
	chk 'variable x 42 x ! : t x@ . cr ; t ;' '42 ' 'x@ fetch'; \
	chk 'variable x : t 99 x! x @ . cr ; t ;' '99 ' 'x! store'; \
	chk ': t 42 99_ . cr ; t ;' '99 ' '99_ nip-replace'; \
	echo "  --- named constant suffixes ---"; \
	chk '10 constant N : t 5 N+ . cr ; t ;' '15 ' 'N+ named add'; \
	chk '3 constant M : t 17 M% . cr ; t ;' '2 ' 'M% named %'; \
	echo "  --- large immediates ---"; \
	chk ': t 1 $$1000+ . cr ; t ;' '4097 ' '$$1000+ large add'; \
	chk ': t 1000 256/ . cr ; t ;' '3 ' '256/ large div'; \
	echo "  ----"; \
	echo "  $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0
