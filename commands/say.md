Read conversation content aloud via the macOS `say` command using the Bash tool.

Argument: $ARGUMENTS

**Content selection** (can combine with speed/voice flags):
- No argument: output a short fun status line ("Speaking...", "On it...", "Here we go...", "Loud and clear..." etc.), then record state and run:
  ```bash
  date +%s > /tmp/claude-say-start.txt && echo "RATE" > /tmp/claude-say-rate.txt && rm -f /tmp/claude-say-offset.txt && cat /tmp/claude-say-last.txt | say [FLAGS] &
  ```
  Replace RATE with the numeric rate (175 if no rate flag, 130 for slow, 250 for fast, or the custom number).
- `again`: same as no argument — output status, record state, run same command. If file missing, say "nothing to repeat".
- `pause`: kill say and save word offset based on elapsed time:
  ```bash
  START=$(cat /tmp/claude-say-start.txt 2>/dev/null || echo $(date +%s)); RATE=$(cat /tmp/claude-say-rate.txt 2>/dev/null || echo 175); NOW=$(date +%s); ELAPSED=$((NOW - START)); WORDS=$((ELAPSED * RATE / 60)); echo $WORDS > /tmp/claude-say-offset.txt; killall say 2>/dev/null; true
  ```
  Output "Paused." as your text response.
- `resume`: restart from saved word offset:
  ```bash
  OFFSET=$(cat /tmp/claude-say-offset.txt 2>/dev/null || echo 0); RATE=$(cat /tmp/claude-say-rate.txt 2>/dev/null || echo 175); date +%s > /tmp/claude-say-start.txt; awk -v skip=$OFFSET 'BEGIN{w=0}{for(i=1;i<=NF;i++){if(w>=skip)printf "%s ",$i; w++}}END{print ""}' /tmp/claude-say-last.txt | say -r $RATE &
  ```
  Output "Resuming." as your text response. Speed/voice flags override the saved rate if provided.
- `full`: speak all assistant text responses since the last user message, concatenated. Claude extracts and preprocesses the text, then runs the full pipeline below.
- `code`: extract only content inside ``` fenced code blocks from the last response and speak it. If none, say "no code in last response". Use the full pipeline below.
- `summary`: summarize the last response into 2-3 concise sentences, then speak the summary. Use the full pipeline below.

**Speed flags:**
- `slow`: use `-r 130`
- `fast`: use `-r 250`
- `r <number>`: use `-r <number>`

**Voice flag:**
- `voice <name>`: use `-v <name>`

Flags combine freely: `full slow`, `voice Alex fast`, `again slow`, `resume fast` etc.

**Full pipeline** (used only for `full`, `code`, `summary`):

```bash
echo "$TEXT" | sed \
  -e 's/\[HIGH\]/High,/g' -e 's/\[MEDIUM\]/Medium,/g' -e 's/\[LOW\]/Low,/g' \
  -e 's/__c//g' -e 's/__/  /g' -e 's/<[^>]*>//g' \
  -e 's/@//g' -e 's/`//g' -e 's/—/, /g' \
  -e 's/\([a-z]\)\([A-Z]\)/\1 \2/g' \
  -e 's/\([a-z]\)\([A-Z]\)/\1 \2/g' \
  -e 's/\([A-Z][A-Z]\)\([A-Z][a-z]\)/\1 \2/g' \
  -e 's/_/ /g' | tee /tmp/claude-say-last.txt | say [FLAGS] &
```
