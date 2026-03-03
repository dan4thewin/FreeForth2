SHELL=/bin/bash

test: ../../ff64
	@source ../test.sh; \
	start "Exp 041: Vectors, d@/d!/d, and tick"; \
	run "d, advances 4" \
		': test here $$DEADBEEF d, here swap - . cr ; test ;' '4'; \
	run "d@ sign-extends" \
		': test here $$80000001 d, here 4 - d@ . cr ; test ;' '-2147483647'; \
	run "d@ positive" \
		': test here $$7FFFFFFF d, here 4 - d@ . cr ; test ;' '2147483647'; \
	run "d! stores 32-bit" \
		': test here 0 d, $$42 here 4 - d! here 4 - d@ . cr ; test ;' '66'; \
	run "vector calls body" \
		$$':^ v : body 42 . cr ;\nv ;' '42'; \
	run "vector body expr" \
		$$':^ v : body 10 20 + . cr ;\nv ;' '30'; \
	run "vector preamble byte" \
		$$':^ v ;\nv H@ @ c@ .x cr ;' '68'; \
	run "vector target is xt+6" \
		$$':^ v ;\nv H@ @ dup 1+ d@ swap 6 + - . cr ;' '0'; \
	run "vector ret byte" \
		$$':^ v ;\nv H@ @ 4+ 1+ c@ .x cr ;' 'c3'; \
	run "tick in colon def" \
		$$': foo 42 ;\n: test foo \x27 drop 99 . cr ; test ;' '99'; \
	run "redirect with !^" \
		$$':^ g : body 42 . cr ;\n: nb 99 . cr ;\n: rd nb \x27 g !^ ; rd ;\ng ;' '99'; \
	run "@^ reads target" \
		$$':^ g : body 42 . cr ;\n: test g @^ g \x27 6 + - . cr ; test ;' '0'; \
	run "n^ nops vector" \
		$$':^ g : body 42 . cr ;\n: nb 99 . cr ;\n: rd nb \x27 g !^ ; rd ;\n: rst g n^ ; rst ;\ng ."done" cr ;' 'done'; \
	run "x^ calls original body" \
		$$':^ g : body 42 . cr ;\n: nb 99 . cr ;\n: rd nb \x27 g !^ ; rd ;\n: test g x^ ; test ;' '42'; \
	finish
