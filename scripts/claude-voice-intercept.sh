#!/bin/bash
# UserPromptSubmit hook for claude-voice.
# Intercepts /say commands that don't need the LLM and runs them directly.
# SAFETY: fail-open on any error — never block normal prompts.

trap 'exit 0' ERR

INPUT=$(cat 2>/dev/null) || exit 0
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[ -z "$PROMPT" ] && exit 0

# Only handle /say and /stop commands — everything else passes through
case "$PROMPT" in
  /say\ *) ARGS="${PROMPT#/say }" ;;
  /say)    ARGS="" ;;
  /stop)   killall say 2>/dev/null || true; printf '{"decision":"block","reason":"Stopped."}\n'; exit 0 ;;
  *)       exit 0 ;;
esac

# If args contain words that need the LLM, pass through
for word in $ARGS; do
  case "$word" in
    full|summary|code) exit 0 ;;
  esac
done

# Session-specific directory (PPID = Claude Code process)
SD="/tmp/claude-say-$PPID"
mkdir -p "$SD"

# Parse flags from args
RATE=175
SAY_FLAGS=""
SKIP_NEXT=""
MODE=""

for word in $ARGS; do
  if [ -n "$SKIP_NEXT" ]; then
    case "$SKIP_NEXT" in
      rate)  RATE="$word" ;;
      voice) SAY_FLAGS="$SAY_FLAGS -v $word" ;;
    esac
    SKIP_NEXT=""
    continue
  fi
  case "$word" in
    slow)    RATE=130 ;;
    fast)    RATE=250 ;;
    r)       SKIP_NEXT="rate" ;;
    voice)   SKIP_NEXT="voice" ;;
    pause)   MODE="pause" ;;
    resume)  MODE="resume" ;;
    again|repeat) MODE="again" ;;
    *)       ;; # ignore unknown flags
  esac
done

SAY_FLAGS="-r $RATE $SAY_FLAGS"

block() {
  printf '{"decision":"block","reason":"%s"}\n' "$1"
  exit 0
}

case "$MODE" in
  pause)
    START=$(cat "$SD/start.txt" 2>/dev/null || echo "$(date +%s)")
    SAVED_RATE=$(cat "$SD/rate.txt" 2>/dev/null || echo 175)
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))
    WORDS=$((ELAPSED * SAVED_RATE / 60))
    echo "$WORDS" > "$SD/offset.txt"
    (killall say 2>/dev/null || true)
    block "Paused."
    ;;
  resume)
    OFFSET=$(cat "$SD/offset.txt" 2>/dev/null || echo 0)
    date +%s > "$SD/start.txt"
    echo "$RATE" > "$SD/rate.txt"
    awk -v skip="$OFFSET" 'BEGIN{w=0}{for(i=1;i<=NF;i++){if(w>=skip)printf "%s ",$i; w++}}END{print ""}' "$SD/last.txt" | say $SAY_FLAGS > /dev/null 2>&1 &
    disown
    block "Resuming."
    ;;
  *)
    # Default and "again"/"repeat": speak from cached file
    if [ ! -f "$SD/last.txt" ]; then
      block "Nothing to say yet."
    fi
    date +%s > "$SD/start.txt"
    echo "$RATE" > "$SD/rate.txt"
    rm -f "$SD/offset.txt"
    cat "$SD/last.txt" | say $SAY_FLAGS > /dev/null 2>&1 &
    disown
    block "Speaking."
    ;;
esac
