#!/bin/bash
# Called by the Claude Code Stop hook after every turn.
# Reads last_assistant_message from the hook's stdin payload, preprocesses it,
# and saves to a session-specific directory under /tmp/claude-say-$PPID/.
# PPID = the Claude Code process PID, shared by both hook and bash tool.
# This is what makes /say fast, token-free, and clutter-free.
# Note: responses are truncated to 5000 chars (~15 min of speech at 175 wpm).

SESSION_DIR="/tmp/claude-say-${PPID}"
mkdir -p "$SESSION_DIR"

# Read the hook payload — contains last_assistant_message directly
INPUT=$(cat 2>/dev/null) || exit 0
MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)

[ -z "$MESSAGE" ] && exit 0

echo "$MESSAGE" \
  | head -c 5000 \
  | sed \
      -e 's/\[HIGH\]/High,/g' \
      -e 's/\[MEDIUM\]/Medium,/g' \
      -e 's/\[LOW\]/Low,/g' \
      -e 's/__c//g' \
      -e 's/__/  /g' \
      -e 's/\([A-Za-z_]\)<\([A-Za-z_][^>]*\)>/\1 of \2/g' \
      -e 's/\([A-Za-z_]\)<\([A-Za-z_][^>]*\)>/\1 of \2/g' \
      -e 's/<[^>]*>//g' \
      -e 's/\*\*\([^*]*\)\*\*/\1/g' \
      -e 's/\*\([^*]*\)\*/\1/g' \
      -e 's/^##* //g' \
      -e 's/\[\([^]]*\)\]([^)]*)/ \1 /g' \
      -e 's/@//g' \
      -e 's/`//g' \
      -e 's/—/, /g' \
      -e 's/\([a-z]\)\([A-Z]\)/\1 \2/g' \
      -e 's/\([a-z]\)\([A-Z]\)/\1 \2/g' \
      -e 's/\([A-Z][A-Z]\)\([A-Z][a-z]\)/\1 \2/g' \
      -e 's/_/ /g' \
  > "$SESSION_DIR/last.txt.tmp" 2>/dev/null \
  && mv "$SESSION_DIR/last.txt.tmp" "$SESSION_DIR/last.txt"

# Auto-speak if the intercept hook flagged this turn
if [ -f "$SESSION_DIR/auto-speak" ]; then
  FLAGS=$(cat "$SESSION_DIR/auto-speak")
  rm -f "$SESSION_DIR/auto-speak"

  # Parse flags (e.g. "fast", "slow", "r 200", "voice Alex")
  RATE=175
  SAY_FLAGS=""
  SKIP_NEXT=""
  for word in $FLAGS; do
    if [ -n "$SKIP_NEXT" ]; then
      case "$SKIP_NEXT" in
        rate)  RATE="$word" ;;
        voice) SAY_FLAGS="$SAY_FLAGS -v $word" ;;
      esac
      SKIP_NEXT=""
      continue
    fi
    case "$word" in
      slow) RATE=130 ;; fast) RATE=250 ;; r) SKIP_NEXT="rate" ;; voice) SKIP_NEXT="voice" ;; *) ;;
    esac
  done

  date +%s > "$SESSION_DIR/start.txt"
  echo "$RATE" > "$SESSION_DIR/rate.txt"
  rm -f "$SESSION_DIR/offset.txt"
  cat "$SESSION_DIR/last.txt" | say -r $RATE $SAY_FLAGS > /dev/null 2>&1 &
  disown
fi
