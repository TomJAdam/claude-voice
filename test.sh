#!/bin/bash
# Run all claude-voice tests
# Usage: bash test.sh

cd "$(dirname "$0")"
PASS=0
FAIL=0

for test_file in tests/test_*.sh; do
  echo "--- $test_file ---"
  OUTPUT=$(bash "$test_file" 2>&1)
  echo "$OUTPUT"
  PASS=$((PASS + $(echo "$OUTPUT" | grep -c "^  PASS:")))
  FAIL=$((FAIL + $(echo "$OUTPUT" | grep -c "^  FAIL:")))
  echo ""
done

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
