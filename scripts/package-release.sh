#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
SOURCE_APP="${ROOT_DIR}/dist/CodexQuotaMenu.app"
RELEASE_DIR="${ROOT_DIR}/dist/release"
RELEASE_APP="${RELEASE_DIR}/CodexUsageMacMenubar.app"
ZIP_PATH="${RELEASE_DIR}/CodexUsageMacMenubar.app.zip"

"${SCRIPT_DIR}/build.sh"

rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

ditto "${SOURCE_APP}" "${RELEASE_APP}"
ditto -c -k --sequesterRsrc --keepParent "${RELEASE_APP}" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" > "${ZIP_PATH}.sha256"

echo "${ZIP_PATH}"
