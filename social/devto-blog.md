# Dev.to blog post

## Title
A status bar for Claude Code that tracks real time across parallel sessions

---

I use Claude Code every day. I'd get heads down and hours would disappear. Sometimes I'd hit the 5-hour rate limit mid-refactor. Sometimes I'd look up and realize I'd lost the afternoon. I wanted a small signal, right there in the terminal, that told me where I stood.

So I built one. It's called **Claude Code Status Timer**, and it replaces the default single-line status bar with a 3-line display showing model, project, branch, session time, context %, daily and weekly totals, and a live rate-limit countdown.

## The three problems it solves

**1. You can't see your rate-limit window.**

Pro and Max accounts get a 5-hour rolling window. The default status line doesn't show it. You find out you've hit it by hitting it.

**2. Idle time gets counted as work.**

Most naive timers treat "session started at 9am, last message at 4pm" as 7 hours of Claude. But you went to lunch. You took a call. You thought for 40 minutes.

**3. Parallel sessions get counted wrong.**

If you run Claude in multiple git worktrees, or spawn subagents, or just keep three terminals open, a dumb timer either triple-counts those hours or ignores the problem.

## How the overlap merging works (conceptually)

Every session writes `[start, end]` timestamp intervals keyed by `session_id`. Nothing fancy. The interesting bit is how we roll those up.

When the status bar asks "how much time did I spend today?", it does this:

1. Gather every interval that touches today.
2. Sort by start time.
3. Walk the list. If the next interval starts before the previous one ends, merge them.
4. Sum the merged intervals.

So three terminals running simultaneously from 2pm to 2:20pm collapse into one 20-minute block. Not 60 minutes. And since `end` only advances when Claude actually responds, walking away from the keyboard doesn't inflate your total. The number you see is real work time, not the sum of wall clocks.

## Install

About two minutes.

```bash
brew install jq
# copy the script to ~/.claude/statusline.sh
# then add this to ~/.claude/settings.json:
```

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

Full instructions in the repo.

## What it doesn't do

No server. No telemetry. No API calls. It reads Claude Code's local session files and renders a string. That's it. Built on the [official statusLine hook](https://code.claude.com/docs/en/statusline), not a scraped workaround.

## Repo

https://github.com/rkrevolution/claude-statusline-timer

If you run parallel agent workflows (worktrees, subagents, multiple terminals), I'd especially like to hear what you think. That's the case I tuned it for.
