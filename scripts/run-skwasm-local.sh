#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-8080}"

flutter build web --wasm --release
node scripts/serve-skwasm.mjs "$PORT"
