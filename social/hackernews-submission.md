# Hacker News submission

## Title
Show HN: A status bar for Claude Code that tracks real time across parallel sessions

## URL
https://github.com/rkrevolution/claude-statusline-timer

## Author comment (ready to paste)

Author here. I built this because I use Claude Code every day and kept losing track of time. Two specific pains:

1. I'd get heads down and look up hours later with no sense of how much of my 5-hour window I'd burned.
2. I run Claude in parallel a lot (git worktrees, subagents, a couple of terminals). Any naive per-session timer either double-counts that or undercounts it.

The core thing this gets right: it stores [start, end] timestamp intervals per session_id and merges overlapping intervals before summing. So if you have three terminals running simultaneously for 20 minutes, that's 20 minutes of real time, not 60. And "end" only advances when Claude actually responds, so idle time trims itself out. The daily and weekly totals you see are real work time.

It replaces the default Claude Code status line with a 3-line display: model/project/branch, session and API time, context %, sessions today, daily and weekly totals, and a live countdown on the rate-limit window (for Pro/Max; API users see daily cost instead).

100% local. No server. No telemetry. Zero API tokens consumed. Built on Claude Code's official statusLine hook: https://code.claude.com/docs/en/statusline

Install is a bash script in ~/.claude/ and a one-line entry in settings.json. Takes about 2 minutes.

Happy to answer anything about the overlap-merge logic or why I went with jq over a heavier runtime.
