#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="$("$ROOT_DIR/scripts/build-app.sh")"
DOWNLOAD_DIR="$ROOT_DIR/site/downloads"
ZIP_PATH="$DOWNLOAD_DIR/Token-Racing.zip"

mkdir -p "$DOWNLOAD_DIR"
rm -f "$ZIP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$ZIP_PATH"
