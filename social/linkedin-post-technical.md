# LinkedIn post (technical / credibility-first)

Most usage timers are wrong, and it's interesting why.

If you run Claude Code in three terminals simultaneously for an hour, a naive timer shows three hours. If you leave a session open while you go to lunch, it shows you "worked" through lunch. Neither is true. Both numbers lie in opposite directions.

I built a small tool to do this honestly. Two mechanics do the work:

1. Each session writes a [start, end] interval. Overlapping intervals get merged before summing, so three parallel agents for an hour sum to one hour, not three.

2. The "end" timestamp only moves forward when Claude actually responds. Walk away, the clock stops. Idle time trims itself out.

The result is a status bar that gives you one number that actually means something: real work time with Claude, across every session, merged honestly. Plus a live 5-hour rate-limit countdown so you stop getting surprised by it.

Runs locally. Zero API tokens. Built on Claude Code's official statusLine hook.

https://github.com/rkrevolution/claude-statusline-timer
