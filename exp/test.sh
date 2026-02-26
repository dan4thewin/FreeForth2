#!/bin/bash
# Test helper for FreeForth2 experiments
# Usage: source ../test.sh
#   start "Exp NNN: Title"
#   run "test name" 'forth code' 'expected grep pattern'
#   finish

FF=${FF:-../../ff64}
PASS=0
FAIL=0

start() {
    echo "=== $1 ==="
    PASS=0
    FAIL=0
}

run() {
    local name="$1" code="$2" expected="$3"
    local result
    result=$(printf '%s\n' "$code" | $FF 2>/dev/null)
    if echo "$result" | grep -qF -- "$expected"; then
        echo "  PASS: $name"
        PASS=$((PASS+1))
    else
        echo "  FAIL: $name"
        echo "    Expected: $expected"
        echo "    Got: $result"
        FAIL=$((FAIL+1))
    fi
}

finish() {
    echo "  ----"
    echo "  $PASS passed, $FAIL failed"
}
