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
#   ████░░░░░░ 42% ctx | #3 | Today: 02h 45m (active: 25m) | Week: 12h 34m | Limit (5hr): 68% used, resets in 1h 51m | Limit (7day): 4% used
#
# WHAT EACH FIELD MEANS:
#   [Model]              — Current Claude model (Opus, Sonnet, etc.)
#   📁 dir               — Current working directory name
#   🌿 branch            — Git branch (cached, updates every 5s per repo)
#   Session: XXh XXm XXs — Wall-clock time since this Claude Code session started
#   (API: XXm XXs)       — Active API time (Claude actually thinking/responding)
#   ██░░ XX% ctx         — Context window usage (green <70%, yellow 70-89%, red 90%+)
#                          Adds "!! >200k" warning when exceeds_200k_tokens is true
#   #N                   — Number of unique sessions tracked today
#   Today: XXh XXm       — Real time at desk with Claude (merged intervals,
#                          no double-counting overlapping sessions)
#   Wall: XXh XXm        — Naive sum of all session durations (for comparison;
#                          if Wall > Today, overlapping sessions were deduplicated)
#   Active: XXm          — Sum of API processing time (Claude actually working)
#   Week: XXh XXm        — Rolling 7-day total (merged intervals)
#   Limit (5hr): XX% used, resets in Xh Xm — 5-hour rolling rate limit (subscription)
#   Limit (7day): XX% used                — 7-day rolling rate limit (subscription)
#   Cost: $X.XX          — Daily cost (API users, shown when no rate limits)
#
# HOW TIME TRACKING WORKS:
#   Each time this script runs (after every assistant message), we record:
#   - "start": the first time we saw this session_id (set once, never changes)
#   - "end": the current time (updated every run)
#   - "api_ms": Claude's cumulative API processing time
#
#   "Today" is computed by merging overlapping [start, end] intervals across
#   all sessions so concurrent windows don't inflate the number. This gives
#   you the actual time you were sitting with Claude open and active.
#
#   Because "end" only updates when Claude responds, idle time at the end
#   of a session naturally gets trimmed — making the number even more honest.
#
# DAILY FILE FORMAT:
#   ~/.claude/timer-daily-YYYY-MM-DD.json
#   {
#     "session_id_1": {"start": 1711926000, "end": 1711933200, "api_ms": 900000, "cost": 1.25},
#     "session_id_2": {"start": 1711929600, "end": 1711936800, "api_ms": 600000, "cost": 0.80}
#   }
#
#   Files older than 30 days are auto-cleaned on each run.
#
# KNOWN LIMITATIONS:
#   - "end" only updates on assistant messages; idle tail time is trimmed (a feature)
#   - Overnight sessions: interval spans midnight, counted under whichever day "start" is in
#   - Git branch cached per-repo with 5s TTL (briefly stale after switching)
#   - disableAllHooks in settings.json also disables the status line
#
# SETUP:
#   1. Save to ~/.claude/ultimate-timer.sh
#   2. chmod +x ~/.claude/ultimate-timer.sh
#   3. Add to ~/.claude/settings.json:
#      { "statusLine": {"type": "command", "command": "bash ~/.claude/ultimate-timer.sh"} }
#   4. Requires: jq (brew install jq)
#
# TROUBLESHOOTING:
#   - No status line? Check chmod +x, check settings.json, restart Claude Code
#   - "statusline skipped"? Accept workspace trust dialog, then restart
#   - Blank status line? Script may have errored — test with mock JSON (see README)
#   - disableAllHooks is true? That also disables status line — set to false
#   - Debug: run `claude --debug` to see exit code and stderr from first invocation
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
EXCEEDS_200K=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')              # bool
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
# 4. DAILY AGGREGATION (merged intervals)
# -----------------------------------------------------------------------------
# For each session_id we store:
#   - "start": Unix epoch when we first saw this session (set once)
#   - "end":   Unix epoch of the most recent update (now)
#   - "api_ms": Claude's cumulative API processing time
#   - "cost":   Claude's cumulative cost
#
# "Today" total is computed by merging overlapping [start, end] intervals
# across all sessions, so concurrent windows don't double-count.
#
# Atomic write: mktemp creates a unique temp file per invocation, avoiding
# race conditions when multiple sessions update simultaneously.

