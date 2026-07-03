#!/usr/bin/env bash
# scripts/bump-version.sh <new-version>
# Atomically bumps the library version AND every workspace member's
# dowdiness/incr pin in one step.
#
# Why atomic: the CI "Check architecture boundaries" job enforces
# pin == incr/moon.mod version (scripts/check-workspace-boundaries.sh,
# invariant B), so bumping incr/moon.mod alone fails CI. Release procedure:
#   1. bash scripts/bump-version.sh X.Y.Z   (this script)
#   2. commit, PR, merge
#   3. moon publish immediately after the merge — the window where pins name
#      a not-yet-published version must stay bounded (see the trade-off note
#      in check-workspace-boundaries.sh).
set -euo pipefail

repo_root="${INCR_REPO_ROOT:-.}"
lib_mod="$repo_root/incr/moon.mod"
work_file="$repo_root/moon.work"

new_version="${1:-}"
# Typo guard, not a full SemVer validator: pre-release and build parts are
# separate optional groups (so `1.2.3-alpha+001` passes); pedantry like
# rejecting leading-zero identifiers is deliberately out of scope.
if ! echo "$new_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then
  echo "usage: bash scripts/bump-version.sh <semver>  (got: '${new_version}')"
  exit 1
fi
if [ ! -f "$lib_mod" ] || [ ! -f "$work_file" ]; then
  echo "MISSING: $lib_mod or $work_file (run from the repository root)"
  exit 1
fi

old_version=$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$lib_mod" | head -1)
if [ -z "$old_version" ]; then
  echo "MISSING: version field in $lib_mod — aborting before touching any pins"
  exit 1
fi
echo "incr/moon.mod: $old_version -> $new_version"
sed -i "s/^version[[:space:]]*=[[:space:]]*\"$old_version\"/version = \"$new_version\"/" "$lib_mod"

members=$({ grep -oE '"\./[^"]+"' "$work_file" | tr -d '"' | sed 's|^\./||'; } || true)
for member in $members; do
  [ "$member" = "incr" ] && continue
  for mod in "$repo_root/$member/moon.mod" "$repo_root/$member/moon.mod.json"; do
    [ -f "$mod" ] || continue
    grep -q '"dowdiness/incr[@"]' "$mod" || continue
    # TOML-style "dowdiness/incr@X" and legacy JSON-style "dowdiness/incr": "X".
    sed -i \
      -e "s|\"dowdiness/incr@[^\"]*\"|\"dowdiness/incr@$new_version\"|" \
      -e "s|\"dowdiness/incr\"\([[:space:]]*:[[:space:]]*\)\"[^\"]*\"|\"dowdiness/incr\"\1\"$new_version\"|" \
      "$mod"
    echo "pinned: $mod"
  done
done

bash "$repo_root/scripts/check-workspace-boundaries.sh"
echo "OK: version and pins at $new_version, boundary check clean"
