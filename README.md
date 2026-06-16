# Codex Quota Menu

Small macOS menu bar app for displaying the latest local Codex rate-limit state.

Data source:

- Reads `~/.codex/sessions/**/*.jsonl`
- Finds the newest event with a `rate_limits` field
- Shows remaining percent for the 5-hour window and weekly window
- Defaults to `CODEX_LIMIT_ID=codex`; set `CODEX_LIMIT_ID` to another local
  `limit_id` if you intentionally want a model-specific quota.

It does not call OpenAI APIs and does not read `~/.codex/auth.json`.

Build:

```zsh
scripts/build.sh
```

Test parser without opening the menu bar app:

```zsh
dist/CodexQuotaMenu.app/Contents/MacOS/CodexQuotaMenu --print-once
```

Install as a login item and launch now:

```zsh
scripts/install-launch-agent.sh
```

Uninstall:

```zsh
scripts/uninstall-launch-agent.sh
```
