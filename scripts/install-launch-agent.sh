#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
APP_BIN="${ROOT_DIR}/dist/CodexQuotaMenu.app/Contents/MacOS/CodexQuotaMenu"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.local.codex-quota-menubar.plist"
DOMAIN="gui/$(id -u)"

if [[ ! -x "${APP_BIN}" ]]; then
  echo "CodexQuotaMenu is not built. Run scripts/build.sh first." >&2
  exit 1
fi

mkdir -p "${HOME}/Library/LaunchAgents"
cat > "${PLIST_DEST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.codex-quota-menubar</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProgramArguments</key>
  <array>
    <string>${APP_BIN}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CODEX_HOME</key>
    <string>${HOME}/.codex</string>
    <key>CODEX_LIMIT_ID</key>
    <string>codex</string>
  </dict>
  <key>StandardOutPath</key>
  <string>/tmp/codex-quota-menubar.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/codex-quota-menubar.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "${DOMAIN}" "${PLIST_DEST}" >/dev/null 2>&1 || true
launchctl bootstrap "${DOMAIN}" "${PLIST_DEST}"

echo "Installed and launched ${PLIST_DEST}"
