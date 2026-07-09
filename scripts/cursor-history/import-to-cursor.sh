#!/usr/bin/env bash
# Import Cursor chat/agent history archive into local Cursor on macOS.
#
# Usage:
#   ./import-to-cursor.sh /path/to/cursor-history-export-YYYYMMDD-HHMMSS.tar.gz
#
# IMPORTANT: Quit Cursor completely (Cmd+Q) before running.

set -euo pipefail

ARCHIVE="${1:?Usage: $0 <cursor-history-export.tar.gz>}"
HOME_DIR="${HOME}"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="/tmp/cursor-import-${STAMP}"

CURSOR_APP_SUPPORT="${HOME_DIR}/Library/Application Support/Cursor"
CURSOR_DOT="${HOME_DIR}/.cursor"

if [[ ! -f "${ARCHIVE}" ]]; then
  echo "ERROR: Archive not found: ${ARCHIVE}"
  exit 1
fi

if pgrep -x "Cursor" >/dev/null 2>&1; then
  echo "ERROR: Cursor is running. Quit Cursor completely (Cmd+Q), then re-run."
  exit 1
fi

echo "==> Extracting ${ARCHIVE}..."
mkdir -p "${WORK}"
tar -xzf "${ARCHIVE}" -C "${WORK}"
EXPORT_DIR="$(find "${WORK}" -maxdepth 1 -type d -name 'cursor-history-export-*' | head -1)"
if [[ -z "${EXPORT_DIR}" ]]; then
  echo "ERROR: Invalid archive layout."
  exit 1
fi

echo "==> Backing up existing Cursor data..."
[[ -d "${CURSOR_APP_SUPPORT}" ]] && mv "${CURSOR_APP_SUPPORT}" "${CURSOR_APP_SUPPORT}.bak-${STAMP}"
[[ -d "${CURSOR_DOT}" ]] && mv "${CURSOR_DOT}" "${CURSOR_DOT}.bak-${STAMP}"

mkdir -p "${CURSOR_APP_SUPPORT}/User/globalStorage"
mkdir -p "${CURSOR_APP_SUPPORT}/User"

echo "==> Restoring global chat database..."
if [[ -f "${EXPORT_DIR}/Application Support/Cursor/User/globalStorage/state.vscdb" ]]; then
  cp "${EXPORT_DIR}/Application Support/Cursor/User/globalStorage/state.vscdb" \
     "${CURSOR_APP_SUPPORT}/User/globalStorage/state.vscdb"
fi

echo "==> Restoring workspace chats..."
if [[ -d "${EXPORT_DIR}/Application Support/Cursor/User/workspaceStorage" ]]; then
  cp -R "${EXPORT_DIR}/Application Support/Cursor/User/workspaceStorage" \
     "${CURSOR_APP_SUPPORT}/User/"
fi

echo "==> Restoring settings..."
for f in settings.json keybindings.json; do
  src="${EXPORT_DIR}/Application Support/Cursor/User/${f}"
  [[ -f "${src}" ]] && cp "${src}" "${CURSOR_APP_SUPPORT}/User/${f}"
done

echo "==> Restoring .cursor rules and config..."
if [[ -d "${EXPORT_DIR}/dot-cursor" ]]; then
  mkdir -p "${CURSOR_DOT}"
  cp -R "${EXPORT_DIR}/dot-cursor/." "${CURSOR_DOT}/"
fi

rm -rf "${WORK}"

echo ""
echo "Import complete."
echo "Backups saved as:"
echo "  ${CURSOR_APP_SUPPORT}.bak-${STAMP}  (if existed)"
echo "  ${CURSOR_DOT}.bak-${STAMP}  (if existed)"
echo ""
echo "Open Cursor now. Fully quit and reopen if chats don't appear immediately."
