#!/bin/bash

COMMANDS_DIR="$HOME/.claude/commands"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing claude-voice..."

# Install command files
mkdir -p "$COMMANDS_DIR"
cp -f commands/say.md "$COMMANDS_DIR/say.md" 2>/dev/null || cp commands/say.md "$COMMANDS_DIR/say.md"
cp -f commands/stop.md "$COMMANDS_DIR/stop.md" 2>/dev/null || cp commands/stop.md "$COMMANDS_DIR/stop.md"
echo "  Commands installed."

# Install save script
cp -f scripts/claude-voice-save.sh "$HOME/.claude/claude-voice-save.sh" 2>/dev/null || cp scripts/claude-voice-save.sh "$HOME/.claude/claude-voice-save.sh"
chmod +x "$HOME/.claude/claude-voice-save.sh"
echo "  Save script installed."

# Add Stop hook to settings.json
if ! command -v jq &>/dev/null; then
  echo ""
  echo "  WARNING: jq not found. Skipping hook installation."
  echo "  Install jq (brew install jq) then manually add this to ~/.claude/settings.json:"
  echo ""
  echo '  "hooks": {'
  echo '    "Stop": [{'
  echo '      "hooks": [{'
  echo '        "type": "command",'
  echo '        "command": "bash ~/.claude/claude-voice-save.sh"'
  echo '      }]'
  echo '    }]'
  echo '  }'
  echo ""
else
  HOOK_CMD="bash ~/.claude/claude-voice-save.sh"

  if [ ! -f "$SETTINGS" ]; then
    # Create new settings with hook
    jq -n --arg cmd "$HOOK_CMD" \
      '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":$cmd}]}]}}' \
      > "$SETTINGS"
  else
    # Remove any existing claude-voice hooks first, then add fresh
    jq --arg cmd "$HOOK_CMD" '
      .hooks.Stop = ([(.hooks.Stop // [])[] | select(.hooks[].command | contains("claude-voice") | not)]
        + [{"hooks":[{"type":"command","command":$cmd}]}])
    ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  fi
  echo "  Stop hook added to settings.json."
fi

echo ""
echo "Done. claude-voice is installed."
echo ""
echo "Usage:"
echo "  /say              — read last response"
echo "  /say full         — read everything since your last message"
echo "  /say summary      — 2-3 sentence summary"
echo "  /say code         — speak only code blocks"
echo "  /say again        — repeat last spoken text"
echo "  /say fast         — 250 wpm"
echo "  /say slow         — 130 wpm"
echo "  /say r 200        — custom wpm"
echo "  /say voice Alex   — specific voice (run 'say -v ?' to list)"
echo "  /stop             — stop immediately"
echo ""
echo "Flags combine: /say full voice Samantha fast"
