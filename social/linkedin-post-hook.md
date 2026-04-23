# LinkedIn post (engagement hook)

Question for the Claude Code power users:

How do you know how much time you've really spent in a day when you're running three agents in parallel?

For me, the honest answer was: I didn't. I'd hit the 5-hour rate limit and be genuinely surprised. I'd spend an afternoon in flow and look up with no sense of whether it had been 90 minutes or four hours.

So I built a status bar that tells me. It sits quietly in the terminal, keeping tabs on every session across the day. The interesting part: it correctly merges overlapping sessions from parallel work (worktrees, subagents, multiple terminals), so the number you see is real time, not a naive sum.

Runs 100% local. No API calls. Built on Claude Code's official status line hook.

https://github.com/rkrevolution/claude-statusline-timer

Curious how others are handling this. Anyone built something similar, or just eyeballing it?
