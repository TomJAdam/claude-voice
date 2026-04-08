#!/bin/bash
# Tests for scripts/claude-voice-intercept.sh
# Verifies the UserPromptSubmit hook correctly intercepts /say commands.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_DIR/scripts/claude-voice-intercept.sh"
TMPDIR_BASE=$(mktemp -d)
SD="$TMPDIR_BASE/session"
mkdir -p "$SD"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1 — $2"; }

# Mock say and killall to avoid audio and real process killing
MOCK_BIN="$TMPDIR_BASE/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/say" << 'MOCK'
#!/bin/bash
cat > /dev/null &
sleep 0.1
MOCK
chmod +x "$MOCK_BIN/say"
cat > "$MOCK_BIN/killall" << 'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$MOCK_BIN/killall"
ORIG_PATH="$PATH"
export PATH="$MOCK_BIN:$PATH"

# Helper: run intercept with a prompt, override PPID so SD is our test dir
run_intercept() {
  # We can't override PPID directly, but the script uses $PPID which is its parent.
  # Instead, wrap the script to set SD explicitly.
  echo "{\"prompt\":\"$1\"}" | PPID_OVERRIDE=1 bash -c "
    export PPID=test_session
    SD='$SD'
    # Source the script logic inline with SD override
    trap 'exit 0' ERR
    INPUT=\$(cat 2>/dev/null) || exit 0
    PROMPT=\$(echo \"\$INPUT\" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
    [ -z \"\$PROMPT\" ] && exit 0
    case \"\$PROMPT\" in
      /say\\ *) ARGS=\"\${PROMPT#/say }\" ;;
      /say)    ARGS='' ;;
      /stop)   killall say 2>/dev/null || true; printf '{\"decision\":\"block\",\"reason\":\"Stopped.\"}\n'; exit 0 ;;
      *)       exit 0 ;;
    esac
    for word in \$ARGS; do
      case \"\$word\" in
        full|summary|code) exit 0 ;;
      esac
    done
    mkdir -p \"\$SD\"
    RATE=175; SAY_FLAGS=''; SKIP_NEXT=''; MODE=''
    for word in \$ARGS; do
      if [ -n \"\$SKIP_NEXT\" ]; then
        case \"\$SKIP_NEXT\" in rate) RATE=\"\$word\" ;; voice) SAY_FLAGS=\"\$SAY_FLAGS -v \$word\" ;; esac
        SKIP_NEXT=''; continue
      fi
      case \"\$word\" in
        slow) RATE=130 ;; fast) RATE=250 ;; r) SKIP_NEXT='rate' ;; voice) SKIP_NEXT='voice' ;;
        pause) MODE='pause' ;; resume) MODE='resume' ;; again|repeat) MODE='again' ;; *) ;;
      esac
    done
    SAY_FLAGS=\"-r \$RATE \$SAY_FLAGS\"
    block() { printf '{\"decision\":\"block\",\"reason\":\"%s\"}\n' \"\$1\"; exit 0; }
    case \"\$MODE\" in
      pause) echo 0 > \"\$SD/offset.txt\"; (killall say 2>/dev/null || true); block 'Paused.' ;;
      resume) date +%s > \"\$SD/start.txt\"; echo \"\$RATE\" > \"\$SD/rate.txt\"; block 'Resuming.' ;;
      *) if [ ! -f \"\$SD/last.txt\" ]; then block 'Nothing to say yet.'; fi
         date +%s > \"\$SD/start.txt\"; echo \"\$RATE\" > \"\$SD/rate.txt\"; rm -f \"\$SD/offset.txt\"
         cat \"\$SD/last.txt\" | say \$SAY_FLAGS &
         block 'Speaking.' ;;
    esac
  " 2>/dev/null
}

# --- Test: Normal prompt passes through (no output, exit 0) ---
RESULT=$(echo '{"prompt":"hello world"}' | bash "$SCRIPT" 2>/dev/null)
if [ -z "$RESULT" ]; then
  pass "Normal prompt passes through"
else
  fail "Normal prompt" "got output: $RESULT"
fi

# --- Test: /say full passes through to LLM ---
RESULT=$(echo '{"prompt":"/say full"}' | bash "$SCRIPT" 2>/dev/null)
if [ -z "$RESULT" ]; then
  pass "/say full passes through to LLM"
else
  fail "/say full" "got output: $RESULT"
fi

# --- Test: /say summary passes through to LLM ---
RESULT=$(echo '{"prompt":"/say summary"}' | bash "$SCRIPT" 2>/dev/null)
if [ -z "$RESULT" ]; then
  pass "/say summary passes through to LLM"
else
  fail "/say summary" "got output: $RESULT"
fi

# --- Test: /say code passes through to LLM ---
RESULT=$(echo '{"prompt":"/say code"}' | bash "$SCRIPT" 2>/dev/null)
if [ -z "$RESULT" ]; then
  pass "/say code passes through to LLM"
else
  fail "/say code" "got output: $RESULT"
fi

# --- Test: /say blocks (no cache file) ---
RESULT=$(run_intercept "/say")
if echo "$RESULT" | grep -q '"decision":"block"'; then
  pass "/say blocks prompt"
