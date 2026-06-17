#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${ROOT_DIR}/dist/CodexQuotaMenu.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
BUILD_DIR="${ROOT_DIR}/.build"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"

mkdir -p "${MACOS_DIR}"
mkdir -p "${MODULE_CACHE_DIR}"
cp "${ROOT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"

swiftc -O \
  -module-cache-path "${MODULE_CACHE_DIR}" \
  -Xcc -fmodules-cache-path="${MODULE_CACHE_DIR}" \
  "${ROOT_DIR}/Sources/CodexQuotaMenu.swift" \
  -o "${MACOS_DIR}/CodexQuotaMenu" \
  -framework AppKit \
  -framework CoreServices

chmod +x "${MACOS_DIR}/CodexQuotaMenu"
plutil -lint "${APP_DIR}/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null
fi

echo "${APP_DIR}"
