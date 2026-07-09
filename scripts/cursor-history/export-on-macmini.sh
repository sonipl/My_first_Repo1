#!/usr/bin/env bash
# Run ON the Mac mini (or pipe via: ssh psoni@192.168.68.20 'bash -s' < export-on-macmini.sh)
set -euo pipefail

HOME_DIR="${HOME:-/Users/psoni}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${HOME_DIR}/cursor-history-export-${STAMP}"
ARCHIVE="${HOME_DIR}/cursor-history-export-${STAMP}.tar.gz"

CURSOR_APP_SUPPORT="${HOME_DIR}/Library/Application Support/Cursor"
CURSOR_DOT="${HOME_DIR}/.cursor"

echo "==> Cursor history export"
echo "    Home: ${HOME_DIR}"
echo "    Output: ${ARCHIVE}"

if [[ ! -d "${CURSOR_APP_SUPPORT}" ]]; then
  echo "ERROR: Cursor not found at ${CURSOR_APP_SUPPORT}"
  exit 1
fi

if pgrep -x "Cursor" >/dev/null 2>&1; then
  echo "WARNING: Cursor appears to be running. Quit Cursor (Cmd+Q) first for a clean export."
  read -r -p "Continue anyway? [y/N] " ans
  [[ "${ans:-}" =~ ^[Yy]$ ]] || exit 1
fi

mkdir -p "${OUT_DIR}/Application Support" "${OUT_DIR}/dot-cursor"

echo "==> Copying global chat database..."
mkdir -p "${OUT_DIR}/Application Support/Cursor/User/globalStorage"
cp "${CURSOR_APP_SUPPORT}/User/globalStorage/state.vscdb" \
   "${OUT_DIR}/Application Support/Cursor/User/globalStorage/" 2>/dev/null || true
cp "${CURSOR_APP_SUPPORT}/User/globalStorage/state.vscdb.backup" \
   "${OUT_DIR}/Application Support/Cursor/User/globalStorage/" 2>/dev/null || true

echo "==> Copying workspace chat storage..."
if [[ -d "${CURSOR_APP_SUPPORT}/User/workspaceStorage" ]]; then
  cp -R "${CURSOR_APP_SUPPORT}/User/workspaceStorage" \
     "${OUT_DIR}/Application Support/Cursor/User/"
fi

echo "==> Copying settings and rules..."
for f in settings.json keybindings.json; do
  src="${CURSOR_APP_SUPPORT}/User/${f}"
  [[ -f "${src}" ]] && mkdir -p "${OUT_DIR}/Application Support/Cursor/User" && cp "${src}" "${OUT_DIR}/Application Support/Cursor/User/"
done

if [[ -d "${CURSOR_DOT}" ]]; then
  cp -R "${CURSOR_DOT}/." "${OUT_DIR}/dot-cursor/"
fi

# Metadata for import
cat > "${OUT_DIR}/manifest.json" <<EOF
{
  "exported_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source_host": "$(hostname)",
  "source_user": "$(whoami)",
  "source_home": "${HOME_DIR}",
  "includes": ["globalStorage/state.vscdb", "workspaceStorage", ".cursor"]
}
EOF

echo "==> Creating archive..."
tar -czf "${ARCHIVE}" -C "${OUT_DIR%/*}" "$(basename "${OUT_DIR}")"
rm -rf "${OUT_DIR}"

echo ""
echo "Done."
echo "Archive: ${ARCHIVE}"
echo "Size:    $(du -h "${ARCHIVE}" | cut -f1)"
ls -lh "${ARCHIVE}"