now=$(date +%s)
today=$(date +%Y-%m-%d)
daily_file="$HOME/.claude/timer-daily-$today.json"

if [ -n "$session_id" ] && [ "$session_ms" != "0" ]; then
  if [ -f "$daily_file" ]; then
    # Update this session: preserve "start" if it exists, always update "end"
    tmpfile=$(mktemp /tmp/claude-timer.XXXXXX)
    if jq --arg sid "$session_id" \
         --argjson now "$now" \
         --argjson api "$api_ms" \
         --argjson cost "$session_cost" \
         'if .[$sid] then
            .[$sid].end = $now | .[$sid].api_ms = $api | .[$sid].cost = $cost
          else
            .[$sid] = {"start": $now, "end": $now, "api_ms": $api, "cost": $cost}
          end' \
         "$daily_file" > "$tmpfile" 2>/dev/null; then
      mv "$tmpfile" "$daily_file"
    else
      rm -f "$tmpfile"
    fi
  else
    # First session of the day — create the file
    echo "{\"$session_id\":{\"start\":$now,\"end\":$now,\"api_ms\":$api_ms,\"cost\":$session_cost}}" > "$daily_file"
  fi
fi

# -----------------------------------------------------------------------------
# 4b. MERGE OVERLAPPING INTERVALS (for accurate daily total)
# -----------------------------------------------------------------------------
# Algorithm: sort intervals by start, then walk through merging overlaps.
# This is done entirely in jq:
#   1. Collect all [start, end] pairs
#   2. Sort by start
#   3. Merge: if next.start <= current.end, extend current.end
#   4. Sum all merged interval durations
#
# Also sum api_ms and cost (these don't need merging — they're independent).

