# Claude Code Ultimate Status Line Timer

A multi-line status bar for [Claude Code](https://code.claude.com) that tracks real time spent using Claude — with accurate overlap handling, daily/weekly totals, and billing info across all terminals and sessions.

## What It Looks Like

**Subscription users** (Pro/Max) — two overlapping sessions correctly deduplicated:
```
[Opus] 📁 my-project | 🌿 main | Session: 01h 23m 45s (API: 12m 34s)
████░░░░░░ 42% ctx | #2 | Today: 02h 00m | Wall: 03h 00m | Active: 25m | Week: 12h 34m | Limit (5hr): 68% used, resets in 1h 51m | Limit (7day): 4% used
```

**No overlapping sessions** — Today and Wall match:
```
[Opus] 📁 counter | 🌿 main | Session: 00h 45m 00s (API: 10m 00s)
██░░░░░░░░ 18% ctx | #2 | Today: 01h 30m | Wall: 01h 30m | Active: 15m | Week: 08h 00m | Limit (5hr): 30% used, resets in 3h 0m | Limit (7day): 8% used
```

**API users** see daily cost instead of rate limits:
```
[Sonnet] 📁 api-project | Session: 00h 30m 00s (API: 08m 15s)
███████░░░ 75% ctx | #1 | Today: 00h 30m | Wall: 00h 30m | Active: 8m | Week: 02h 15m | Cost: $2.47
```

## Data Flow: How It Works End-to-End

```
┌─────────────────────────────────────────────────────────────┐
│  CLAUDE CODE                                                 │
│                                                              │
│  After each assistant message, pipes JSON to stdin:          │
│  {                                                           │
│    "session_id": "abc123",                                   │
│    "cost": {                                                 │
│      "total_duration_ms": 4925000,  ← wall-clock since start │
│      "total_api_duration_ms": 745000, ← Claude thinking time │
│      "total_cost_usd": 1.25                                 │
│    },                                                        │
│    "context_window": { "used_percentage": 42 },              │
│    "rate_limits": { "five_hour": { "used_percentage": 68 } } │
│    ...more fields                                            │
│  }                                                           │
│  Updates debounced at 300ms. Cancelled if script still runs. │
└──────────────────────────┬──────────────────────────────────┘
                           │ stdin (JSON)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  ULTIMATE-TIMER.SH                                           │
│                                                              │
│  1. Read JSON from stdin                                     │
│  2. Extract: session_id, durations, cost, context %, limits  │
│  3. Record timestamps locally:                               │
│     - First time seeing session_id → store start = now       │
│     - Every update → overwrite end = now                     │
│  4. Write to daily file (atomic via mktemp + mv)             │
│  5. Merge overlapping intervals for accurate daily total     │
│  6. Sum merged intervals for weekly total                    │
│  7. Format and output two lines to stdout                    │
└──────────────────────────┬──────────────────────────────────┘
                           │ stdout (formatted text)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  CLAUDE CODE STATUS BAR                                      │
│                                                              │
│  Displays whatever the script prints at the bottom of the    │
│  terminal. Each line = one row. Supports ANSI colors.        │
│                                                              │
│  [Opus] 📁 my-project | 🌿 main | Session: 01h 23m 45s ... │
│  ████░░░░░░ 42% ctx | #2 | Today: 02h 00m | Wall: 03h ...  │
└─────────────────────────────────────────────────────────────┘
```

### Local Storage

```
~/.claude/timer-daily-2026-03-31.json
{
  "abc123": {
    "start": 1711926000,     ← Unix epoch: first time we saw this session
    "end":   1711933200,     ← Unix epoch: last assistant message in this session
    "api_ms": 745000,        ← Claude's cumulative API processing time
    "cost": 1.25             ← Claude's cumulative session cost
  },
  "def456": {
    "start": 1711929600,
    "end":   1711936800,
    "api_ms": 300000,
    "cost": 0.80
  }
}
```

**Key detail:** `start` is set once (first time a session_id appears). `end` is updated to `now` every time the script runs for that session. These are **our own timestamps**, not Claude's — this lets us do accurate interval merging.

## Three Time Dimensions

This is the core feature. We track three different measures of "how long" because they answer different questions:

### Today (merged intervals) — "How long was I sitting with Claude?"

```
Timeline:
1:00pm          2:00pm          3:00pm
  |--- Session A ---|
          |--- Session B --------------|

Stored intervals:
  sess-A: [1:00pm → 2:00pm]
  sess-B: [1:30pm → 3:00pm]

Merge: 1:30 overlaps with 2:00, so merge into [1:00pm → 3:00pm]
Result: Today = 2 hours ✓
```

This is the most accurate answer to "how long was I using Claude today." Overlapping sessions don't inflate the number. Idle tail time gets trimmed because `end` only updates when Claude responds.

### Wall (naive sum) — "Sum of all session durations"

Using the same example:
```
sess-A duration: 2:00 - 1:00 = 1 hour
sess-B duration: 3:00 - 1:30 = 1.5 hours
Wall = 2.5 hours
```

This is the raw sum. **If Wall > Today, overlapping sessions were deduplicated.** If they match, you had no concurrent sessions. Useful as a sanity check.

### Active (API time) — "How long was Claude actually working?"

Sum of `total_api_duration_ms` across all sessions. This is only the time Claude spent thinking and generating responses — not waiting for you to type.

```
sess-A api_ms: 900000 (15 minutes)
sess-B api_ms: 600000 (10 minutes)
Active = 25 minutes
```

### Comparison

| Scenario | Today (merged) | Wall (sum) | Active (API) |
|---|---|---|---|
| 1 session, actively coding 1hr | ~1h | ~1h | ~15-30m |
| 1 session, mostly idle 3hr | ~3h | ~3h | ~5m |
| 2 concurrent sessions, 1hr overlap | **2h (correct)** | 3h (inflated) | 25m |
| 3 sessions, all overlapping | **real span** | 3x inflated | honest total |

## What Each Field Means

### Line 1 — Session Info

| Field | Description |
|---|---|
| `[Opus]` | Current Claude model name |
| 📁 `my-project` | Current working directory |
| 🌿 `main` | Git branch (cached per-repo, refreshes every 5s) |
| `Session: 01h 23m 45s` | Wall-clock time since this specific session started |
| `(API: 12m 34s)` | Time Claude spent actively processing in this session |

### Line 2 — Usage & Limits

| Field | Description |
|---|---|
| `████░░░░░░ 42% ctx` | Context window usage. Green (<70%), yellow (70-89%), red (90%+). |
| `!! >200k` | Warning when total tokens exceed 200k (only shown when triggered). |
| `#3` | Number of unique Claude Code sessions tracked today. |
| `Today: 02h 00m` | Real time at desk with Claude (merged intervals, overlap-safe). |
| `Wall: 03h 00m` | Naive sum of all session durations (for comparison). |
| `Active: 25m` | Total API processing time across all sessions today. |
| `Week: 12h 34m` | Rolling 7-day total (merged intervals). |
| `Limit (5hr): 68% used` | 5-hour rolling rate limit consumption (subscription only). |
| `resets in 1h 51m` | Time until the 5-hour window opens up again. |
| `Limit (7day): 4% used` | 7-day rolling rate limit consumption (subscription only). |
| `Cost: $2.47` | Daily cost total — shown for API users instead of rate limits. |

### Understanding Rate Limits (Subscription Users)

- **Limit (5hr)** is your short-term budget. When it approaches 100%, you'll be rate-limited until the window rolls forward. Watch this day-to-day.
- **Limit (7day)** is your weekly budget. Matters for sustained heavy usage across multiple days.
- **resets in Xh Xm** tells you exactly when the 5-hour window recovers.

## Prerequisites

- [Claude Code](https://code.claude.com) installed
- [`jq`](https://jqlang.github.io/jq/) for JSON parsing
- macOS or Linux (Windows works via Git Bash)

## Installation

### 1. Install jq (if not already installed)

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq
```

### 2. Copy the script

```bash
cp ultimate-timer.sh ~/.claude/ultimate-timer.sh
chmod +x ~/.claude/ultimate-timer.sh
```

### 3. Configure Claude Code

Add the `statusLine` field to `~/.claude/settings.json`. Merge with existing settings — don't overwrite:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/ultimate-timer.sh"
  }
}
```

### 4. Restart Claude Code

Open a new `claude` session. The status line appears at the bottom after your first message.

## Testing

Test with mock JSON without starting a real session:

```bash
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/Users/you/project"},"context_window":{"used_percentage":25},"exceeds_200k_tokens":false,"session_id":"test","cost":{"total_duration_ms":3600000,"total_api_duration_ms":300000,"total_cost_usd":0},"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'$(($(date +%s) + 7200))'},"seven_day":{"used_percentage":5}},"version":"1.0.80"}' | bash ~/.claude/ultimate-timer.sh
```

## Performance

- **Git branch** cached per-repo with 5-second TTL (avoids lag in large repos)
- **Daily file cleanup** runs once per day (removes files older than 30 days)
- **Atomic writes** via `mktemp` (no race conditions between concurrent sessions)
- **Single jq call** computes merged + wall + API totals in one pass
- Uses `printf '%b'` for reliable escape handling across shells

## Known Limitations

- `end` only updates on assistant messages — idle tail time is trimmed (this is a feature: it makes "Today" more honest)
- Overnight sessions: interval spans midnight, counted under the day `start` is in
- Git branch cached per-repo with 5s TTL (briefly stale after switching)
- `disableAllHooks` in settings.json also disables the status line
- Status line temporarily hides during autocomplete, help menu, and permission prompts

## Maintenance

| Action | Command |
|---|---|
| View today's sessions | `cat ~/.claude/timer-daily-$(date +%Y-%m-%d).json \| jq .` |
| Reset today | `rm ~/.claude/timer-daily-$(date +%Y-%m-%d).json` |
| Reset all history | `rm ~/.claude/timer-daily-*.json` |
| Disable status line | Remove `"statusLine"` from `~/.claude/settings.json` |
| Uninstall | `rm ~/.claude/ultimate-timer.sh ~/.claude/timer-daily-*.json` |

## Troubleshooting

| Issue | Fix |
|---|---|
| No status line visible | Check `~/.claude/settings.json` has `statusLine`, restart Claude Code |
| "statusline skipped" | Accept workspace trust dialog, then restart |
| Blank status line | Script errored. Test with mock JSON above. Run `claude --debug`. |
| Shows `--` or empty values | Normal before first API response |
| `jq: command not found` | `brew install jq` (macOS) or `apt install jq` (Linux) |
| `Permission denied` | `chmod +x ~/.claude/ultimate-timer.sh` |
| `disableAllHooks` is true | Also disables status line. Set to `false` or remove. |
| Git branch wrong | `rm /tmp/statusline-git-cache-*` to clear cache |
| Today seems low | `end` only updates on messages — idle time at end of session is trimmed |
| Wall > Today | Working correctly — overlapping sessions were deduplicated |

## Reference

- [Official Claude Code Status Line docs](https://code.claude.com/docs/en/statusline)
- [Available JSON fields](https://code.claude.com/docs/en/statusline#available-data)
- [Multi-line display](https://code.claude.com/docs/en/statusline#display-multiple-lines)
- [Caching best practices](https://code.claude.com/docs/en/statusline#cache-expensive-operations)
