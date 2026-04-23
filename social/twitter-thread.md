# Twitter thread

1/ I use Claude Code every day. I kept looking up at 7pm wondering where the day went. Or hitting a rate limit mid-refactor. So I built a status bar that tells me where I stand before I burn through my hours.

2/ It's a 3-line status line that replaces the default one. Shows model, project, branch, session time, API time, context %, sessions today, daily + weekly real time, and a live 5-hour rate-limit countdown.

3/ The trick: I run Claude in parallel a lot. Multiple worktrees, subagents, a couple terminals. A naive timer double-counts that. This one stores [start, end] intervals per session and merges overlaps before summing.

4/ Also: "end" only ticks forward when Claude actually responds. So if you walk away for an hour, that hour doesn't count. The number you see is real work time, not wall-clock.

5/ Runs 100% local. Zero API tokens consumed. No server, no telemetry. Built on Claude Code's official statusLine hook, not a scraped hack. https://code.claude.com/docs/en/statusline

6/ Install is ~2 minutes:
- brew install jq
- drop one bash script in ~/.claude/
- add a statusLine entry to settings.json

Repo: https://github.com/rkrevolution/claude-statusline-timer

7/ Pro/Max subscribers get the rate-limit countdown. API users see daily spend instead. If you run parallel agents and you've ever lost a day to the terminal, this is the buddy I wanted.
