#!/bin/zsh
set -euo pipefail

REPO="peb44043399-web/codex-usage-mac-menubar"
ASSET_NAME="CodexUsageMacMenubar.app.zip"
APP_NAME="CodexUsageMacMenubar.app"
INSTALL_DIR="${HOME}/Applications"
APP_PATH="${INSTALL_DIR}/${APP_NAME}"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.local.codex-quota-menubar.plist"
DOMAIN="gui/$(id -u)"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
CODEX_HOME_VALUE="${CODEX_HOME:-${HOME}/.codex}"
CODEX_LIMIT_ID_VALUE="${CODEX_LIMIT_ID:-codex}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

xml_escape() {
  printf "%s" "$1" \
    | sed -e 's/&/\&amp;/g' \
          -e 's/</\&lt;/g' \
          -e 's/>/\&gt;/g' \
          -e 's/"/\&quot;/g' \
          -e "s/'/\&apos;/g"
}

echo "Downloading ${DOWNLOAD_URL}"
curl -fL --retry 3 "${DOWNLOAD_URL}" -o "${TMP_DIR}/${ASSET_NAME}"

ditto -x -k "${TMP_DIR}/${ASSET_NAME}" "${TMP_DIR}"

if [[ ! -d "${TMP_DIR}/${APP_NAME}" ]]; then
  echo "Downloaded archive does not contain ${APP_NAME}" >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"
rm -rf "${APP_PATH}"
ditto "${TMP_DIR}/${APP_NAME}" "${APP_PATH}"

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
    <string>$(xml_escape "${APP_PATH}/Contents/MacOS/CodexQuotaMenu")</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CODEX_HOME</key>
    <string>$(xml_escape "${CODEX_HOME_VALUE}")</string>
    <key>CODEX_LIMIT_ID</key>
    <string>$(xml_escape "${CODEX_LIMIT_ID_VALUE}")</string>
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

echo "Installed ${APP_PATH}"
echo "Installed and launched ${PLIST_DEST}"
