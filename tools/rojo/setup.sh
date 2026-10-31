#!/usr/bin/env bash
# setup.sh — cài Rojo (qua Rokit) rồi kiểm tra môi trường local.
#
#   bash tools/rojo/setup.sh          # macOS / Linux
#
# Windows (PowerShell):
#   iwr https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 -useb | iex
#   rokit install
set -euo pipefail

cd "$(dirname "$0")/../.."

if ! command -v rojo >/dev/null 2>&1; then
  echo "→ Chưa có rojo. Cài Rokit + rojo theo rokit.toml…"
  if ! command -v rokit >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
    export PATH="${HOME}/.rokit/bin:${PATH}"
  fi
  rokit install
else
  echo "✔ rojo đã có: $(rojo --version)"
fi

echo ""
node tools/rojo/serve.mjs --check
echo ""
echo "Chạy tiếp: node tools/rojo/serve.mjs"
