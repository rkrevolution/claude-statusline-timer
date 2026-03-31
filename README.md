# Claude Code Ultimate Status Line Timer

A multi-line status bar for [Claude Code](https://code.claude.com) that tracks real time spent using Claude — with accurate overlap handling, daily/weekly totals, and billing info across all terminals and sessions.

---

## Quick Start (2 minutes)

```bash
# 1. Install jq (if you don't have it)
brew install jq            # macOS
# sudo apt install jq      # Linux

# 2. Copy the script
cp ultimate-timer.sh ~/.claude/ultimate-timer.sh
chmod +x ~/.claude/ultimate-timer.sh

# 3. Add to your Claude Code settings
# Open ~/.claude/settings.json and add the statusLine field:
#
#   {
#     "statusLine": {
#       "type": "command",
#       "command": "bash ~/.claude/ultimate-timer.sh"
#     }
#   }
#
# If you already have settings in that file, just add the "statusLine" key
# alongside your existing keys. Don't replace the whole file.

# 4. Start Claude Code
claude
# The status line appears at the bottom after your first message.
```

**That's it.** Everything below is reference documentation.

---

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

---

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
Result: Today = 2 hours
```

This is the most accurate answer to "how long was I using Claude today." Overlapping sessions don't inflate the number. Idle tail time gets trimmed because `end` only updates when Claude responds — so if you walk away for an hour, that hour isn't counted.

### Wall (naive sum) — "Sum of all session durations"

Using the same example:
```
sess-A duration: 2:00 - 1:00 = 1 hour
sess-B duration: 3:00 - 1:30 = 1.5 hours
Wall = 2.5 hours
```

This is the raw sum without any deduplication. **If Wall > Today, overlapping sessions were deduplicated.** If they match, you had no concurrent sessions. Useful as a sanity check to verify the merge is working.

### Active (API time) — "How long was Claude actually working?"

Sum of `total_api_duration_ms` across all sessions. This is only the time Claude spent thinking and generating responses — not waiting for you to type.

```
sess-A api_ms: 900000 (15 minutes)
sess-B api_ms: 600000 (10 minutes)
Active = 25 minutes
```

### At a Glance

| Scenario | Today (merged) | Wall (sum) | Active (API) |
|---|---|---|---|
| 1 session, actively coding 1hr | ~1h | ~1h | ~15-30m |
| 1 session, mostly idle 3hr | ~3h | ~3h | ~5m |
| 2 concurrent sessions, 1hr overlap | **2h** | 3h (inflated) | 25m |
| 3 sessions, all overlapping | **1h** | 3h (3x inflated) | 30m |

---

## What Each Field Means

### Line 1 — Session Info

| Field | What it tells you |
|---|---|
| `[Opus]` | Which Claude model you're using |
| 📁 `my-project` | Your current working directory |
| 🌿 `main` | Your git branch (cached per-repo, refreshes every 5s) |
| `Session: 01h 23m 45s` | How long this specific Claude Code window has been open |
| `(API: 12m 34s)` | How long Claude spent actively processing in this session |

### Line 2 — Daily Usage & Limits

| Field | What it tells you |
|---|---|
| `████░░░░░░ 42% ctx` | How full your context window is. Green = fine, yellow = filling, red = almost full. |
| `!! >200k` | Warning flag when your tokens exceed 200k. Only appears when triggered. |
| `#3` | How many Claude Code sessions you've opened today |
| `Today: 02h 00m` | Real time you spent with Claude today. Overlapping sessions deduplicated. Idle tail trimmed. |
| `Wall: 03h 00m` | Raw sum of all session durations. Compare with Today to see if deduplication happened. |
| `Active: 25m` | Total time Claude was actually thinking/responding across all sessions today. |
| `Week: 12h 34m` | Rolling 7-day total of real time with Claude (merged intervals). |
| `Limit (5hr): 68% used` | How much of your 5-hour rate limit you've consumed. Watch this — it's what throttles you. |
| `resets in 1h 51m` | When your 5-hour window opens back up. Plan breaks around this. |
| `Limit (7day): 4% used` | How much of your weekly rate limit you've consumed. |
| `Cost: $2.47` | Daily cost total. Only shown for API users (not subscription). |

### Rate Limits (Subscription Users Only)

- **Limit (5hr)** is your short-term budget. When it hits ~100%, Claude rate-limits you until the window rolls forward.
- **Limit (7day)** is your weekly budget. Only matters for sustained heavy usage over multiple days.
- **resets in Xh Xm** tells you exactly when the 5-hour window recovers so you can plan.
- These fields only appear after your first message in a session (Claude sends them with the first API response).

---

## Data Flow

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
┌─────────────────────────────────────────────────────────────��
│  ULTIMATE-TIMER.SH                                           │
│                                                              │
│  1. Read JSON from stdin                                     │
│  2. Extract: session_id, durations, cost, context %, limits  │
│  3. Record timestamps locally:                               │
│     - First time seeing session_id → store start = now       │
│     - Every update → overwrite end = now                     │
│  4. Write to daily file (atomic via mktemp + mv)             │
│  5. Merge overlapping [start,end] intervals for Today total  │
│  6. Sum merged intervals across 7 days for Week total        │
│  7. Format and output two lines to stdout                    │
└──────────────────────────┬──────────────────────────────────┘
                           │ stdout (two lines of formatted text)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  CLAUDE CODE STATUS BAR (bottom of terminal)                 │
│                                                              │
│  [Opus] 📁 my-project | 🌿 main | Session: 01h 23m 45s ... │
│  ████░░░░░░ 42% ctx | #2 | Today: 02h 00m | Wall: 03h ...  │
└─────────────────────────────────────────────────────────────┘
```

### What Gets Stored Locally

One JSON file per day at `~/.claude/timer-daily-YYYY-MM-DD.json`:

```json
{
  "abc123": {
    "start": 1711926000,
    "end":   1711933200,
    "api_ms": 745000,
    "cost": 1.25
  },
  "def456": {
    "start": 1711929600,
    "end":   1711936800,
    "api_ms": 300000,
    "cost": 0.80
  }
}
```

- `start` — Unix timestamp, set once when we first see this session_id
- `end` — Unix timestamp, updated to `now` every time the script runs
- `api_ms` — Claude's cumulative API processing time (from Claude's JSON)
- `cost` — Claude's cumulative session cost (from Claude's JSON)

These are **our own timestamps**, not Claude's `total_duration_ms`. This is what makes accurate interval merging possible.

Files older than 30 days are automatically cleaned up.

---

## Installation (Detailed)

### 1. Install jq

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# Verify
jq --version
```

### 2. Copy the script

If you cloned this repo:
```bash
cp ultimate-timer.sh ~/.claude/ultimate-timer.sh
chmod +x ~/.claude/ultimate-timer.sh
```

Or copy it directly:
```bash
curl -o ~/.claude/ultimate-timer.sh https://raw.githubusercontent.com/rkrevolution/claude-statusline-timer/main/ultimate-timer.sh
chmod +x ~/.claude/ultimate-timer.sh
```

### 3. Configure Claude Code

Edit `~/.claude/settings.json`. If the file already has content, add the `statusLine` key alongside your existing settings:

```json
{
  "existingSetting": true,
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/ultimate-timer.sh"
  }
}
```

If the file doesn't exist, create it with just the statusLine config.

### 4. Start (or restart) Claude Code

```bash
claude
```

The status line appears at the bottom of the terminal after your first message to Claude.

---

## Testing

Test the script with mock JSON without starting a real session:

```bash
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/Users/you/project"},"context_window":{"used_percentage":25},"exceeds_200k_tokens":false,"session_id":"test","cost":{"total_duration_ms":3600000,"total_api_duration_ms":300000,"total_cost_usd":0},"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'$(($(date +%s) + 7200))'},"seven_day":{"used_percentage":5}},"version":"1.0.80"}' | bash ~/.claude/ultimate-timer.sh
```

You should see two formatted lines with colors in your terminal.

---

## Maintenance

| What you want to do | Command |
|---|---|
| See today's raw session data | `cat ~/.claude/timer-daily-$(date +%Y-%m-%d).json \| jq .` |
| Reset today's tracking | `rm ~/.claude/timer-daily-$(date +%Y-%m-%d).json` |
| Reset all tracking history | `rm ~/.claude/timer-daily-*.json` |
| Temporarily disable | Remove `"statusLine"` from `~/.claude/settings.json` |
| Fully uninstall | `rm ~/.claude/ultimate-timer.sh ~/.claude/timer-daily-*.json` and remove `statusLine` from settings |

---

## Performance Notes

- **Git branch** cached per-repo with 5-second TTL (avoids lag in large repos)
- **Daily file cleanup** runs once per day, removes files older than 30 days
- **Atomic writes** via `mktemp` — no race conditions between concurrent sessions
- **Single jq call** computes merged + wall + API totals in one pass
- Uses `printf '%b'` for reliable escape handling across shells
- Status line does not consume API tokens — it runs locally

---

## Known Limitations

| Limitation | Why it's OK |
|---|---|
| `end` only updates on assistant messages | Idle tail time is trimmed — makes "Today" more honest, not less |
| Overnight sessions span midnight | Counted under the day `start` is in. Doesn't affect accuracy. |
| Git branch has 5s cache | Briefly stale after switching branches. Clear with `rm /tmp/statusline-git-cache-*` |
| `disableAllHooks` in settings | Also disables status line. Set to `false` to re-enable. |
| Hides during autocomplete/help | Built-in Claude Code behavior, returns automatically. |

---

## Troubleshooting

| Problem | Solution |
|---|---|
| No status line visible | Verify `~/.claude/settings.json` has the `statusLine` config. Restart Claude Code. |
| "statusline skipped" notification | Accept the workspace trust dialog when prompted, then restart. |
| Blank status line | Script may have errored. Test with mock JSON (see Testing section). Run `claude --debug` for details. |
| Shows `--` or empty values | Normal before first API response. Send a message and it populates. |
| `jq: command not found` | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |
| `Permission denied` | Run `chmod +x ~/.claude/ultimate-timer.sh` |
| `disableAllHooks` is set to true | That also disables the status line. Remove it or set to `false`. |
| Git branch shows wrong repo | Cache is per-repo. Clear with `rm /tmp/statusline-git-cache-*` |
| Today seems lower than expected | That's the merged interval — idle tail time is trimmed. Check Wall for raw sum. |
| Wall is higher than Today | Working correctly — overlapping sessions were deduplicated. |
| Rate limits not showing | Only appears for Claude.ai subscribers (Pro/Max) after first API response. API users see Cost instead. |

---

## Reference

- [Official Claude Code Status Line docs](https://code.claude.com/docs/en/statusline)
- [Available JSON fields](https://code.claude.com/docs/en/statusline#available-data)
- [Multi-line display](https://code.claude.com/docs/en/statusline#display-multiple-lines)
- [Caching best practices](https://code.claude.com/docs/en/statusline#cache-expensive-operations)
