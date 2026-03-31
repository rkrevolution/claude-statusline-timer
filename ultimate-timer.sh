#!/bin/bash
# =============================================================================
# Claude Code Ultimate Status Line Timer
# =============================================================================
#
# Multi-line status bar for Claude Code that tracks session, daily, and weekly
# usage across all terminals and sessions.
#
# DISPLAY FORMAT (2 lines):
#   [Opus] 📁 my-project | 🌿 main | Session: 01h 23m 45s (API: 12m 34s)
#   ████░░░░░░ 42% ctx | #3 | Today: 04h 56m | Week: 12h 34m | 5h: 23% 7d: 41%
#
# WHAT EACH FIELD MEANS:
#   [Model]              — Current Claude model (Opus, Sonnet, etc.)
#   📁 dir               — Current working directory name
#   🌿 branch            — Git branch (cached, updates every 5s per repo)
#   Session: XXh XXm XXs — Wall-clock time since this Claude Code session started
#   (API: XXm XXs)       — Active API time (Claude actually thinking/responding)
#   ██░░ XX% ctx         — Context window usage (green <70%, yellow 70-89%, red 90%+)
#   #N                   — Number of unique sessions tracked today
#   Today: XXh XXm       — Daily total across ALL sessions (resets at midnight)
#   Week: XXh XXm        — Rolling 7-day total across all sessions
#   5h: XX% / 7d: XX%    — Rate limit usage (subscription users: Pro/Max)
#   Cost: $X.XX          — Daily cost (API users, shown when no rate limits)
#
# IMPORTANT — WHAT "TIME" MEANS:
#   Session/Today/Week use total_duration_ms = wall-clock time since session
#   start. This includes idle time (lunch breaks, overnight). It does NOT
#   measure active coding time. The (API: Xm Xs) metric shows actual time
#   Claude spent processing requests — closer to "active usage."
#
# HOW AGGREGATION WORKS:
#   Claude sends total_duration_ms which is cumulative per session. Each time
#   this script runs, it OVERWRITES (not adds) the value for the current
#   session_id in a daily JSON file. Summing all entries gives the true total.
#
#   Daily files: ~/.claude/timer-daily-YYYY-MM-DD.json
#   Format: {"session_id_1": {"ms": 45000, "api_ms": 2300, "cost": 0.12}, ...}
#
#   Files older than 30 days are auto-cleaned on each run.
#
# KNOWN LIMITATIONS:
#   - Wall-clock, not active time (idle sessions inflate totals)
#   - Overnight sessions: full duration stored under the day the script last ran
#   - Value updates only after assistant messages; closing mid-prompt loses ~1 update
#   - Git branch cached per-repo with 5s TTL (briefly stale after switching)
#
# SETUP:
#   1. Save to ~/.claude/ultimate-timer.sh
#   2. chmod +x ~/.claude/ultimate-timer.sh
#   3. Add to ~/.claude/settings.json:
#      { "statusLine": {"type": "command", "command": "bash ~/.claude/ultimate-timer.sh"} }
#   4. Requires: jq (brew install jq)
#
# MAINTENANCE:
#   Reset today:    rm ~/.claude/timer-daily-$(date +%Y-%m-%d).json
#   Reset all:      rm ~/.claude/timer-daily-*.json
#   Disable:        Remove "statusLine" from settings.json
#   View sessions:  cat ~/.claude/timer-daily-$(date +%Y-%m-%d).json | jq .
#
# REFERENCE: https://code.claude.com/docs/en/statusline
# =============================================================================

# -----------------------------------------------------------------------------
# 1. READ JSON FROM STDIN
# -----------------------------------------------------------------------------
# Claude Code pipes session data as JSON to stdin on every update.
# Updates trigger after each assistant message, debounced at 300ms.
input=$(cat)

# -----------------------------------------------------------------------------
# 2. EXTRACT SESSION DATA
# -----------------------------------------------------------------------------
# All fields use "// 0" or "// empty" for null safety (official best practice).
# See: https://code.claude.com/docs/en/statusline#available-data

MODEL=$(echo "$input" | jq -r '.model.display_name')           # e.g. "Opus"
DIR=$(echo "$input" | jq -r '.workspace.current_dir')          # e.g. "/Users/spark/project"
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)  # integer %
session_id=$(echo "$input" | jq -r '.session_id // empty')     # unique per Claude process
session_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')      # wall-clock ms (cumulative)
api_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')      # API-only ms (cumulative)
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')       # USD (cumulative)

