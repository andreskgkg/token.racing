#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="$("$ROOT_DIR/scripts/build-app.sh")"
"$APP_PATH/Contents/MacOS/TokenRacing" \
  --usage-fixture "$ROOT_DIR/fixtures/sample-usage.jsonl" \
  --expected-total 3175