if [ -f "$daily_file" ]; then
  read -r daily_merged daily_wall daily_api daily_cost < <(jq -r '
    # Collect intervals and totals
    [to_entries[] | .value] as $sessions |

    # Wall-clock: naive sum of each session duration (for comparison)
    ([$sessions[] | .end - .start] | add // 0) as $wall |

    # Sort intervals by start time
    [$sessions | sort_by(.start)[] | {start: .start, end: .end}] as $sorted |

    # Merge overlapping intervals
    ($sorted | reduce .[] as $iv (
      [];
      if length == 0 then [$iv]
      elif (last.end >= $iv.start) then (.[:-1] + [{start: last.start, end: ([last.end, $iv.end] | max)}])
      else . + [$iv]
      end
    )) as $merged |

    # Sum merged interval durations (seconds)
    ([$merged[] | .end - .start] | add // 0) as $merged_total |

    # Output: merged_seconds wall_seconds api_ms_total cost_total
    "\($merged_total) \($wall) \([$sessions[].api_ms] | add // 0) \([$sessions[].cost] | add // 0)"
  ' "$daily_file" 2>/dev/null || echo "0 0 0 0")
else
  daily_merged=0
  daily_wall=0
  daily_api=0
  daily_cost=0
fi

# Merged time (real time at desk, no overlap)
daily_s=${daily_merged:-0}
dh=$(( daily_s / 3600 ))
dm=$(( (daily_s % 3600) / 60 ))

# Wall-clock time (naive sum of all sessions, for comparison)
wall_s=${daily_wall:-0}
wall_h=$(( wall_s / 3600 ))
wall_m=$(( (wall_s % 3600) / 60 ))

# Active time (sum of API processing across all sessions)
daily_api_s=$(( ${daily_api:-0} / 1000 ))
dah=$(( daily_api_s / 3600 ))
dam=$(( daily_api_s % 3600 / 60 ))

# -----------------------------------------------------------------------------
# 5. WEEKLY AGGREGATION (rolling 7 days, merged intervals)
# -----------------------------------------------------------------------------
# Reads daily files for the past 7 days. Each day's file already contains
# intervals, so we sum each day's merged total.

week_s=0
for i in {0..6}; do
  wdate=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-$i days" +%Y-%m-%d 2>/dev/null)
  wfile="$HOME/.claude/timer-daily-${wdate}.json"
  if [ -f "$wfile" ]; then
    w=$(jq '
      [to_entries[] | .value] |
      [sort_by(.start)[] | {start: .start, end: .end}] |
      reduce .[] as $iv (
        [];
        if length == 0 then [$iv]
        elif (last.end >= $iv.start) then (.[:-1] + [{start: last.start, end: ([last.end, $iv.end] | max)}])
        else . + [$iv]
        end
      ) |
      [.[] | .end - .start] | add // 0
    ' "$wfile" 2>/dev/null || echo 0)
    week_s=$(( week_s + ${w:-0} ))
  fi
done

wh=$(( week_s / 3600 ))
wm=$(( (week_s % 3600) / 60 ))

# -----------------------------------------------------------------------------
# 6. CONTEXT WINDOW PROGRESS BAR
# -----------------------------------------------------------------------------
# Color thresholds match the official multi-line example:
#   Green  (<70%)  — plenty of room
#   Yellow (70-89%) — getting full
#   Red    (90%+)  — nearly exhausted
#
# exceeds_200k_tokens is a fixed threshold warning from Claude, regardless of
# actual context window size. We append a warning when true.

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

# Append 200k warning if context is massive
CTX_WARN=""
[ "$EXCEEDS_200K" = "true" ] && CTX_WARN=" ${RED}!! >200k${RESET}"

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
#
# For subscribers, also show time until 5-hour window resets using resets_at
# (Unix epoch seconds). This helps plan usage around rate limit recovery.

FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
FIVE_H_RESETS=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
SEVEN_D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
SEVEN_D_RESETS=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Remember if we've ever seen rate_limits in this day's data.
# This prevents showing misleading Cost: on session start for subscribers.
# rate_limits is absent before the first API response (per docs), so on
# first load we don't know if user is subscriber or API. Once we see it
# once, we save a marker so subsequent sessions know to wait for it.
SUBSCRIBER_MARKER="$HOME/.claude/timer-subscriber-$today"

if [ -n "$FIVE_H" ] || [ -n "$SEVEN_D" ]; then
  # We have rate_limits — user is a subscriber. Save marker.
  touch "$SUBSCRIBER_MARKER"
fi

# Build the billing info string
BILLING=""
if [ -n "$FIVE_H" ] || [ -n "$SEVEN_D" ]; then
  # Subscription: show rate limit percentages with reset countdowns
  if [ -n "$FIVE_H" ]; then
    BILLING="Limit (5hr): $(printf '%.0f' "$FIVE_H")% used"
    if [ -n "$FIVE_H_RESETS" ]; then
      remaining=$(( FIVE_H_RESETS - now ))
      if [ "$remaining" -gt 0 ]; then
        rh=$(( remaining / 3600 ))
        rm_val=$(( (remaining % 3600) / 60 ))
        if [ "$rh" -gt 0 ]; then
          BILLING="${BILLING}, resets in ${rh}h ${rm_val}m"
        else
          BILLING="${BILLING}, resets in ${rm_val}m"
        fi
      fi
    fi
  fi
  if [ -n "$SEVEN_D" ]; then
    SEVEN_D_STR="Limit (7day): $(printf '%.0f' "$SEVEN_D")% used"
    if [ -n "$SEVEN_D_RESETS" ]; then
      remaining7=$(( SEVEN_D_RESETS - now ))
      if [ "$remaining7" -gt 0 ]; then
        r7d=$(( remaining7 / 86400 ))
        r7h=$(( (remaining7 % 86400) / 3600 ))
        SEVEN_D_STR="${SEVEN_D_STR}, resets in ${r7d}d ${r7h}h"
      fi
    fi
    BILLING="${BILLING:+$BILLING | }${SEVEN_D_STR}"
  fi
elif [ -f "$SUBSCRIBER_MARKER" ]; then
  # We've seen rate_limits before today — user is a subscriber but
  # rate_limits hasn't loaded yet (before first API response).
  BILLING="Limits: loading..."
else
  # No rate_limits seen today and no marker — likely an API user.
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
# 11. FORMAT COMPACT TIME STRINGS
# -----------------------------------------------------------------------------
# Active time shown compactly: "45m" or "1h 23m" depending on duration

if [ "$dah" -gt 0 ]; then
  ACTIVE_FMT="${dah}h ${dam}m"
else
  ACTIVE_FMT="${dam}m"
fi

# -----------------------------------------------------------------------------
# 12. OUTPUT (multi-line)
# -----------------------------------------------------------------------------
# Line 1: Model, directory, git branch, session timer, active API time
# Line 2: Context bar, 3 daily time metrics, session count, weekly total, billing
#
# THREE TIME DIMENSIONS:
#   Today (merged):  Real time at desk — overlapping sessions deduplicated
#   Today (wall):    Naive sum of all session durations — for comparison
#   Today (active):  API processing time — Claude actually working
#
# If merged == wall-clock, you had no overlapping sessions.
# If wall-clock > merged, the merge is doing its job.
#
# Uses printf '%b' instead of echo -e for more reliable escape sequence
# handling across different shells (official docs recommendation).
#
# EXPECTED OUTPUT (subscription user, 2 overlapping sessions):
#   [Opus] 📁 my-project | 🌿 main | Session: 01h 23m 45s (API: 12m 34s)
#   ████░░░░░░ 42% ctx | #2 | Today: 02h 00m | Wall: 03h 00m | Active: 25m | Week: 12h 34m | Limit (5hr): 68% used, resets in 1h 51m | Limit (7day): 4% used
#
# EXPECTED OUTPUT (no overlap — Today and Wall match):
#   [Opus] 📁 my-project | 🌿 main | Session: 00h 45m 00s (API: 10m 00s)
#   ██░░░░░░░░ 18% ctx | #2 | Today: 01h 30m | Wall: 01h 30m | Active: 15m | Week: 08h 00m | Limit (5hr): 30% used, resets in 3h 0m | Limit (7day): 8% used
#
# EXPECTED OUTPUT (API user):
#   [Sonnet] 📁 my-project | Session: 00h 30m 00s (API: 08m 15s)
#   ███████░░░ 75% ctx | #1 | Today: 00h 30m | Wall: 00h 30m | Active: 8m | Week: 02h 15m | Cost: $2.47

# Detect if this is a fresh session with no real data yet.
# total_api_duration_ms = 0 and total_duration_ms <= 2s means Claude
# just started and hasn't processed anything — show a hint.
if [ "$session_ms" -le 2000 ] && [ "$api_ms" -eq 0 ]; then
  # Fresh session — flag session data as pending
  printf '%b\n' "${CYAN}[$MODEL]${RESET} 📁 ${DIR##*/}${BRANCH_STR} | Awaiting first message..."
else
  # Line 1: Model, directory, git branch, session timer
  printf '%b\n' "${CYAN}[$MODEL]${RESET} 📁 ${DIR##*/}${BRANCH_STR} | Session: $(printf '%02dh %02dm %02ds' "$sh" "$sm" "$ss") (API: $(printf '%02dm %02ds' "$am" "$as"))"
fi

# Line 2: Context bar + daily time metrics
printf '%b\n' "${BAR_COLOR}${BAR}${RESET} ${PCT:-0}% ctx${CTX_WARN} | #${session_count} | Today: $(printf '%02dh %02dm' "$dh" "$dm") | Wall: $(printf '%02dh %02dm' "$wall_h" "$wall_m") | Active: ${ACTIVE_FMT} | Week: $(printf '%02dh %02dm' "$wh" "$wm")"

# Line 3: Billing info (rate limits or cost)
printf '%b\n' "${YELLOW}${BILLING}${RESET}"

# Always exit 0 — non-zero exit causes the status line to go blank (per docs)
exit 0