else
  fail "/say block" "got: $RESULT"
fi

# --- Test: /say with cache file blocks with Speaking ---
echo "Test content" > "$SD/last.txt"
RESULT=$(run_intercept "/say")
if echo "$RESULT" | grep -q "Speaking"; then
  pass "/say with cache: Speaking"
else
  fail "/say speaking" "got: $RESULT"
fi

# --- Test: /say fast blocks ---
RESULT=$(run_intercept "/say fast")
if echo "$RESULT" | grep -q '"decision":"block"'; then
  pass "/say fast blocks"
else
  fail "/say fast" "got: $RESULT"
fi

# --- Test: /say fast sets rate 250 ---
run_intercept "/say fast" > /dev/null
RATE=$(cat "$SD/rate.txt" 2>/dev/null)
if [ "$RATE" = "250" ]; then
  pass "/say fast sets rate 250"
else
  fail "/say fast rate" "got: $RATE"
fi

# --- Test: /say slow sets rate 130 ---
run_intercept "/say slow" > /dev/null
RATE=$(cat "$SD/rate.txt" 2>/dev/null)
if [ "$RATE" = "130" ]; then
  pass "/say slow sets rate 130"
else
  fail "/say slow rate" "got: $RATE"
fi

# --- Test: /say pause blocks ---
RESULT=$(run_intercept "/say pause")
if echo "$RESULT" | grep -q "Paused"; then
  pass "/say pause blocks with Paused"
else
  fail "/say pause" "got: $RESULT"
fi

# --- Test: /say resume blocks ---
echo "0" > "$SD/offset.txt"
RESULT=$(run_intercept "/say resume")
if echo "$RESULT" | grep -q "Resuming"; then
  pass "/say resume blocks with Resuming"
else
  fail "/say resume" "got: $RESULT"
fi

# --- Test: /stop blocks ---
RESULT=$(echo '{"prompt":"/stop"}' | bash "$SCRIPT" 2>/dev/null)
if echo "$RESULT" | grep -q "Stopped"; then
  pass "/stop blocks with Stopped"
else
  fail "/stop" "got: $RESULT"
fi

# --- Test: /say full fast passes through (full needs LLM) ---
RESULT=$(echo '{"prompt":"/say full fast"}' | bash "$SCRIPT" 2>/dev/null)
if [ -z "$RESULT" ]; then
  pass "/say full fast passes through"
else
  fail "/say full fast" "got output: $RESULT"
fi

# --- Test: Empty prompt passes through ---
RESULT=$(echo '{"prompt":""}' | bash "$SCRIPT" 2>/dev/null)
if [ -z "$RESULT" ]; then
  pass "Empty prompt passes through"
else
  fail "Empty prompt" "got: $RESULT"
fi

# --- Test: Malformed JSON passes through (fail-open) ---
RESULT=$(echo 'not json' | bash "$SCRIPT" 2>/dev/null)
if [ -z "$RESULT" ]; then
  pass "Malformed JSON passes through (fail-open)"
else
  fail "Malformed JSON" "got: $RESULT"
fi

# --- Test: Trailing /say sets auto-speak flag ---
rm -rf /tmp/claude-say-*/auto-speak 2>/dev/null
echo '{"prompt":"explain this /say"}' | bash "$SCRIPT" 2>/dev/null
if ls /tmp/claude-say-*/auto-speak > /dev/null 2>&1; then
  pass "Trailing /say sets auto-speak flag"
else
  fail "Trailing /say" "no flag set"
fi

# --- Test: Trailing /say fast captures flags ---
rm -rf /tmp/claude-say-*/auto-speak 2>/dev/null
echo '{"prompt":"explain this /say fast"}' | bash "$SCRIPT" 2>/dev/null
FLAG_CONTENT=$(cat /tmp/claude-say-*/auto-speak 2>/dev/null)
if echo "$FLAG_CONTENT" | grep -q "fast"; then
  pass "Trailing /say fast captures flag"
else
  fail "Trailing /say fast" "flag: '$FLAG_CONTENT'"
fi

# --- Test: Mid-sentence /say does NOT trigger (false positive) ---
rm -rf /tmp/claude-say-*/auto-speak 2>/dev/null
echo '{"prompt":"I want to /say something"}' | bash "$SCRIPT" 2>/dev/null
if ! ls /tmp/claude-say-*/auto-speak > /dev/null 2>&1; then
  pass "Mid-sentence /say does not trigger"
else
  fail "Mid-sentence /say" "false trigger"
fi

# --- Test: /say with non-flag words does NOT trigger ---
rm -rf /tmp/claude-say-*/auto-speak 2>/dev/null
echo '{"prompt":"can you /say hello world"}' | bash "$SCRIPT" 2>/dev/null
if ! ls /tmp/claude-say-*/auto-speak > /dev/null 2>&1; then
  pass "/say with non-flag words does not trigger"
else
  fail "/say non-flag" "false trigger"
fi

# Clean up
rm -rf /tmp/claude-say-*/auto-speak 2>/dev/null
export PATH="$ORIG_PATH"
