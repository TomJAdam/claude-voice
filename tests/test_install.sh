#!/bin/bash
# Tests for install.sh

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1 — $2"; }

# Helper: set up a fake HOME and run install.sh
run_install() {
  local FAKE_HOME="$TMPDIR_BASE/home_$$_$RANDOM"
  mkdir -p "$FAKE_HOME/.claude/commands"
  export HOME="$FAKE_HOME"
  # If a settings file was pre-created, it's already in place
  (cd "$REPO_DIR" && bash install.sh) > /dev/null 2>&1
  echo "$FAKE_HOME"
}

# --- Test: Fresh install creates settings.json with hook ---
FAKE_HOME=$(run_install)
if [ -f "$FAKE_HOME/.claude/settings.json" ]; then
  HOOK_COUNT=$(jq '.hooks.Stop | length' "$FAKE_HOME/.claude/settings.json")
  if [ "$HOOK_COUNT" = "1" ]; then
    pass "Fresh install creates settings.json with 1 hook"
  else
    fail "Fresh install hook count" "expected 1, got $HOOK_COUNT"
  fi
else
  fail "Fresh install creates settings.json" "file not found"
fi

# --- Test: Hook command is correct ---
HOOK_CMD=$(jq -r '.hooks.Stop[0].hooks[0].command' "$FAKE_HOME/.claude/settings.json")
if echo "$HOOK_CMD" | grep -q "claude-voice-save.sh"; then
  pass "Hook command references claude-voice-save.sh"
else
  fail "Hook command" "got: $HOOK_CMD"
fi

# --- Test: Hook does NOT have async:true ---
ASYNC=$(jq '.hooks.Stop[0].hooks[0].async // empty' "$FAKE_HOME/.claude/settings.json")
if [ -z "$ASYNC" ]; then
  pass "Hook does not have async:true"
else
  fail "Hook async" "found async: $ASYNC"
fi

# --- Test: UserPromptSubmit hook installed ---
INTERCEPT_COUNT=$(jq '.hooks.UserPromptSubmit | length' "$FAKE_HOME/.claude/settings.json")
if [ "$INTERCEPT_COUNT" = "1" ]; then
  pass "UserPromptSubmit hook installed"
else
  fail "UserPromptSubmit hook" "expected 1, got $INTERCEPT_COUNT"
fi

# --- Test: Save script is installed and executable ---
if [ -x "$FAKE_HOME/.claude/claude-voice-save.sh" ]; then
  pass "Save script installed and executable"
else
  fail "Save script" "not found or not executable"
fi

# --- Test: Intercept script is installed and executable ---
if [ -x "$FAKE_HOME/.claude/claude-voice-intercept.sh" ]; then
  pass "Intercept script installed and executable"
else
  fail "Intercept script" "not found or not executable"
fi

# --- Test: Command files installed ---
if [ -f "$FAKE_HOME/.claude/commands/say.md" ] && [ -f "$FAKE_HOME/.claude/commands/stop.md" ]; then
  pass "Command files installed"
else
  fail "Command files" "say.md or stop.md missing"
fi

# --- Test: Re-install deduplicates hooks ---
export HOME="$FAKE_HOME"
(cd "$REPO_DIR" && bash install.sh) > /dev/null 2>&1
STOP_COUNT=$(jq '.hooks.Stop | length' "$FAKE_HOME/.claude/settings.json")
INTERCEPT_COUNT=$(jq '.hooks.UserPromptSubmit | length' "$FAKE_HOME/.claude/settings.json")
if [ "$STOP_COUNT" = "1" ] && [ "$INTERCEPT_COUNT" = "1" ]; then
  pass "Re-install deduplicates (1 Stop + 1 UserPromptSubmit)"
else
  fail "Re-install dedupe" "Stop=$STOP_COUNT, UserPromptSubmit=$INTERCEPT_COUNT"
fi

# --- Test: Preserves other hooks ---
FAKE_HOME2="$TMPDIR_BASE/home_other_$$"
mkdir -p "$FAKE_HOME2/.claude/commands"
echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-other-hook"}]}]}}' > "$FAKE_HOME2/.claude/settings.json"
export HOME="$FAKE_HOME2"
(cd "$REPO_DIR" && bash install.sh) > /dev/null 2>&1
HOOK_COUNT=$(jq '.hooks.Stop | length' "$FAKE_HOME2/.claude/settings.json")
OTHER_HOOK=$(jq -r '.hooks.Stop[0].hooks[0].command' "$FAKE_HOME2/.claude/settings.json")
if [ "$HOOK_COUNT" = "2" ] && [ "$OTHER_HOOK" = "my-other-hook" ]; then
  pass "Preserves existing hooks (2 total, other hook first)"
else
  fail "Preserve hooks" "count=$HOOK_COUNT, other=$OTHER_HOOK"
fi

# --- Test: Preserves non-hook settings ---
FAKE_HOME3="$TMPDIR_BASE/home_perms_$$"
mkdir -p "$FAKE_HOME3/.claude/commands"
echo '{"permissions":{"allow":["Bash(*)"]}}' > "$FAKE_HOME3/.claude/settings.json"
export HOME="$FAKE_HOME3"
(cd "$REPO_DIR" && bash install.sh) > /dev/null 2>&1
PERMS=$(jq -r '.permissions.allow[0]' "$FAKE_HOME3/.claude/settings.json")
if [ "$PERMS" = "Bash(*)" ]; then
  pass "Preserves non-hook settings (permissions)"
else
  fail "Preserve settings" "permissions lost: $PERMS"
fi
