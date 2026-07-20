#!/usr/bin/env bash
#
# Bumps the app version by one patch + one build number and writes it to the
# three places that must stay in lockstep:
#   - pubspec.yaml              version: MAJOR.MINOR.PATCH+BUILD
#   - config_service.dart       appVersion => 'MAJOR.MINOR.PATCH'
#   - web/version.json          {"version": "MAJOR.MINOR.PATCH+BUILD"}
#
# Invoked by .githooks/pre-commit, but safe to run by hand too. Pass --stage to
# also `git add` the changed files (the hook does this so the bump lands in the
# same commit).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PUBSPEC="pubspec.yaml"
CONFIG="lib/services/data/config_service.dart"
WEB_JSON="web/version.json"

for f in "$PUBSPEC" "$CONFIG" "$WEB_JSON"; do
  if [ ! -f "$f" ]; then
    echo "bump-version: missing $f" >&2
    exit 1
  fi
done

# Current "version: X.Y.Z+B" from pubspec (the single source of truth).
current="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*+[0-9][0-9]*\).*/\1/p' "$PUBSPEC" | head -1)"
if [ -z "$current" ]; then
  echo "bump-version: could not parse 'version: X.Y.Z+B' from $PUBSPEC" >&2
  exit 1
fi

semver="${current%%+*}"   # X.Y.Z
build="${current##*+}"    # B
major="${semver%%.*}"
patch="${semver##*.}"
rest="${semver#*.}"
minor="${rest%%.*}"

new_patch=$((patch + 1))
new_build=$((build + 1))
new_semver="${major}.${minor}.${new_patch}"
new_full="${new_semver}+${new_build}"

# Rewrite in place. perl -i is portable across macOS/Linux (BSD vs GNU sed).
# Only the top-level `version:` line (column 0) is touched, never indented
# dependency version fields.
perl -0pi -e "s/^version:[ \t]*\Q$current\E[ \t]*\$/version: $new_full/m" "$PUBSPEC"

# Replace whatever is inside the appVersion string literal, regardless of its
# old value, so the files can't drift.
perl -0pi -e "s/(appVersion\s*=>\s*')[^']*(')/\${1}$new_semver\${2}/" "$CONFIG"

# Replace the JSON "version" value.
perl -0pi -e "s/(\"version\"\s*:\s*\")[^\"]*(\")/\${1}$new_full\${2}/" "$WEB_JSON"

echo "bump-version: $current -> $new_full"

if [ "${1:-}" = "--stage" ]; then
  git add "$PUBSPEC" "$CONFIG" "$WEB_JSON"
fi
