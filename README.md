# claude-voice

Text-to-speech commands for [Claude Code](https://claude.ai/code). Reads Claude's responses aloud using the macOS `say` command.

## Requirements

- macOS (uses built-in `say` command)
- [Claude Code](https://claude.ai/code) installed
- `jq` installed (`brew install jq`)

---

## ⚠️ IMPORTANT: Install the Stop Hook

**Without the Stop hook, `/say` works but is slow, expensive, and clutters the chat.**

The Stop hook runs a lightweight script after every Claude turn that pre-saves and pre-processes the last response to `/tmp/claude-say-last.txt`. This means `/say` can read that file directly instead of scanning the entire conversation.

| | Without hook | With hook |
|---|---|---|
| Speed | Slow (Claude scans conversation) | Instant |
| Token cost | ~1,000–3,000 tokens per `/say` | 0 tokens |
| Chat output | Full bash pipeline shown | Clean status line only |

The `install.sh` script adds the hook automatically. **Do not skip it.**

---

## Install

```bash
git clone https://github.com/TomJAdam/claude-voice.git
cd claude-voice
./install.sh
```

Then **restart Claude Code** (or open `/hooks`) to activate the Stop hook.

## Uninstall

```bash
./uninstall.sh
```

---

## Commands

### `/say` — read last response aloud

| Command | Description |
|---|---|
| `/say` | Read the last response |
| `/say full` | Read everything since your last message |
| `/say summary` | Speak a 2–3 sentence summary |
| `/say code` | Speak only code blocks |
| `/say again` | Repeat the last spoken text |
| `/say pause` | Pause at current position |
| `/say resume` | Resume from where it paused |

### Speed flags

| Flag | Rate |
|---|---|
| `slow` | 130 wpm |
| `fast` | 250 wpm |
| `r 200` | Custom wpm |

### Voice flag

`voice <name>` — use a specific macOS voice. To list available voices:

```bash
say -v ?
```

### Combining flags

```
/say full slow
/say voice Samantha
/say summary fast
/say full voice Alex fast
/say again fast
/say resume fast
```

### `/stop` — stop speaking

Immediately kills any active `say` process.

---

## How it works

A Claude Code Stop hook runs `claude-voice-save.sh` silently after every turn. The script reads the session transcript, extracts the last assistant text response, applies preprocessing (camelCase splitting, Salesforce `__c` stripping, markdown cleanup), and saves it to `/tmp/claude-say-last.txt`.

When you type `/say`, Claude reads from that file and pipes it to `say` — zero conversation scanning, zero extra tokens.

The `full`, `code`, and `summary` flags still use Claude for extraction since they require understanding of conversation context.

## Text preprocessing

`say` struggles with code identifiers and technical terms out of the box. claude-voice preprocesses text before speaking to make it significantly more natural:

| Raw | Spoken as |
|---|---|
| `getUsersDaysOffMapStartingAt` | "get Users Days Off Map Starting At" |
| `Complete_Day_Off__c` | "Complete Day Off" |
| `List<Complete_Day_Off__c>` | "List" |
| `calculatePauseExpiryWithinCompleteUserAvailability` | "calculate Pause Expiry Within Complete User Availability" |
| `[HIGH]` | "High," |
| `—` | natural pause |
| backticks, `@param` | cleaned up |

This makes responses with Apex, Java, JavaScript, or any camelCase/snake_case code significantly more listenable.
