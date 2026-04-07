#!/bin/bash

COMMANDS_DIR="$HOME/.claude/commands"
SETTINGS="$HOME/.claude/settings.json"

echo "Uninstalling claude-voice..."

rm -f "$COMMANDS_DIR/say.md"
rm -f "$COMMANDS_DIR/stop.md"
rm -f "$HOME/.claude/claude-voice-save.sh"
rm -f /tmp/claude-say-last.txt

# Remove Stop hook from settings.json
if command -v jq &>/dev/null && [ -f "$SETTINGS" ]; then
  jq 'del(.hooks.Stop[] | select(.hooks[].command | contains("claude-voice-save")))
      | if .hooks.Stop == [] then del(.hooks.Stop) else . end
      | if .hooks == {} then del(.hooks) else . end' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  Stop hook removed from settings.json."
fi

echo "Done."
