#!/bin/bash
# =============================================================================
# Claude Code Status Line Timer — Diagnostic Test
# =============================================================================
# Run this anytime to verify the timer is working correctly.
# Usage: bash ~/.claude/test-timer.sh
# =============================================================================

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'
today=$(date +%Y-%m-%d)
daily_file="$HOME/.claude/timer-daily-$today.json"
subscriber_marker="$HOME/.claude/timer-subscriber-$today"

echo "============================================"
echo " Claude Status Line Timer — Diagnostic Test"
echo " $(date)"
echo "============================================"
echo ""

# --- 1. Check dependencies ---
echo -e "${CYAN}[1] Dependencies${RESET}"
if command -v jq &>/dev/null; then
  echo -e "  ${GREEN}✓${RESET} jq installed ($(jq --version 2>&1))"
else
  echo -e "  ${RED}✗${RESET} jq NOT installed — run: brew install jq"
fi

if [ -x "$HOME/.claude/ultimate-timer.sh" ]; then
  echo -e "  ${GREEN}✓${RESET} ultimate-timer.sh exists and is executable"
else
  echo -e "  ${RED}✗${RESET} ultimate-timer.sh missing or not executable"
  echo "    Fix: chmod +x ~/.claude/ultimate-timer.sh"
fi
echo ""

# --- 2. Check settings ---
echo -e "${CYAN}[2] Settings${RESET}"
if [ -f "$HOME/.claude/settings.json" ]; then
  sl=$(jq -r '.statusLine.command // empty' "$HOME/.claude/settings.json" 2>/dev/null)
  if [ -n "$sl" ]; then
    echo -e "  ${GREEN}✓${RESET} statusLine configured: $sl"
  else
    echo -e "  ${RED}✗${RESET} statusLine not found in settings.json"
  fi

  hooks=$(jq -r '.disableAllHooks // false' "$HOME/.claude/settings.json" 2>/dev/null)
  if [ "$hooks" = "true" ]; then
    echo -e "  ${RED}✗${RESET} disableAllHooks is true — status line is disabled!"
  else
    echo -e "  ${GREEN}✓${RESET} disableAllHooks is not set (status line enabled)"
  fi
else
  echo -e "  ${RED}✗${RESET} ~/.claude/settings.json not found"
fi
echo ""

