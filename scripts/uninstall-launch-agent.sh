#!/bin/zsh
set -euo pipefail

PLIST_DEST="${HOME}/Library/LaunchAgents/com.local.codex-quota-menubar.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "${DOMAIN}" "${PLIST_DEST}" >/dev/null 2>&1 || true

if [[ -f "${PLIST_DEST}" ]]; then
  rm "${PLIST_DEST}"
fi

echo "Uninstalled ${PLIST_DEST}"
