# claude-voice

Text-to-speech commands for [Claude Code](https://claude.ai/code). Reads Claude's responses aloud using the macOS `say` command.

## Requirements

- macOS (uses built-in `say` command)
- [Claude Code](https://claude.ai/code) installed
- `jq` installed (`brew install jq`)

---

## Install

```bash
git clone https://github.com/TomJAdam/claude-voice.git
cd claude-voice
./install.sh
```

Then **restart Claude Code** to activate the hooks.

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
| `/say again` or `/say repeat` | Repeat the last spoken text |
| `/say pause` | Pause at current position |
| `/say resume` | Resume from where it paused |

### Inline `/say`

Append `/say` to any prompt to automatically hear the response read aloud:

```
explain quantum entanglement /say
what does this function do /say fast
summarize this PR /say slow
```

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

claude-voice uses two Claude Code hooks:

**UserPromptSubmit hook** (`claude-voice-intercept.sh`) — Intercepts `/say`, `/stop`, and inline `/say` prompts before they reach the LLM. Basic playback, pause, resume, speed/voice flags, and stop are handled entirely in shell — zero tokens, instant response. Only `/say full`, `/say summary`, and `/say code` pass through to Claude since they need LLM processing. For inline `/say`, the hook sets a flag and lets the prompt through.

**Stop hook** (`claude-voice-save.sh`) — Runs after every Claude turn. Reads `last_assistant_message` from the hook payload, applies text preprocessing, and saves it to a session-specific cache. If an inline `/say` flag was set, it automatically speaks the response.

Each session's cache is stored in `/tmp/claude-say-$PPID/` so multiple concurrent sessions don't interfere with each other.

| | Without hooks | With hooks |
|---|---|---|
| Speed | Slow (LLM round-trip) | Instant |
| Token cost | ~300 tokens per `/say` | 0 tokens |
| Concurrent sessions | Shared cache (conflicts) | Isolated per session |

## Text preprocessing

`say` struggles with code identifiers and technical terms out of the box. claude-voice preprocesses text before speaking to make it significantly more natural:

| Raw | Spoken as |
|---|---|
| `getUsersDaysOffMapStartingAt` | "get Users Days Off Map Starting At" |
| `Complete_Day_Off__c` | "Complete Day Off" |
| `List<Complete_Day_Off__c>` | "List of Complete Day Off" |
| `calculatePauseExpiryWithinCompleteUserAvailability` | "calculate Pause Expiry Within Complete User Availability" |
| `[HIGH]` | "High," |
| `—` | natural pause |
| backticks, `@param` | cleaned up |

This makes responses with Apex, Java, JavaScript, or any camelCase/snake_case code significantly more listenable.

## Tests

```bash
bash test.sh
```

Runs 68 tests covering install/uninstall, text preprocessing, command behavior, and the intercept hook.
