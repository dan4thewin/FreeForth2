FF64 = ../../ff64
BOOT = ../../ff64.boot

.PHONY: test
test: test-openr test-read test-close test-nonexist

# Create a test file for reading
testfile:
	@echo "hello world" > testfile

test-openr: testfile
	@echo "--- $@ ---"
	@result=$$(echo ': t "testfile" openr . cr ; t' | $(FF64) -f $(BOOT) 2>&1 | grep -o '[0-9]*' | head -1); \
	  if [ "$$result" -gt 0 ] 2>/dev/null; then echo "  PASS: $@"; \
	  else echo "  FAIL: $@ (expected positive fd, got $$result)"; exit 1; fi

test-read: testfile
	@echo "--- $@ ---"
	@result=$$(echo ': t "testfile" openr tib 12 rot read tib swap type ; t' | $(FF64) -f $(BOOT) 2>&1 | grep -o 'hello world'); \
	  if [ "$$result" = "hello world" ]; then echo "  PASS: $@"; \
	  else echo "  FAIL: $@ (expected 'hello world', got '$$result')"; exit 1; fi

test-close: testfile
	@echo "--- $@ ---"
	@result=$$(echo ': t "testfile" openr close .l cr ; t' | $(FF64) -f $(BOOT) 2>&1 | grep -o '[0-9a-f]*' | tail -1); \
	  if [ "$$result" = "00000000" ]; then echo "  PASS: $@"; \
	  else echo "  FAIL: $@ (expected 00000000, got $$result)"; exit 1; fi

test-nonexist:
	@echo "--- $@ ---"
	@result=$$(echo ': t "nonexistent_file_xyz" openr .l cr ; t' | $(FF64) -f $(BOOT) 2>&1 | grep -o '[0-9a-f]*' | tail -1); \
	  if [ "$$result" = "fffffffe" ]; then echo "  PASS: $@"; \
	  else echo "  FAIL: $@ (expected fffffffe (-2=ENOENT), got $$result)"; exit 1; fi

clean:
	@rm -f testfile
