#!/bin/bash
# Tests for uninstall.sh

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1 — $2"; }

# Helper: install then uninstall in a fake HOME
setup_and_uninstall() {
  local FAKE_HOME="$TMPDIR_BASE/home_$$_$RANDOM"
  mkdir -p "$FAKE_HOME/.claude/commands"
  export HOME="$FAKE_HOME"
  (cd "$REPO_DIR" && bash install.sh) > /dev/null 2>&1
  # Create temp state files that uninstall should clean
  echo "test" > /tmp/claude-say-last.txt.test_$$
  echo "$FAKE_HOME"
}

# --- Test: Removes command files ---
FAKE_HOME=$(setup_and_uninstall)
export HOME="$FAKE_HOME"
# Create state files in the real /tmp that uninstall targets
ORIG_LAST=$(cat /tmp/claude-say-last.txt 2>/dev/null)
echo "test" > /tmp/claude-say-last.txt
echo "test" > /tmp/claude-say-start.txt
echo "test" > /tmp/claude-say-rate.txt
echo "test" > /tmp/claude-say-offset.txt
(cd "$REPO_DIR" && bash uninstall.sh) > /dev/null 2>&1

if [ ! -f "$FAKE_HOME/.claude/commands/say.md" ] && [ ! -f "$FAKE_HOME/.claude/commands/stop.md" ]; then
  pass "Removes command files"
else
  fail "Remove commands" "files still exist"
fi

# --- Test: Removes save script ---
if [ ! -f "$FAKE_HOME/.claude/claude-voice-save.sh" ]; then
  pass "Removes save script"
else
  fail "Remove save script" "file still exists"
fi

# --- Test: Removes temp state files ---
if [ ! -f /tmp/claude-say-last.txt ] && [ ! -f /tmp/claude-say-start.txt ] && \
   [ ! -f /tmp/claude-say-rate.txt ] && [ ! -f /tmp/claude-say-offset.txt ]; then
  pass "Removes all temp state files"
else
  fail "Remove temp files" "some files remain"
fi
# Restore original last.txt if it existed
[ -n "$ORIG_LAST" ] && echo "$ORIG_LAST" > /tmp/claude-say-last.txt

# --- Test: Removes hook from settings.json ---
HOOK_COUNT=$(jq '.hooks.Stop // [] | length' "$FAKE_HOME/.claude/settings.json" 2>/dev/null)
if [ "$HOOK_COUNT" = "0" ] || [ -z "$HOOK_COUNT" ]; then
  pass "Removes hook from settings.json"
else
  fail "Remove hook" "hooks remaining: $HOOK_COUNT"
fi

# --- Test: Cleans up empty hooks object ---
HAS_HOOKS=$(jq 'has("hooks")' "$FAKE_HOME/.claude/settings.json" 2>/dev/null)
if [ "$HAS_HOOKS" = "false" ]; then
  pass "Cleans up empty hooks object"
else
  fail "Cleanup hooks" "hooks key still present"
fi

# --- Test: Preserves other hooks ---
FAKE_HOME2="$TMPDIR_BASE/home_other_$$"
mkdir -p "$FAKE_HOME2/.claude/commands"
export HOME="$FAKE_HOME2"
(cd "$REPO_DIR" && bash install.sh) > /dev/null 2>&1
# Add another hook manually
jq '.hooks.Stop += [{"hooks":[{"type":"command","command":"my-other-hook"}]}]' \
  "$FAKE_HOME2/.claude/settings.json" > "$FAKE_HOME2/.claude/settings.json.tmp" \
  && mv "$FAKE_HOME2/.claude/settings.json.tmp" "$FAKE_HOME2/.claude/settings.json"
(cd "$REPO_DIR" && bash uninstall.sh) > /dev/null 2>&1
OTHER_HOOK=$(jq -r '.hooks.Stop[0].hooks[0].command' "$FAKE_HOME2/.claude/settings.json" 2>/dev/null)
if [ "$OTHER_HOOK" = "my-other-hook" ]; then
  pass "Preserves other hooks after uninstall"
else
  fail "Preserve other hooks" "got: $OTHER_HOOK"
fi

# --- Test: Uninstall when never installed (no errors) ---
FAKE_HOME3="$TMPDIR_BASE/home_empty_$$"
mkdir -p "$FAKE_HOME3/.claude/commands"
export HOME="$FAKE_HOME3"
if (cd "$REPO_DIR" && bash uninstall.sh) > /dev/null 2>&1; then
  pass "Uninstall when never installed succeeds"
else
  fail "Uninstall empty" "exited with error"
fi
