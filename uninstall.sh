#!/bin/bash

COMMANDS_DIR="$HOME/.claude/commands"
SETTINGS="$HOME/.claude/settings.json"

echo "Uninstalling claude-voice..."

rm -f "$COMMANDS_DIR/say.md"
rm -f "$COMMANDS_DIR/stop.md"
rm -f "$HOME/.claude/claude-voice-save.sh"
rm -f "$HOME/.claude/claude-voice-intercept.sh"
# Clean up session directories and legacy flat files
rm -rf /tmp/claude-say-*/
rm -f /tmp/claude-say-last.txt /tmp/claude-say-start.txt /tmp/claude-say-rate.txt /tmp/claude-say-offset.txt

# Remove Stop hook from settings.json
if command -v jq &>/dev/null && [ -f "$SETTINGS" ]; then
  jq 'del(.hooks.Stop[]? | select(.hooks[]?.command | contains("claude-voice")))
      | del(.hooks.UserPromptSubmit[]? | select(.hooks[]?.command | contains("claude-voice")))
      | if .hooks.Stop == [] then del(.hooks.Stop) else . end
      | if .hooks.UserPromptSubmit == [] then del(.hooks.UserPromptSubmit) else . end
      | if .hooks == {} then del(.hooks) else . end' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  Hooks removed from settings.json."
fi

echo "Done."
