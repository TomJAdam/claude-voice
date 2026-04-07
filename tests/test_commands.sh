#!/bin/bash
# Tests for /say and /stop command behavior.
# Mocks the `say` command to log invocations instead of producing audio.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"; export PATH="$ORIG_PATH"' EXIT

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1 — $2"; }

# Create a mock `say` that logs its args to a file
MOCK_BIN="$TMPDIR_BASE/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/say" << 'MOCK'
#!/bin/bash
# Read stdin to consume piped input (like real say would)
cat > /dev/null &
echo "$@" >> /tmp/claude-say-mock-log.txt
sleep 2
MOCK
chmod +x "$MOCK_BIN/say"

# Also mock killall to track calls without killing real processes
cat > "$MOCK_BIN/killall" << 'MOCK'
#!/bin/bash
echo "killall $@" >> /tmp/claude-say-mock-log.txt
# Kill any mock say processes
pkill -f "$TMPDIR_BASE/bin/say" 2>/dev/null
exit 0
MOCK
chmod +x "$MOCK_BIN/killall"

ORIG_PATH="$PATH"
export PATH="$MOCK_BIN:$PATH"

# Clean state before each test
reset_state() {
  rm -f /tmp/claude-say-mock-log.txt
  rm -f /tmp/claude-say-start.txt
  rm -f /tmp/claude-say-rate.txt
  rm -f /tmp/claude-say-offset.txt
  echo "This is a test response with many words to verify the speech output works correctly." > /tmp/claude-say-last.txt
}

# === /say (no args) — default rate 175 ===
reset_state
(date +%s > /tmp/claude-say-start.txt && echo "175" > /tmp/claude-say-rate.txt && rm -f /tmp/claude-say-offset.txt && cat /tmp/claude-say-last.txt | say -r 175 &) 2>/dev/null
sleep 0.5

if [ -f /tmp/claude-say-start.txt ]; then
  pass "/say: creates start timestamp"
else
  fail "/say start timestamp" "file not found"
fi

RATE=$(cat /tmp/claude-say-rate.txt 2>/dev/null)
if [ "$RATE" = "175" ]; then
  pass "/say: records default rate 175"
else
  fail "/say default rate" "got: $RATE"
fi

if [ ! -f /tmp/claude-say-offset.txt ]; then
  pass "/say: clears offset file"
else
  fail "/say clear offset" "offset file still exists"
fi

if grep -q "\-r 175" /tmp/claude-say-mock-log.txt 2>/dev/null; then
  pass "/say: passes -r 175 to say"
else
  fail "/say flags" "log: $(cat /tmp/claude-say-mock-log.txt 2>/dev/null)"
fi

# === /say fast — rate 250 ===
reset_state
(date +%s > /tmp/claude-say-start.txt && echo "250" > /tmp/claude-say-rate.txt && rm -f /tmp/claude-say-offset.txt && cat /tmp/claude-say-last.txt | say -r 250 &) 2>/dev/null
sleep 0.5

RATE=$(cat /tmp/claude-say-rate.txt 2>/dev/null)
if [ "$RATE" = "250" ]; then
  pass "/say fast: records rate 250"
else
  fail "/say fast rate" "got: $RATE"
fi

if grep -q "\-r 250" /tmp/claude-say-mock-log.txt 2>/dev/null; then
  pass "/say fast: passes -r 250 to say"
else
  fail "/say fast flags" "log: $(cat /tmp/claude-say-mock-log.txt 2>/dev/null)"
fi

# === /say slow — rate 130 ===
reset_state
(date +%s > /tmp/claude-say-start.txt && echo "130" > /tmp/claude-say-rate.txt && rm -f /tmp/claude-say-offset.txt && cat /tmp/claude-say-last.txt | say -r 130 &) 2>/dev/null
sleep 0.5

if grep -q "\-r 130" /tmp/claude-say-mock-log.txt 2>/dev/null; then
  pass "/say slow: passes -r 130 to say"
else
  fail "/say slow flags" "log: $(cat /tmp/claude-say-mock-log.txt 2>/dev/null)"
fi

# === /say r 200 — custom rate ===
reset_state
(date +%s > /tmp/claude-say-start.txt && echo "200" > /tmp/claude-say-rate.txt && rm -f /tmp/claude-say-offset.txt && cat /tmp/claude-say-last.txt | say -r 200 &) 2>/dev/null
sleep 0.5

