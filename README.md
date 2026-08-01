# ClaudeUsage

A tiny native macOS menu bar app that shows your Claude Code subscription usage at a glance:

- **5-hour session** utilization (the percentage lives right in the menu bar)
- **Weekly** utilization
- **Countdown** until the 5-hour window resets
- **Notification** the moment your session refreshes, so you know you're back at full capacity

Built in pure Swift/SwiftUI — no Electron, no log-file parsing. It calls a lightweight API every ~3 minutes and sleeps in between (~0% CPU, a few tens of MB of RAM).

```
Menu bar:  ◉ 16%
┌──────────────────────────────┐
│ Claude Usage                 │
│ 5h session  ██░░░░░░░░  16%  │
│ Weekly      ██████░░░░  64%  │
│ ⟳ Session resets in 2h 14m   │
│ Updated 15:12                │
│ ──────────────────────────── │
│ Refresh Now  ☐ Launch at Login│
│ Quit ClaudeUsage             │
└──────────────────────────────┘
```

## Requirements

- macOS 14+
- Swift toolchain (Xcode Command Line Tools are enough — no Xcode needed)
- Claude Code installed and logged in (the app reads the OAuth token Claude Code stores in your Keychain)

## Install

```sh
make install    # builds, bundles, signs (ad-hoc), copies to /Applications, launches
```

On first run macOS may show a Keychain dialog — click **Always Allow**. If asked about notifications, allow them so the session-reset alert can fire.

Other targets: `make once` (one-shot fetch printed to the terminal), `make run` (run without installing), `make clean`.

## How it works

- Reads your Claude Code OAuth token from the login Keychain (`security find-generic-password -s "Claude Code-credentials" -w`). It never refreshes or stores the token itself — Claude Code owns it.
- Polls `https://api.anthropic.com/api/oauth/usage` — the same undocumented endpoint that powers Claude Code's `/usage` command — every ~3 minutes with exponential backoff on 429s, and immediately after your Mac wakes from sleep.
- Writes the latest reading to `~/Library/Application Support/ClaudeUsage/snapshot.json` (atomic), which is the contract for the planned desktop widget (see below).
- Schedules the "session refreshed" notification at the exact `resets_at` time via `UNCalendarNotificationTrigger`, with an in-app timer + `osascript` fallback.
- Test the notification without waiting 5 hours: `open /Applications/ClaudeUsage.app --args -debugNotifyIn 10`

Because the usage endpoint is undocumented, Anthropic could change it at any time; the app degrades gracefully (keeps showing the last good numbers with a stale indicator).

## Roadmap: desktop widget (Phase 2)

The code is structured so a real WidgetKit desktop widget can be added later (requires full Xcode + a free Apple ID for signing): the menu bar app would write `snapshot.json` into an App Group container and a sandboxed widget extension would render it with a live countdown. The snapshot model (`UsageSnapshot.swift`) is already the shared contract.

## Disclaimer

Personal project, not affiliated with Anthropic. Uses an undocumented endpoint — be gentle with polling intervals.
