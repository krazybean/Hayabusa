#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/collector/windows"
DIST_ROOT="${ROOT_DIR}/dist"
PACKAGE_DIR="${DIST_ROOT}/hayabusa-windows-collector"
ZIP_PATH="${DIST_ROOT}/hayabusa-windows-collector.zip"

log() {
  printf '[windows-package] %s\n' "$*"
}

copy_file() {
  src="$1"
  dest="$2"
  mkdir -p "$(dirname "${dest}")"
  cp "${src}" "${dest}"
}

log "Preparing Windows collector package output."
rm -rf "${PACKAGE_DIR}" "${ZIP_PATH}"
mkdir -p "${PACKAGE_DIR}/docs" "${PACKAGE_DIR}/vector"

copy_file "${SOURCE_DIR}/bundle/README.md" "${PACKAGE_DIR}/README.md"
copy_file "${SOURCE_DIR}/bundle/env.example" "${PACKAGE_DIR}/env.example"

for script_name in install.ps1 configure.ps1 validate.ps1 start.ps1 stop.ps1 test-ingestion.ps1 collect-sample-events.ps1 emit-security-events.ps1 uninstall.ps1; do
  copy_file "${SOURCE_DIR}/scripts/${script_name}" "${PACKAGE_DIR}/${script_name}"
done

copy_file "${SOURCE_DIR}/vector/vector.toml.tpl" "${PACKAGE_DIR}/vector/vector.toml.tpl"
copy_file "${SOURCE_DIR}/vector/README.md" "${PACKAGE_DIR}/vector/README.md"
copy_file "${SOURCE_DIR}/docs/windows-collector.md" "${PACKAGE_DIR}/docs/windows-collector.md"
copy_file "${SOURCE_DIR}/docs/windows-real-host-test.md" "${PACKAGE_DIR}/docs/windows-real-host-test.md"

if command -v zip >/dev/null 2>&1; then
  (
    cd "${DIST_ROOT}"
    zip -qr "$(basename "${ZIP_PATH}")" "$(basename "${PACKAGE_DIR}")"
  )
  log "Created zip archive: ${ZIP_PATH}"
else
  log "zip command not found; leaving folder ready to zip manually."
fi

log "Package ready at: ${PACKAGE_DIR}"
printf '\nContents:\n'
find "${PACKAGE_DIR}" -maxdepth 3 -type f | sort | sed "s#${ROOT_DIR}/##"