# -----------------------------------------------------------------------------
# 3. SESSION ELAPSED TIME
# -----------------------------------------------------------------------------
# total_duration_ms = wall-clock time since session started (includes idle)
# total_api_duration_ms = time Claude spent processing (active usage)
session_s=$(( session_ms / 1000 ))
sh=$(( session_s / 3600 ))
sm=$(( (session_s % 3600) / 60 ))
ss=$(( session_s % 60 ))

api_s=$(( api_ms / 1000 ))
am=$(( api_s / 60 ))
as=$(( api_s % 60 ))

# -----------------------------------------------------------------------------
# 4. DAILY AGGREGATION
# -----------------------------------------------------------------------------
# Store the LATEST cumulative value per session_id (not additive).
# Since total_duration_ms grows over the session's lifetime, we overwrite
# each session's entry. Summing all entries = true daily total.
#
# Atomic write: mktemp creates a unique temp file per invocation, avoiding
# race conditions when multiple sessions update simultaneously.

today=$(date +%Y-%m-%d)
daily_file="$HOME/.claude/timer-daily-$today.json"

if [ -n "$session_id" ] && [ "$session_ms" != "0" ]; then
  if [ -f "$daily_file" ]; then
    # Overwrite this session's entry with latest cumulative values
    tmpfile=$(mktemp /tmp/claude-timer-XXXXXX.json)
    if jq --arg sid "$session_id" \
         --argjson ms "$session_ms" \
         --argjson api "$api_ms" \
         --argjson cost "$session_cost" \
         '.[$sid] = {"ms": $ms, "api_ms": $api, "cost": $cost}' \
         "$daily_file" > "$tmpfile" 2>/dev/null; then
      mv "$tmpfile" "$daily_file"
    else
      rm -f "$tmpfile"
    fi
  else
    # First session of the day — create the file
    echo "{\"$session_id\":{\"ms\":$session_ms,\"api_ms\":$api_ms,\"cost\":$session_cost}}" > "$daily_file"
  fi
fi

# Sum all sessions for today's totals
if [ -f "$daily_file" ]; then
  daily_ms=$(jq '[.[].ms] | add // 0' "$daily_file" 2>/dev/null || echo 0)
  daily_cost=$(jq '[.[].cost] | add // 0' "$daily_file" 2>/dev/null || echo 0)
else
  daily_ms=0
  daily_cost=0
fi

daily_s=$(( ${daily_ms:-0} / 1000 ))
dh=$(( daily_s / 3600 ))
dm=$(( (daily_s % 3600) / 60 ))

# -----------------------------------------------------------------------------
# 5. WEEKLY AGGREGATION (rolling 7 days)
# -----------------------------------------------------------------------------
# Reads daily files for the past 7 days and sums them.
# Uses macOS `date -v` with GNU/Linux `date -d` fallback.

week_ms=0
for i in {0..6}; do
  wdate=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-$i days" +%Y-%m-%d 2>/dev/null)
  wfile="$HOME/.claude/timer-daily-${wdate}.json"
  if [ -f "$wfile" ]; then
    w=$(jq '[.[].ms] | add // 0' "$wfile" 2>/dev/null || echo 0)
    week_ms=$(( week_ms + ${w:-0} ))
  fi
done

week_s=$(( week_ms / 1000 ))
wh=$(( week_s / 3600 ))
wm=$(( (week_s % 3600) / 60 ))

# -----------------------------------------------------------------------------
# 6. CONTEXT WINDOW PROGRESS BAR
# -----------------------------------------------------------------------------
# Color thresholds match the official multi-line example:
#   Green  (<70%)  — plenty of room
#   Yellow (70-89%) — getting full
#   Red    (90%+)  — nearly exhausted

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

if [ "${PCT:-0}" -ge 90 ] 2>/dev/null; then BAR_COLOR="$RED"
elif [ "${PCT:-0}" -ge 70 ] 2>/dev/null; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

BAR_WIDTH=10
FILLED=$(( ${PCT:-0} * BAR_WIDTH / 100 ))
EMPTY=$(( BAR_WIDTH - FILLED ))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && BAR="${FILL// /█}"
[ "$EMPTY" -gt 0 ] && printf -v PAD "%${EMPTY}s" && BAR="${BAR}${PAD// /░}"

# -----------------------------------------------------------------------------
# 7. GIT BRANCH (cached per-repo for performance)
# -----------------------------------------------------------------------------
# Official docs recommend caching git operations to avoid lag in large repos.
# Cache is keyed by directory so multiple repos don't cross-contaminate.
# See: https://code.claude.com/docs/en/statusline#cache-expensive-operations