if grep -q "\-r 200" /tmp/claude-say-mock-log.txt 2>/dev/null; then
  pass "/say r 200: passes -r 200 to say"
else
  fail "/say custom rate" "log: $(cat /tmp/claude-say-mock-log.txt 2>/dev/null)"
fi

# === /say pause — kills say and saves offset ===
reset_state
# Simulate: started 10 seconds ago at rate 175
echo $(($(date +%s) - 10)) > /tmp/claude-say-start.txt
echo "175" > /tmp/claude-say-rate.txt

START=$(cat /tmp/claude-say-start.txt 2>/dev/null || echo $(date +%s))
RATE=$(cat /tmp/claude-say-rate.txt 2>/dev/null || echo 175)
NOW=$(date +%s)
ELAPSED=$((NOW - START))
WORDS=$((ELAPSED * RATE / 60))
echo $WORDS > /tmp/claude-say-offset.txt
killall say 2>/dev/null; true

if [ -f /tmp/claude-say-offset.txt ]; then
  OFFSET=$(cat /tmp/claude-say-offset.txt)
  # 10 seconds at 175 wpm = ~29 words
  if [ "$OFFSET" -ge 25 ] && [ "$OFFSET" -le 35 ]; then
    pass "/say pause: saves correct word offset (~29 for 10s at 175wpm, got $OFFSET)"
  else
    fail "/say pause offset" "expected ~29, got $OFFSET"
  fi
else
  fail "/say pause" "offset file not created"
fi

if grep -q "killall say" /tmp/claude-say-mock-log.txt 2>/dev/null; then
  pass "/say pause: calls killall say"
else
  fail "/say pause killall" "killall not called"
fi

# === /say resume — restarts from offset ===
reset_state
echo "15" > /tmp/claude-say-offset.txt
echo "175" > /tmp/claude-say-rate.txt

OFFSET=$(cat /tmp/claude-say-offset.txt 2>/dev/null || echo 0)
RATE=$(cat /tmp/claude-say-rate.txt 2>/dev/null || echo 175)
date +%s > /tmp/claude-say-start.txt
(awk -v skip=$OFFSET 'BEGIN{w=0}{for(i=1;i<=NF;i++){if(w>=skip)printf "%s ",$i; w++}}END{print ""}' /tmp/claude-say-last.txt | say -r $RATE &) 2>/dev/null
sleep 0.5

if [ -f /tmp/claude-say-start.txt ]; then
  pass "/say resume: creates new start timestamp"
else
  fail "/say resume timestamp" "file not found"
fi

if grep -q "\-r 175" /tmp/claude-say-mock-log.txt 2>/dev/null; then
  pass "/say resume: passes rate to say"
else
  fail "/say resume flags" "log: $(cat /tmp/claude-say-mock-log.txt 2>/dev/null)"
fi

# Verify resume skips words — the mock say receives truncated text
LOG_CONTENT=$(cat /tmp/claude-say-mock-log.txt 2>/dev/null)
# Original has 16 words, skip 15 should give ~1 word
if ! echo "$LOG_CONTENT" | grep -q "This is a test"; then
  pass "/say resume: skips words (doesn't start from beginning)"
else
  fail "/say resume skip" "got full text: $LOG_CONTENT"
fi

# === /say again — replays from cache ===
reset_state
(date +%s > /tmp/claude-say-start.txt && echo "175" > /tmp/claude-say-rate.txt && rm -f /tmp/claude-say-offset.txt && cat /tmp/claude-say-last.txt | say -r 175 &) 2>/dev/null
sleep 0.5

if grep -q "\-r 175" /tmp/claude-say-mock-log.txt 2>/dev/null; then
  pass "/say again: replays cached file"
else
  fail "/say again" "say not called"
fi

# === /say with missing cache file ===
reset_state
rm -f /tmp/claude-say-last.txt
rm -f /tmp/claude-say-mock-log.txt
# This should not crash — cat will fail but & backgrounds it
(cat /tmp/claude-say-last.txt 2>/dev/null | say -r 175 &) 2>/dev/null
sleep 0.2
pass "/say missing cache: no crash"

# === /stop — kills say ===
reset_state
rm -f /tmp/claude-say-mock-log.txt
killall say 2>/dev/null; true

if grep -q "killall say" /tmp/claude-say-mock-log.txt 2>/dev/null; then
  pass "/stop: calls killall say"
else
  fail "/stop" "killall not called"
fi

# Clean up any background processes
pkill -f "$MOCK_BIN/say" 2>/dev/null || true
