# Reddit r/ClaudeAI post

## Title
I built a status bar for Claude Code that handles parallel sessions correctly (worktrees, subagents)

## Body

Hey all. Sharing a small tool I built for myself that other heavy users might like.

**The problem I kept running into:**

I run Claude Code across multiple git worktrees. Often 2-3 terminals at once, sometimes spawning subagents. I also use Pro, so the 5-hour rate-limit window matters. Two things kept biting me:

1. No sense of how much of my window I'd already spent until I hit the wall.
2. Any timer I tried either double-counted parallel sessions (three terminals running = 3x the time) or ignored the problem entirely.

**What it does:**

Replaces Claude Code's default single-line status with a 3-line display. Shows:

- Current model, project, git branch
- Active session time, API time, context window %
- Sessions today, daily + weekly real time totals
- Live countdown on the 5-hour rate-limit window (Pro/Max) or daily cost (API)

**The parallel-session part:**

It stores [start, end] intervals per session_id and merges overlapping intervals before summing. Three terminals running at the same time for 20 minutes shows up as 20 minutes, not 60. And "end" only advances when Claude actually responds, so if you walk away the idle time trims itself out.

If you run worktree-based workflows or spawn subagents, this is built for you.

**Other stuff:**

- 100% local. No server, no telemetry, zero API tokens consumed.
- Built on Claude Code's official statusLine hook, not a scraper.
- Install is `brew install jq`, drop a bash script in `~/.claude/`, add one line to `settings.json`. Maybe 2 minutes.

Repo: https://github.com/rkrevolution/claude-statusline-timer

Feedback welcome, especially from other parallel-agent users. Curious what fields you'd want that I haven't thought of.
