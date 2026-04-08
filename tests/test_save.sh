#!/bin/bash
# Tests for scripts/claude-voice-save.sh
# Tests the text preprocessing pipeline and transcript extraction.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_DIR/scripts/claude-voice-save.sh"
FIXTURE="$REPO_DIR/tests/fixtures/mock-transcript.jsonl"
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE" "/tmp/claude-say-$$"' EXIT

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
    -e 's/\([A-Za-z_]\)<\([A-Za-z_][^>]*\)>/\1 of \2/g' \
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

# --- Test: Generic type to "of" ---
RESULT=$(preprocess "List<String>")
if [ "$RESULT" = "List of String" ]; then
  pass "Generic type (List<String>)"
else
  fail "Generic type" "got: '$RESULT'"
fi

# --- Test: Generic type with Salesforce field ---
RESULT=$(preprocess "List<Complete_Day_Off__c>")
if [ "$RESULT" = "List of Complete Day Off" ]; then
  pass "Generic type with Salesforce (List<Complete_Day_Off__c>)"
else
  fail "Generic Salesforce" "got: '$RESULT'"
fi

# --- Test: HTML tag stripping (still works) ---
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

# --- Test: Extracts last_assistant_message with preprocessing ---
SAVE_DIR="/tmp/claude-say-$$"
TEST_MSG="The getUserName function retrieves the Account__c field from <code>SalesforceAPI</code>. It uses camelCase naming — specifically getHTTPResponse — and returns the Complete_Day_Off__c value."
echo "{\"last_assistant_message\":\"$TEST_MSG\"}" | bash "$SCRIPT"

if [ -f "$SAVE_DIR/last.txt" ]; then
  CONTENT=$(cat "$SAVE_DIR/last.txt")
  if echo "$CONTENT" | grep -q "get User Name"; then
    pass "Extracts last_assistant_message with preprocessing"
  else
    fail "Message extraction" "content: '$CONTENT'"
  fi
  # Should have Salesforce __c removed
  if ! echo "$CONTENT" | grep -q "__c"; then
    pass "Salesforce __c stripped from message"
  else
    fail "Message __c" "found __c in output"
  fi
  # Should have HTML stripped
  if ! echo "$CONTENT" | grep -q "<code>"; then
    pass "HTML stripped from message"
  else
    fail "Message HTML" "found HTML in output"
  fi
else
  fail "Message extraction" "no output file created at $SAVE_DIR/last.txt"
  fail "Salesforce __c" "skipped (no file)"
  fail "HTML strip" "skipped (no file)"
fi

# --- Test: Atomic write (tmp file not left behind) ---
if [ ! -f "$SAVE_DIR/last.txt.tmp" ]; then
  pass "Atomic write: no .tmp file left behind"
else
  fail "Atomic write" ".tmp file still exists"
fi

# --- Test: Missing message exits cleanly ---
RESULT=$(echo '{}' | bash "$SCRIPT" 2>&1; echo "EXIT:$?")
if echo "$RESULT" | grep -q "EXIT:0"; then
  pass "Missing message exits cleanly"
else
  fail "Missing message" "non-zero exit"
fi

# --- Test: Empty input exits cleanly ---
RESULT=$(echo '' | bash "$SCRIPT" 2>&1; echo "EXIT:$?")
if echo "$RESULT" | grep -q "EXIT:0"; then
  pass "Empty input exits cleanly"
else
  fail "Empty input" "non-zero exit"
fi
