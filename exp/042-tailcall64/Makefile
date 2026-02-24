SHELL=/bin/bash
FF = ../../ff64 -f ../../ff64.boot

test: ../../ff64 ## Run all tests
	@source ../test.sh && start "042: Tail-call optimization" && \
	run "jmp-named" ': foo 42 . cr ; : bar foo ; bar ;' '42' && \
	run "jmp-opcode" ': foo 42 . ; : bar foo ; bar H@ @ c@ .x cr ;' 'e9' && \
	run "ret-anon" ': foo 42 . cr ; foo ;' '42' && \
	run "reverse-works" ': hi 72 emit 73 emit ; : t reverse hi cr ; t ;' 'HI' && \
	run "chain-tailcall" ': a 65 emit ; : b a ; : c b ; c cr ;' 'A' && \
	run "no-opt-empty" ': e ; e H@ @ c@ .x cr ;' 'c3' && \
	run "opt-preserves-func" ': f1 10 . ; : f2 20 . ; : g f1 f2 ; g cr ;' '10 20' && \
	finish

.PHONY: test
