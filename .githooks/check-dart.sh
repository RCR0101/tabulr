#!/usr/bin/env bash
#
# Fails the commit if the Dart/Flutter analyzer reports any issues.
#
# Runs as the first step of .githooks/pre-commit so a broken tree never gets
# committed (and the version bump that follows only happens on a clean tree).
# Skipped automatically when the commit stages no Dart files.
#
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Nothing to analyse if no .dart files are staged — keep doc/asset commits fast.
if ! git diff --cached --name-only --diff-filter=ACM | grep -qE '\.dart$'; then
  echo "pre-commit: no staged Dart files, skipping analysis."
  exit 0
fi

# Prefer the Flutter analyzer; fall back to the Dart SDK; skip if neither exists
# (e.g. a CI/tooling environment without the SDK on PATH) rather than blocking.
if command -v flutter >/dev/null 2>&1; then
  ANALYZE=(flutter analyze)
elif command -v dart >/dev/null 2>&1; then
  ANALYZE=(dart analyze)
else
  echo "pre-commit: neither 'flutter' nor 'dart' found on PATH; skipping analysis." >&2
  exit 0
fi

echo "pre-commit: running ${ANALYZE[*]} ..."
if ! "${ANALYZE[@]}"; then
  echo "" >&2
  echo "Dart analysis found issues. Fix them, or bypass with: git commit --no-verify" >&2
  exit 1
fi

echo "pre-commit: no Dart issues."
