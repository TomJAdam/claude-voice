#!/bin/bash
# Tests for scripts/claude-voice-save.sh
# Tests the text preprocessing pipeline and transcript extraction.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_DIR/scripts/claude-voice-save.sh"
FIXTURE="$REPO_DIR/tests/fixtures/mock-transcript.jsonl"
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1 — $2"; }

# Helper: run the save script's preprocessing pipeline on raw text
# (bypasses transcript extraction, tests just the sed chain)
preprocess() {
  echo "$1" | sed \
    -e 's/\[HIGH\]/High,/g' \
    -e 's/\[MEDIUM\]/Medium,/g' \
    -e 's/\[LOW\]/Low,/g' \
    -e 's/__c//g' \
    -e 's/__/  /g' \
    -e 's/<[^>]*>//g' \
    -e 's/@//g' \
    -e 's/`//g' \
    -e 's/—/, /g' \
    -e 's/\([a-z]\)\([A-Z]\)/\1 \2/g' \
    -e 's/\([a-z]\)\([A-Z]\)/\1 \2/g' \
    -e 's/\([A-Z][A-Z]\)\([A-Z][a-z]\)/\1 \2/g' \
    -e 's/_/ /g'
}

# --- Test: camelCase splitting ---
RESULT=$(preprocess "getUserName")
if [ "$RESULT" = "get User Name" ]; then
  pass "camelCase splitting (getUserName)"
else
  fail "camelCase" "got: '$RESULT'"
fi

# --- Test: Acronym boundary ---
RESULT=$(preprocess "getHTTPResponse")
if [ "$RESULT" = "get HTTP Response" ]; then
  pass "Acronym boundary (getHTTPResponse)"
else
  fail "Acronym boundary" "got: '$RESULT'"
fi

# --- Test: Salesforce __c removal ---
RESULT=$(preprocess "Account__c")
if [ "$RESULT" = "Account" ]; then
  pass "Salesforce __c removal"
else
  fail "Salesforce __c" "got: '$RESULT'"
fi

# --- Test: Double underscore to spaces ---
RESULT=$(preprocess "some__field")
if [ "$RESULT" = "some  field" ]; then
  pass "Double underscore to spaces"
else
  fail "Double underscore" "got: '$RESULT'"
fi

# --- Test: snake_case to spaces ---
RESULT=$(preprocess "Complete_Day_Off")
if [ "$RESULT" = "Complete Day Off" ]; then
  pass "snake_case to spaces"
else
  fail "snake_case" "got: '$RESULT'"
fi

# --- Test: HTML tag stripping ---
RESULT=$(preprocess "<code>hello</code>")
if [ "$RESULT" = "hello" ]; then
  pass "HTML tag stripping"
else
  fail "HTML strip" "got: '$RESULT'"
fi

# --- Test: Backtick removal ---
RESULT=$(preprocess 'the `foo` function')
if [ "$RESULT" = "the foo function" ]; then
  pass "Backtick removal"
else
  fail "Backtick" "got: '$RESULT'"
fi

# --- Test: Em-dash replacement ---
RESULT=$(preprocess "hello — world")
if [ "$RESULT" = "hello ,  world" ]; then
  pass "Em-dash replacement"
else
  fail "Em-dash" "got: '$RESULT'"
fi

# --- Test: @ symbol removal ---
RESULT=$(preprocess "email @user")
if [ "$RESULT" = "email user" ]; then
  pass "@ symbol removal"
else
  fail "@ removal" "got: '$RESULT'"
fi

# --- Test: Priority markers ---
RESULT=$(preprocess "[HIGH] issue")
if [ "$RESULT" = "High, issue" ]; then
  pass "Priority marker [HIGH]"
else
  fail "Priority HIGH" "got: '$RESULT'"
fi

RESULT=$(preprocess "[MEDIUM] issue")
if [ "$RESULT" = "Medium, issue" ]; then
  pass "Priority marker [MEDIUM]"
else
  fail "Priority MEDIUM" "got: '$RESULT'"
fi

# --- Test: Transcript extraction (full pipeline) ---
# Set up a fake session with the mock transcript
FAKE_HOME="$TMPDIR_BASE/home_$$"
FAKE_SESSION="test-session-$$"
FAKE_PROJECT="$FAKE_HOME/.claude/projects/test"
mkdir -p "$FAKE_PROJECT"
cp "$FIXTURE" "$FAKE_PROJECT/${FAKE_SESSION}.jsonl"
export HOME="$FAKE_HOME"

# Run the save script with the fake session ID
echo "{\"session_id\":\"$FAKE_SESSION\"}" | bash "$SCRIPT"

if [ -f /tmp/claude-say-last.txt ]; then
  CONTENT=$(cat /tmp/claude-say-last.txt)
  # Should contain the LAST assistant message, preprocessed
  if echo "$CONTENT" | grep -q "get User Name"; then
    pass "Extracts last assistant message with preprocessing"
  else
    fail "Transcript extraction" "content: '$CONTENT'"
  fi
  # Should NOT contain the first assistant message
  if ! echo "$CONTENT" | grep -q "first response"; then
    pass "Only extracts last assistant message (not earlier ones)"
  else
    fail "Last-only extraction" "found first response in output"
  fi
  # Should have Salesforce __c removed
  if ! echo "$CONTENT" | grep -q "__c"; then
    pass "Transcript: Salesforce __c stripped"
  else
    fail "Transcript __c" "found __c in output"
  fi
else
  fail "Transcript extraction" "no output file created"
  fail "Last-only extraction" "skipped (no file)"
  fail "Transcript __c" "skipped (no file)"
fi

# --- Test: Atomic write (tmp file not left behind) ---
if [ ! -f /tmp/claude-say-last.txt.tmp ]; then
  pass "Atomic write: no .tmp file left behind"
else
  fail "Atomic write" ".tmp file still exists"
fi

# --- Test: Missing session ID exits cleanly ---
RESULT=$(echo '{}' | bash "$SCRIPT" 2>&1; echo "EXIT:$?")
if echo "$RESULT" | grep -q "EXIT:0"; then
  pass "Missing session ID exits cleanly"
else
  fail "Missing session" "non-zero exit"
fi

# --- Test: Missing transcript exits cleanly ---
RESULT=$(echo '{"session_id":"nonexistent-id"}' | bash "$SCRIPT" 2>&1; echo "EXIT:$?")
if echo "$RESULT" | grep -q "EXIT:0"; then
  pass "Missing transcript exits cleanly"
else
  fail "Missing transcript" "non-zero exit"
fi