# --- 3. Check daily file ---
echo -e "${CYAN}[3] Daily File ($today)${RESET}"
if [ -f "$daily_file" ]; then
  session_count=$(jq 'length' "$daily_file" 2>/dev/null || echo 0)
  echo -e "  ${GREEN}✓${RESET} File exists with $session_count session(s)"
  echo ""
  echo "  Sessions:"
  jq -r 'to_entries[] | "    \(.key[0:12])... start=\(.value.start) end=\(.value.end) dur=\(.value.end - .value.start)s api=\(.value.api_ms // 0)ms cost=$\(.value.cost // 0)"' "$daily_file" 2>/dev/null
  echo ""

  # Validate fields
  echo "  Field validation:"
  bad=0
  jq -e '[to_entries[] | select(.value.start == null or .value.end == null)] | length == 0' "$daily_file" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "    ${GREEN}✓${RESET} All sessions have start and end timestamps"
  else
    echo -e "    ${RED}✗${RESET} Some sessions missing start/end timestamps"
    bad=1
  fi

  jq -e '[to_entries[] | select(.value.end < .value.start)] | length == 0' "$daily_file" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "    ${GREEN}✓${RESET} All sessions have end >= start"
  else
    echo -e "    ${RED}✗${RESET} Some sessions have end < start (invalid)"
    bad=1
  fi

  jq -e '[to_entries[] | select(.value.api_ms < 0)] | length == 0' "$daily_file" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "    ${GREEN}✓${RESET} All api_ms values are non-negative"
  else
    echo -e "    ${RED}✗${RESET} Negative api_ms values found"
    bad=1
  fi
  echo ""

  # Compute and show merge
  echo "  Merge computation:"
  read -r merged wall api cost < <(jq -r '
    [to_entries[] | .value] as $s |
    ([$s[] | .end - .start] | add // 0) as $wall |
    [$s | sort_by(.start)[] | {start: .start, end: .end}] as $sorted |
    ($sorted | reduce .[] as $iv (
      [];
      if length == 0 then [$iv]
      elif (last.end >= $iv.start) then (.[:-1] + [{start: last.start, end: ([last.end, $iv.end] | max)}])
      else . + [$iv]
      end
    )) as $m |
    ([$m[] | .end - .start] | add // 0) as $mt |
    "\($mt) \($wall) \([$s[].api_ms] | add // 0) \([$s[].cost] | add // 0)"
  ' "$daily_file" 2>/dev/null || echo "0 0 0 0")

  merged_h=$(( merged / 3600 ))
  merged_m=$(( (merged % 3600) / 60 ))
  wall_h=$(( wall / 3600 ))
  wall_m=$(( (wall % 3600) / 60 ))
  api_s=$(( api / 1000 ))
  api_min=$(( api_s / 60 ))
  saved=$(( wall - merged ))

  echo "    Today (merged): ${merged_h}h ${merged_m}m (${merged}s)"
  echo "    Wall (naive):   ${wall_h}h ${wall_m}m (${wall}s)"
  echo "    Active (API):   ${api_min}m (${api}ms)"
  echo "    Cost:           \$${cost}"
  if [ "$saved" -gt 0 ]; then
    echo -e "    ${GREEN}✓${RESET} Merge saved ${saved}s from overlapping sessions"
  elif [ "$saved" -eq 0 ]; then
    echo -e "    ${GREEN}✓${RESET} No overlapping sessions (Today == Wall)"
  else
    echo -e "    ${RED}✗${RESET} Merged > Wall — this shouldn't happen"
  fi
else
  echo -e "  ${YELLOW}—${RESET} No daily file yet (will be created on first message)"
fi
echo ""

# --- 4. Check subscriber marker ---
echo -e "${CYAN}[4] Subscriber Detection${RESET}"
if [ -f "$subscriber_marker" ]; then
  echo -e "  ${GREEN}✓${RESET} Subscriber marker exists — rate limits will show"
else
  echo -e "  ${YELLOW}—${RESET} No subscriber marker yet — will show Cost until first API response with rate_limits"
fi
echo ""

# --- 5. Check weekly files ---
echo -e "${CYAN}[5] Weekly Data (past 7 days)${RESET}"
week_total=0
for i in {0..6}; do
  wdate=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-$i days" +%Y-%m-%d 2>/dev/null)
  wfile="$HOME/.claude/timer-daily-${wdate}.json"
  if [ -f "$wfile" ]; then
    count=$(jq 'length' "$wfile" 2>/dev/null || echo 0)
    ws=$(jq '[to_entries[] | .value] | [sort_by(.start)[] | {start: .start, end: .end}] | reduce .[] as $iv ([]; if length == 0 then [$iv] elif (last.end >= $iv.start) then (.[:-1] + [{start: last.start, end: ([last.end, $iv.end] | max)}]) else . + [$iv] end) | [.[] | .end - .start] | add // 0' "$wfile" 2>/dev/null || echo 0)
    wh=$(( ws / 3600 ))
    wm=$(( (ws % 3600) / 60 ))
    week_total=$(( week_total + ws ))
    echo -e "  ${GREEN}✓${RESET} $wdate: ${count} sessions, ${wh}h ${wm}m merged"
  else
    echo -e "  ${YELLOW}—${RESET} $wdate: no data"
  fi
done
tw_h=$(( week_total / 3600 ))
tw_m=$(( (week_total % 3600) / 60 ))
echo "  Week total: ${tw_h}h ${tw_m}m"
echo ""

# --- 6. Live test ---
echo -e "${CYAN}[6] Live Test (mock data)${RESET}"
NOW=$(date +%s)
output=$(echo '{"model":{"display_name":"TestModel"},"workspace":{"current_dir":"/tmp/test"},"context_window":{"used_percentage":50},"exceeds_200k_tokens":false,"session_id":"diag-test","cost":{"total_duration_ms":60000,"total_api_duration_ms":5000,"total_cost_usd":0.5},"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":'$((NOW+3600))'},"seven_day":{"used_percentage":10,"resets_at":'$((NOW+500000))'}},"version":"1.0.80"}' | bash ~/.claude/ultimate-timer.sh 2>&1)

if [ $? -eq 0 ] && [ -n "$output" ]; then
  echo -e "  ${GREEN}✓${RESET} Script ran successfully. Output:"
  echo "$output" | sed 's/^/    /'
else
  echo -e "  ${RED}✗${RESET} Script failed or produced no output"
  echo "    Exit code: $?"
  echo "    Output: $output"
fi

# Clean up test entry
jq 'del(.["diag-test"])' "$daily_file" > /tmp/ct-diag.json 2>/dev/null && mv /tmp/ct-diag.json "$daily_file" 2>/dev/null

echo ""
echo "============================================"
echo " Diagnostic complete"
echo "============================================"
