# Claude Code Ultimate Status Line Timer

A multi-line status bar for [Claude Code](https://code.claude.com) that tracks session time, daily totals, weekly totals, and billing info across all terminals and sessions.

## What It Looks Like

**Subscription users** (Pro/Max) see rate limit usage with reset countdown:
```
[Opus] 📁 my-project | 🌿 main | Session: 01h 23m 45s (API: 12m 34s)
████░░░░░░ 42% ctx | #3 | Today: 04h 56m | Week: 12h 34m | Limit (5hr): 68% used, resets in 1h 51m | Limit (7day): 4% used
```

**API users** see daily cost instead:
```
[Sonnet] 📁 api-project | Session: 00h 30m 00s (API: 08m 15s)
███████░░░ 75% ctx | #1 | Today: 00h 30m | Week: 02h 15m | Cost: $2.47
```

**Heavy context usage** triggers a warning:
```
[Opus] 📁 big-project | 🌿 main | Session: 02h 10m 00s (API: 25m 00s)
█████████░ 92% ctx !! >200k | #2 | Today: 03h 00m | Week: 15h 00m | Limit (5hr): 65% used, resets in 1h 45m | Limit (7day): 80% used
```

## What Each Field Means

### Line 1 — Session Info

| Field | Description |
|---|---|
| `[Opus]` | Current Claude model name |
| 📁 `my-project` | Current working directory |
| 🌿 `main` | Git branch (cached per-repo, refreshes every 5s) |
| `Session: 01h 23m 45s` | Wall-clock time since this Claude Code session started. Includes idle time. |
| `(API: 12m 34s)` | Time Claude spent actively thinking/responding. This is your real "active usage." |

### Line 2 — Usage & Limits

| Field | Description |
|---|---|
| `████░░░░░░ 42% ctx` | Context window usage. Green (<70%), yellow (70-89%), red (90%+). |
| `!! >200k` | Warning when total tokens exceed 200k (only shown when triggered). |
| `#3` | Number of unique Claude Code sessions tracked today. |
| `Today: 04h 56m` | Sum of all sessions today across all terminals/windows. Resets at midnight. |
| `Week: 12h 34m` | Rolling 7-day total across all sessions. |
| `Limit (5hr): 68% used` | How much of your 5-hour rolling rate limit you've consumed (subscription only). |
| `resets in 1h 51m` | Time until the 5-hour window resets and your allowance recovers. |
| `Limit (7day): 4% used` | How much of your 7-day rolling rate limit you've consumed (subscription only). |
| `Cost: $2.47` | Daily cost total — shown for API users instead of rate limits. |

### Understanding Rate Limits (Subscription Users)

- **Limit (5hr)** is your short-term budget. This is what throttles you during heavy use. When it approaches 100%, Claude will rate-limit you until the window rolls forward. Watch this number day-to-day.
- **Limit (7day)** is your weekly budget. At low percentages you have plenty of room. This matters for sustained heavy usage across multiple days.
- **resets in Xh Xm** tells you exactly when the 5-hour window opens up again, so you can plan breaks or switch to a lighter model.

### Understanding Time Metrics

- **Session time** = wall-clock time (includes idle, lunch breaks, leaving it open overnight)
- **API time** = only time Claude was actively processing your requests
- **Today/Week** = wall-clock totals aggregated across all sessions

| Scenario | Session time | API time |
|---|---|---|
| Active coding for 1 hour | ~1h | ~15-30m |
| Open but idle for 2 hours | ~2h | ~0m |
| Overnight (left open 8 hours) | ~8h | Same as last update |

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

# Verify
jq --version
```

### 2. Copy the script

```bash
cp ultimate-timer.sh ~/.claude/ultimate-timer.sh
chmod +x ~/.claude/ultimate-timer.sh
```

### 3. Configure Claude Code

Add the `statusLine` field to `~/.claude/settings.json`. If you have existing settings, merge it in — don't overwrite the file:

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

## How It Works

### Data Source

Claude Code pipes JSON session data to the status line command via stdin after each assistant message ([official docs](https://code.claude.com/docs/en/statusline)). Key fields used:

| JSON Field | What It Provides |
|---|---|
| `cost.total_duration_ms` | Wall-clock time since session start (cumulative) |
| `cost.total_api_duration_ms` | Time spent on API calls only (cumulative) |
| `cost.total_cost_usd` | Session cost in USD (cumulative) |
| `session_id` | Unique identifier per Claude Code process |
| `context_window.used_percentage` | Context window usage (0-100) |
| `exceeds_200k_tokens` | Whether tokens exceed 200k (fixed threshold) |
| `rate_limits.five_hour.used_percentage` | 5-hour rate limit (subscription only) |
| `rate_limits.five_hour.resets_at` | Unix epoch when 5-hour window resets |
| `rate_limits.seven_day.used_percentage` | 7-day rate limit (subscription only) |

### Aggregation

Each session's `total_duration_ms` is cumulative (it grows over the session's lifetime). The script **overwrites** (not adds) each session's entry in a daily JSON file keyed by `session_id`. Summing all entries gives the true daily total.

```
~/.claude/timer-daily-2026-03-31.json
{
  "abc123": {"ms": 4925000, "api_ms": 745000, "cost": 0},
  "def456": {"ms": 1800000, "api_ms": 300000, "cost": 0}
}
```

### Update Frequency

- Triggers after each assistant message
- Debounced at 300ms (rapid updates batch together)
- If a new update fires while the script is running, the old one is cancelled

### Performance

- **Git branch** is cached per-repo with a 5-second TTL to avoid lag in large repositories
- **Daily file cleanup** runs once per day, removing files older than 30 days
- **Atomic writes** use `mktemp` to avoid race conditions between concurrent sessions
- Uses `printf '%b'` for reliable escape sequence handling across shells

### Known Limitations

- Wall-clock, not active time (idle sessions inflate totals; use API time for real usage)
- Overnight sessions: full duration stored under the day the script last ran
- Value updates only after assistant messages; closing mid-prompt loses ~1 update
- Git branch cached per-repo with 5s TTL (briefly stale after switching)
- `disableAllHooks` in settings.json also disables the status line

## Testing

Test the script with mock JSON without starting a real session:

```bash
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/Users/you/project"},"context_window":{"used_percentage":25},"exceeds_200k_tokens":false,"session_id":"test","cost":{"total_duration_ms":3600000,"total_api_duration_ms":300000,"total_cost_usd":0},"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'$(($(date +%s) + 7200))'},"seven_day":{"used_percentage":5}},"version":"1.0.80"}' | bash ~/.claude/ultimate-timer.sh
```

Expected output:
```
[Opus] 📁 project | Session: 01h 00m 00s (API: 05m 00s)
██░░░░░░░░ 25% ctx | #1 | Today: 01h 00m | Week: 01h 00m | Limit (5hr): 10% used, resets in 2h 0m | Limit (7day): 5% used
```

## Maintenance

| Action | Command |
|---|---|
| View today's sessions | `cat ~/.claude/timer-daily-$(date +%Y-%m-%d).json \| jq .` |
| Reset today | `rm ~/.claude/timer-daily-$(date +%Y-%m-%d).json` |
| Reset all history | `rm ~/.claude/timer-daily-*.json` |
| Disable status line | Remove `"statusLine"` from `~/.claude/settings.json` |
| Uninstall | `rm ~/.claude/ultimate-timer.sh ~/.claude/timer-daily-*.json` |

Old daily files (30+ days) are automatically deleted.

## Troubleshooting

| Issue | Fix |
|---|---|
| No status line visible | Check `~/.claude/settings.json` has the `statusLine` config, restart Claude Code |
| "statusline skipped" message | Accept the workspace trust dialog, then restart Claude Code |
| Blank status line | Script may have errored. Test with mock JSON above. Run `claude --debug` for details. |
| Shows `--` or empty values | Normal before first API response; values populate after first message |
| `jq: command not found` | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |
| `Permission denied` | Run `chmod +x ~/.claude/ultimate-timer.sh` |
| `disableAllHooks` is true | That also disables status line. Set to `false` or remove it. |
| Git branch wrong/stale | Cache refreshes every 5s per-repo. Clear with `rm /tmp/statusline-git-cache-*` |
| Today/Week values seem high | Wall-clock time includes idle; check `(API: Xm Xs)` for active usage |
| Narrow terminal truncation | System notifications share the status row and may clip your output |

## Reference

- [Official Claude Code Status Line docs](https://code.claude.com/docs/en/statusline)
- [Available JSON fields](https://code.claude.com/docs/en/statusline#available-data)
- [Caching best practices](https://code.claude.com/docs/en/statusline#cache-expensive-operations)
