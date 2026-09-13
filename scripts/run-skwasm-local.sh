#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-8080}"

flutter build web --wasm --release
python3 e2e/serve.py "$PORT"
