SHELL=/bin/bash
FF = ../../ff64-

test: ../../ff64-
	@source ../test.sh && start "043: Shifts, parser, system words" && \
	run "shl-basic" '1 3 << . cr ;' '8' && \
	run "shr-basic" '200 3 >> . cr ;' '25' && \
	run "shl-one" '5 1 << . cr ;' '10' && \
	run "shr-hex" '$$FF00FF00 8 >> .x cr ;' 'ff00ff' && \
	run "shl-swap" '3 1 swap << . cr ;' '8' && \
	run "shr-swap" '3 200 swap >> . cr ;' '25' && \
	run "shl-64bit" '1 32 << .x cr ;' '100000000' && \
	run "shl-named" ': s3 3 << ; 7 s3 . cr ;' '56' && \
	run "shr-named" ': h8 8 >> ; $$ABCD00 h8 .x cr ;' 'abcd' && \
	run "shl-zero" '42 0 << . cr ;' '42' && \
	run "comment-paren" 'variable x 42 x ! x \( fetch x \) @ . cr ;' '42' && \
	run "lnparse-eol" 'lnparse . cr ;' '0' && \
	run "in-addr" '>in @ 0- 0<> drop IF 1 THEN . cr ;' '1' && \
	run "exit-code" '0 exit ;' '' && \
	run "bye-exits" 'bye ;' '' && \
	run "eof-skips" '42 . EOF this_ignored cr ;' '42' && \
	finish

.PHONY: test
