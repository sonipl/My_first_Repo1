#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Starting Tesla Daily Usage Agent backend..."
cd "$ROOT/backend"
if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install -r requirements.txt
fi
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
