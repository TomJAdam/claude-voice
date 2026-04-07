Read conversation content aloud via the macOS `say` command using the Bash tool.

Argument: $ARGUMENTS

**Content selection** (can combine with speed/voice flags):
- No argument: output a short fun status line ("Speaking...", "On it...", "Here we go...", "Loud and clear..." etc.), then run: `cat /tmp/claude-say-last.txt | say [FLAGS] &`
- `again`: same as no argument — output status, run: `cat /tmp/claude-say-last.txt | say [FLAGS] &`. If file missing, say "nothing to repeat".
- `full`: speak all assistant text responses since the last user message, concatenated. Claude extracts and preprocesses the text, then runs the full pipeline below.
- `code`: extract only content inside ``` fenced code blocks from the last response and speak it. If none, say "no code in last response". Use the full pipeline below.
- `summary`: summarize the last response into 2-3 concise sentences, then speak the summary. Use the full pipeline below.

**Speed flags:**
- `slow`: use `-r 130`
- `fast`: use `-r 250`
- `r <number>`: use `-r <number>`

**Voice flag:**
- `voice <name>`: use `-v <name>`

Flags combine freely: `full slow`, `voice Alex fast`, `again slow` etc.

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
