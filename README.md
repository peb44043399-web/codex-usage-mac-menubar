# Codex Quota Menu

macOS menu bar app for showing your local Codex quota at a glance.

It displays two remaining-usage values in the status bar:

- `5h`: remaining quota in the rolling 5-hour window
- `w`: remaining quota in the weekly window

The app reads Codex's local session logs. It does not call OpenAI APIs and does
not read `~/.codex/auth.json`.

![Codex Quota Menu screenshot](docs/screenshot.png)

## Requirements

- macOS 13 or later
- Xcode Command Line Tools, for `swiftc`
- A local Codex installation that writes session logs under `~/.codex/sessions`

Install Xcode Command Line Tools if `swiftc` is not available:

```zsh
xcode-select --install
```

## Quick Start

Clone the repository, build the app, then install it as a LaunchAgent:

```zsh
git clone https://github.com/peb44043399-web/codex-quota-menubar.git
cd codex-quota-menubar
scripts/build.sh
scripts/install-launch-agent.sh
```

After installation, the app starts immediately and also starts automatically at
login.

Important: the LaunchAgent points to the app inside this clone directory. Do not
move or delete the repository directory after installing, unless you uninstall
and install again from the new location.

## Usage

The menu bar item shows two rows:

```text
5h 68%
w  21%
```

Both values are remaining quota, not used quota.

Click the menu bar item to open the detail menu. The detail menu shows:

- 5-hour remaining quota and refresh time
- weekly remaining quota and refresh date
- refresh action
- quit action

Hold Option while opening the menu to reveal the source log action.

## Test Without Installing

Build first:

```zsh
scripts/build.sh
```

Then run the parser once:

```zsh
dist/CodexQuotaMenu.app/Contents/MacOS/CodexQuotaMenu --print-once
```

Example output:

```text
Codex 5h 68% w 21%
5小时剩余用量: 68%
5h刷新时间: 2026/6/16, 16:57:00
周剩余用量: 21%
weekly刷新时间: 2026/6/18, 10:43:30
```

## Install, Restart, Uninstall

Install or restart the LaunchAgent:

```zsh
scripts/install-launch-agent.sh
```

Uninstall:

```zsh
scripts/uninstall-launch-agent.sh
```

Check whether the LaunchAgent is running:

```zsh
launchctl print "gui/$(id -u)/com.local.codex-quota-menubar"
```

Logs:

```zsh
tail -n 80 /tmp/codex-quota-menubar.err.log
```

## Configuration

The app reads these environment variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `CODEX_HOME` | `~/.codex` | Codex home directory |
| `CODEX_LIMIT_ID` | `codex` | Rate-limit id to prefer |
| `CODEX_QUOTA_LOOKBACK_DAYS` | `3` | Recent session days to scan before fallback |

The install script writes `CODEX_HOME` and `CODEX_LIMIT_ID` into the generated
LaunchAgent plist. If you need different values, edit
`scripts/install-launch-agent.sh`, then run it again.

## How It Works

The app scans local JSONL files under:

```text
~/.codex/sessions
~/.codex/archived_sessions
```

It finds the newest event containing a `rate_limits` field, extracts the 5-hour
and weekly windows, and renders the remaining percentages in the macOS status
bar.

For startup responsiveness, the app caches the last parsed snapshot in:

```text
~/Library/Caches/local.codex.quota-menubar/last-snapshot.json
```

The cache is only a local copy of the last quota snapshot. It does not contain
Codex credentials.

## Troubleshooting

If the menu shows `--`, the app did not find a local `rate_limits` event. Use
Codex once, or open Codex status in a session, then click refresh.

If the app does not appear after login, run:

```zsh
scripts/install-launch-agent.sh
launchctl print "gui/$(id -u)/com.local.codex-quota-menubar"
```

If you moved the repository directory after installing, uninstall and reinstall:

```zsh
scripts/uninstall-launch-agent.sh
scripts/install-launch-agent.sh
```

If build fails with `swiftc: command not found`, install Xcode Command Line
Tools:

```zsh
xcode-select --install
```

## Privacy

This app is local-only:

- no network requests
- no OpenAI API calls
- no reading of `~/.codex/auth.json`
- no telemetry

It reads local Codex session JSONL files only to find quota metadata.

## License

MIT
