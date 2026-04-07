#!/bin/bash
# Called by the Claude Code Stop hook after every turn.
# Extracts the last assistant text response, preprocesses it, and saves to a
# session-specific directory under /tmp/claude-say-$PPID/.
# PPID = the Claude Code process PID, shared by both hook and bash tool.
# This is what makes /say fast, token-free, and clutter-free.
# Note: responses are truncated to 5000 chars (~15 min of speech at 175 wpm).

SESSION_DIR="/tmp/claude-say-${PPID}"
mkdir -p "$SESSION_DIR"

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
  > "$SESSION_DIR/last.txt.tmp" 2>/dev/null \
  && mv "$SESSION_DIR/last.txt.tmp" "$SESSION_DIR/last.txt"
