# Claude Code Ultimate Status Line Timer

A multi-line status bar for [Claude Code](https://code.claude.com) that tracks session time, daily totals, weekly totals, and billing info across all terminals and sessions.

## What It Looks Like

```
[Opus] 📁 my-project | 🌿 main | Session: 01h 23m 45s (API: 12m 34s)
████░░░░░░ 42% ctx | #3 | Today: 04h 56m | Week: 12h 34m | 5h: 23% 7d: 41%
```

**Subscription users** see rate limit usage:
```
[Opus] 📁 counter | 🌿 main | Session: 00h 45m 12s (API: 05m 30s)
██░░░░░░░░ 18% ctx | #2 | Today: 02h 10m | Week: 08h 45m | 5h: 15% 7d: 32%
```

**API users** see daily cost instead:
```
[Sonnet] 📁 api-project | Session: 00h 30m 00s (API: 08m 15s)
███████░░░ 75% ctx | #1 | Today: 00h 30m | Week: 02h 15m | Cost: $2.47
```

## What Each Field Means

| Field | Description |
|---|---|
| `[Model]` | Current Claude model (Opus, Sonnet, etc.) |
| 📁 `dir` | Current working directory name |
| 🌿 `branch` | Git branch (cached per-repo, refreshes every 5s) |
| `Session: XXh XXm XXs` | Wall-clock time since this Claude Code session started |
| `(API: XXm XXs)` | Time Claude spent actively processing requests |
| `██░░ XX% ctx` | Context window usage with color coding |
| `#N` | Number of unique sessions tracked today |
| `Today: XXh XXm` | Sum of all sessions today (resets at midnight) |
| `Week: XXh XXm` | Rolling 7-day total across all sessions |
| `5h: XX%` / `7d: XX%` | Rate limit usage (Pro/Max subscription plans) |
| `Cost: $X.XX` | Daily cost total (API users only) |

### Context Bar Colors

| Color | Range | Meaning |
|---|---|---|
| Green | 0-69% | Plenty of context remaining |
| Yellow | 70-89% | Getting full |
| Red | 90-100% | Nearly exhausted |

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
| `rate_limits.five_hour.used_percentage` | 5-hour rate limit (subscription only) |
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

## Important: What "Time" Means

`Session`, `Today`, and `Week` measure **wall-clock time** — how long sessions have been open, including idle time. If you leave Claude Code open during lunch, that time counts.

The `(API: Xm Xs)` metric measures **active processing time** — only the time Claude spent thinking and responding to your requests. This is closer to "actual usage."

| Scenario | Session time | API time |
|---|---|---|
| Active coding for 1 hour | ~1h | ~15-30m (depends on request frequency) |
| Open but idle for 2 hours | ~2h | ~0m |
| Overnight (left open 8 hours) | ~8h | Same as last update |

## Testing

Test the script with mock JSON without starting a real session:

```bash
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/Users/you/project"},"context_window":{"used_percentage":25},"session_id":"test","cost":{"total_duration_ms":3600000,"total_api_duration_ms":300000,"total_cost_usd":0},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":5}},"version":"1.0.80"}' | bash ~/.claude/ultimate-timer.sh
```

Expected output:
```
[Opus] 📁 project | Session: 01h 00m 00s (API: 05m 00s)
██░░░░░░░░ 25% ctx | #1 | Today: 01h 00m | Week: 01h 00m | 5h: 10% 7d: 5%
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
| Shows `--` or empty values | Normal before first API response; values populate after first message |
| `jq: command not found` | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |
| `Permission denied` | Run `chmod +x ~/.claude/ultimate-timer.sh` |
| Git branch wrong/stale | Cache refreshes every 5s; wait or `rm /tmp/statusline-git-cache-*` |
| Today/Week values seem high | Wall-clock time includes idle; check `(API: Xm Xs)` for active usage |

## Reference

- [Official Claude Code Status Line docs](https://code.claude.com/docs/en/statusline)
- [Available JSON fields](https://code.claude.com/docs/en/statusline#available-data)
- [Caching best practices](https://code.claude.com/docs/en/statusline#cache-expensive-operations)
