#!/usr/bin/env bash
# Run from a Mac ON THE SAME NETWORK as the Mac mini.
# Pulls Cursor chat/agent history from the Mac mini to the current machine.
#
# Usage:
#   ./pull-from-macmini.sh
#   ./pull-from-macmini.sh psoni@192.168.68.20
#
# You will be prompted for the SSH password unless you use SSH keys.

set -euo pipefail

MAC_HOST="${1:-psoni@192.168.68.20}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_DIR="${SCRIPT_DIR}/imports"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOCAL_ARCHIVE="${LOCAL_DIR}/cursor-history-${STAMP}.tar.gz"

mkdir -p "${LOCAL_DIR}"

echo "==> Exporting Cursor history on Mac mini (${MAC_HOST})..."
ssh "${MAC_HOST}" 'bash -s' < "${SCRIPT_DIR}/export-on-macmini.sh"

echo ""
echo "==> Locating latest export on Mac mini..."
REMOTE_ARCHIVE="$(ssh "${MAC_HOST}" 'ls -t ~/cursor-history-export-*.tar.gz 2>/dev/null | head -1')"
if [[ -z "${REMOTE_ARCHIVE}" ]]; then
  echo "ERROR: No export archive found on Mac mini."
  exit 1
fi
echo "    Found: ${REMOTE_ARCHIVE}"

echo "==> Downloading to ${LOCAL_ARCHIVE}..."
scp "${MAC_HOST}:${REMOTE_ARCHIVE}" "${LOCAL_ARCHIVE}"

echo ""
echo "==> Download complete."
echo "Archive: ${LOCAL_ARCHIVE}"
echo ""
echo "Next step — import into Cursor on THIS Mac:"
echo "  ${SCRIPT_DIR}/import-to-cursor.sh ${LOCAL_ARCHIVE}"
