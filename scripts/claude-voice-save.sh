#!/bin/bash
# Called by the Claude Code Stop hook after every turn.
# Extracts the last assistant text response, preprocesses it, and saves to /tmp/claude-say-last.txt.
# This is what makes /say fast, token-free, and clutter-free.
# Note: responses are truncated to 5000 chars (~15 min of speech at 175 wpm).

SESSION_ID=$(jq -r '.session_id' 2>/dev/null)
TRANSCRIPT=$(find ~/.claude/projects -name "${SESSION_ID}.jsonl" 2>/dev/null | head -1)

[ -z "$TRANSCRIPT" ] && exit 0

tail -300 "$TRANSCRIPT" \
  | jq -rs '[.[] | select(.type == "assistant") | select(any(.message.content[]?; .type == "text"))] | last | .message.content[] | select(.type == "text") | .text' 2>/dev/null \
  | head -c 5000 \
  | sed \
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
      -e 's/_/ /g' \
  > /tmp/claude-say-last.txt.tmp 2>/dev/null \
  && mv /tmp/claude-say-last.txt.tmp /tmp/claude-say-last.txt
