#!/bin/zsh
set -euo pipefail

APP_PATH="${HOME}/Applications/CodexUsageMacMenubar.app"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.local.codex-quota-menubar.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "${DOMAIN}" "${PLIST_DEST}" >/dev/null 2>&1 || true

if [[ -f "${PLIST_DEST}" ]]; then
  rm "${PLIST_DEST}"
fi

if [[ -d "${APP_PATH}" ]]; then
  rm -rf "${APP_PATH}"
fi

echo "Uninstalled CodexUsageMacMenubar"
