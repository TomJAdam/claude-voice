#!/bin/bash
set -e

COMMANDS_DIR="$HOME/.claude/commands"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing claude-voice..."

# Install command files
mkdir -p "$COMMANDS_DIR"
cp commands/say.md "$COMMANDS_DIR/say.md"
cp commands/stop.md "$COMMANDS_DIR/stop.md"
echo "  Commands installed."

# Install save script
cp scripts/claude-voice-save.sh "$HOME/.claude/claude-voice-save.sh"
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
  echo '        "command": "bash ~/.claude/claude-voice-save.sh",'
  echo '        "async": true'
  echo '      }]'
  echo '    }]'
  echo '  }'
  echo ""
else
  HOOK='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/claude-voice-save.sh","async":true}]}]}}'

  if [ ! -f "$SETTINGS" ]; then
    echo "$HOOK" | jq '.' > "$SETTINGS"
  else
    # Merge hook into existing settings without overwriting anything
    jq --argjson hook "$HOOK" \
      '.hooks.Stop = (.hooks.Stop // []) + $hook.hooks.Stop' \
      "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
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