DIR_HASH=$(echo "$DIR" | md5 2>/dev/null || echo "$DIR" | md5sum 2>/dev/null | cut -d' ' -f1)
CACHE_FILE="/tmp/statusline-git-cache-${DIR_HASH}"
CACHE_MAX_AGE=5  # seconds

cache_stale=true
if [ -f "$CACHE_FILE" ]; then
  # stat -f %m = macOS, stat -c %Y = Linux
  cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
  [ "$cache_age" -le "$CACHE_MAX_AGE" ] && cache_stale=false
fi

if $cache_stale; then
  BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null || echo "")
  echo "$BRANCH" > "$CACHE_FILE"
else
  BRANCH=$(cat "$CACHE_FILE")
fi

BRANCH_STR=""
[ -n "$BRANCH" ] && BRANCH_STR=" | 🌿 $BRANCH"

# -----------------------------------------------------------------------------
# 8. RATE LIMITS & COST
# -----------------------------------------------------------------------------
# Subscription users (Pro/Max) get rate_limits after first API response.
# API users get cost instead. We show whichever is available.
# "// empty" produces no output when the field is absent (official pattern).

FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SEVEN_D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Build the billing info string: rate limits for subscribers, cost for API users
BILLING=""
if [ -n "$FIVE_H" ] || [ -n "$SEVEN_D" ]; then
  # Subscription: show rate limit percentages
  [ -n "$FIVE_H" ] && BILLING="5h: $(printf '%.0f' "$FIVE_H")%"
  [ -n "$SEVEN_D" ] && BILLING="${BILLING:+$BILLING }7d: $(printf '%.0f' "$SEVEN_D")%"
else
  # API: show daily cost
  cost_fmt=$(printf '%.2f' "${daily_cost:-0}" 2>/dev/null || echo "0.00")
  BILLING="Cost: \$${cost_fmt}"
fi

# -----------------------------------------------------------------------------
# 9. SESSION COUNT
# -----------------------------------------------------------------------------
# Count how many unique sessions have been tracked today.
# Each Claude Code process gets a unique session_id.

if [ -f "$daily_file" ]; then
  session_count=$(jq 'length' "$daily_file" 2>/dev/null || echo 0)
else
  session_count=0
fi

# -----------------------------------------------------------------------------
# 10. AUTO-CLEANUP (daily files older than 30 days)
# -----------------------------------------------------------------------------
# Prevents unbounded file growth in ~/.claude/. Only runs the find once
# per day by checking a marker file.

CLEANUP_MARKER="/tmp/claude-timer-cleanup-$today"
if [ ! -f "$CLEANUP_MARKER" ]; then
  find "$HOME/.claude" -name "timer-daily-*.json" -mtime +30 -delete 2>/dev/null
  touch "$CLEANUP_MARKER"
fi

# -----------------------------------------------------------------------------
# 11. OUTPUT (multi-line)
# -----------------------------------------------------------------------------
# Line 1: Model, directory, git branch, session timer, active API time
# Line 2: Context bar, session count, daily total, weekly total, billing info
# Each echo produces a separate row in the status area.
#
# EXPECTED OUTPUT (subscription user):
#   [Opus] 📁 my-project | 🌿 main | Session: 01h 23m 45s (API: 12m 34s)
#   ████░░░░░░ 42% ctx | #3 | Today: 04h 56m | Week: 12h 34m | 5h: 23% 7d: 41%
#
# EXPECTED OUTPUT (API user):
#   [Sonnet] 📁 my-project | 🌿 main | Session: 00h 30m 00s (API: 08m 15s)
#   ███████░░░ 75% ctx | #1 | Today: 00h 30m | Week: 02h 15m | Cost: $2.47
#
# EXPECTED OUTPUT (early session, before first API response):
#   [Opus] 📁 my-project | Session: 00h 00m 00s (API: 00m 00s)
#   ░░░░░░░░░░ 0% ctx | #0 | Today: 00h 00m | Week: 00h 00m | Cost: $0.00

echo -e "${CYAN}[$MODEL]${RESET} 📁 ${DIR##*/}${BRANCH_STR} | Session: $(printf '%02dh %02dm %02ds' "$sh" "$sm" "$ss") (API: $(printf '%02dm %02ds' "$am" "$as"))"
echo -e "${BAR_COLOR}${BAR}${RESET} ${PCT:-0}% ctx | #${session_count} | Today: $(printf '%02dh %02dm' "$dh" "$dm") | Week: $(printf '%02dh %02dm' "$wh" "$wm") | ${YELLOW}${BILLING}${RESET}"
