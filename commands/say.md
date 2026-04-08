Read conversation content aloud via the macOS `say` command using the Bash tool. Do NOT output any text response — just run the bash command silently.

All state files are stored in a session-specific directory: `SD=/tmp/claude-say-$PPID`. Always set SD at the start of every bash command.

Argument: $ARGUMENTS

**Content selection** (can combine with speed/voice flags):
- No argument: record state and run:
  ```bash
  SD=/tmp/claude-say-$PPID; mkdir -p $SD; date +%s > $SD/start.txt && echo "RATE" > $SD/rate.txt && rm -f $SD/offset.txt && cat $SD/last.txt | say [FLAGS] &
  ```
  Replace RATE with the numeric rate (175 if no rate flag, 130 for slow, 250 for fast, or the custom number).
- `again` or `repeat`: same as no argument — record state, run same command. If file missing, do nothing.
- `pause`: kill say and save word offset based on elapsed time:
  ```bash
  SD=/tmp/claude-say-$PPID; mkdir -p $SD; START=$(cat $SD/start.txt 2>/dev/null || echo $(date +%s)); RATE=$(cat $SD/rate.txt 2>/dev/null || echo 175); NOW=$(date +%s); ELAPSED=$((NOW - START)); WORDS=$((ELAPSED * RATE / 60)); echo $WORDS > $SD/offset.txt; killall say 2>/dev/null; true
  ```
- `resume`: restart from saved word offset:
  ```bash
  SD=/tmp/claude-say-$PPID; mkdir -p $SD; OFFSET=$(cat $SD/offset.txt 2>/dev/null || echo 0); RATE=$(cat $SD/rate.txt 2>/dev/null || echo 175); date +%s > $SD/start.txt; awk -v skip=$OFFSET 'BEGIN{w=0}{for(i=1;i<=NF;i++){if(w>=skip)printf "%s ",$i; w++}}END{print ""}' $SD/last.txt | say -r $RATE &
  ```
  Speed/voice flags override the saved rate if provided.
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
SD=/tmp/claude-say-$PPID; mkdir -p $SD; echo "$TEXT" | sed \
  -e 's/\[HIGH\]/High,/g' -e 's/\[MEDIUM\]/Medium,/g' -e 's/\[LOW\]/Low,/g' \
  -e 's/__c//g' -e 's/__/  /g' \
  -e 's/\([A-Za-z_]\)<\([A-Za-z_][^>]*\)>/\1 of \2/g' -e 's/<[^>]*>//g' \
  -e 's/@//g' -e 's/`//g' -e 's/—/, /g' \
  -e 's/\([a-z]\)\([A-Z]\)/\1 \2/g' \
  -e 's/\([a-z]\)\([A-Z]\)/\1 \2/g' \
  -e 's/\([A-Z][A-Z]\)\([A-Z][a-z]\)/\1 \2/g' \
  -e 's/_/ /g' | tee $SD/last.txt | say [FLAGS] &
```
