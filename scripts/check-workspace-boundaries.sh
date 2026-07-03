#!/usr/bin/env bash
# scripts/check-workspace-boundaries.sh
# Asserts cross-module workspace contracts for the incr repository.
# Companion to check-engine-isolation.sh (in-library invariants); this script
# covers the seams between workspace members. Rules established by
# docs/design/specs/2026-07-03-workspace-boundary-assessment.md (issue #343).
#
# Invariant A (facade-only imports): non-library workspace members (docs/,
#   examples/*) may import only the `dowdiness/incr` root facade — never
#   `dowdiness/incr/cells`, `dowdiness/incr/types`, or any deeper package.
#   Whatever the facade cannot express becomes an explicit core feature
#   request, not a reach into internals.
#
# Invariant B (pin freshness): every workspace member that declares a
#   `dowdiness/incr@X` dependency must pin X to the library's current version
#   (incr/moon.mod). Workspace resolution masks stale pins locally, so drift
#   is invisible until someone builds a member outside the workspace.
#
#   Accepted trade-off: pins must bump atomically with a library version bump,
#   so between the bump commit and `moon publish` the pins name a not-yet-
#   published version. That window is bounded by the release workflow (publish
#   immediately follows the bump), and this repo's CI builds members in
#   workspace mode where registry availability is irrelevant. The alternative
#   (allowing pin < version) readmits exactly the multi-release drift this
#   check exists to catch (0.9.0 pins against a 0.12.0 library, #343).
set -euo pipefail

fail=0
repo_root="${INCR_REPO_ROOT:-.}"
work_file="$repo_root/moon.work"
lib_mod="$repo_root/incr/moon.mod"

if [ ! -f "$work_file" ] || [ ! -f "$lib_mod" ]; then
  echo "MISSING: $work_file or $lib_mod (run from the repository root)"
  exit 1
fi

# Library's current version, from incr/moon.mod: version = "X.Y.Z"
lib_version=$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$lib_mod" | head -1)
if [ -z "$lib_version" ]; then
  echo "MISSING: version field in $lib_mod"
  exit 1
fi

# Workspace members, from moon.work: quoted "./path" entries.
# `|| true` guards set -o pipefail against a no-match grep (same rationale as
# check-engine-isolation.sh's extract_imports).
members=$({ grep -oE '"\./[^"]+"' "$work_file" | tr -d '"' | sed 's|^\./||'; } || true)
if [ -z "$members" ]; then
  echo "MISSING: no members parsed from $work_file"
  exit 1
fi

# Extract imports as exact quoted strings from a moon.pkg file, comments
# stripped, `"test"` discriminator excluded (same shape as
# check-engine-isolation.sh's extract_imports).
extract_imports() {
  local file="$1"
  {
    sed 's|//.*$||; s|#.*$||' "$file" \
      | grep -oE '"[^"]+"' \
      | tr -d '"' \
      | grep -vFx 'test'
  } || true
}

for member in $members; do
  # The library module itself is exempt from both rules.
  [ "$member" = "incr" ] && continue
  member_dir="$repo_root/$member"
  if [ ! -d "$member_dir" ]; then
    echo "MISSING: workspace member directory $member_dir"
    fail=1
    continue
  fi

  # Invariant A: scan every package manifest in the member for deep imports.
  while IFS= read -r pkg; do
    if extract_imports "$pkg" | grep -E '^dowdiness/incr/' | grep -q .; then
      echo "FAIL: $pkg imports a dowdiness/incr subpackage (facade-only rule: import \"dowdiness/incr\" root)"
      fail=1
    fi
  done < <(find "$member_dir" -name 'moon.pkg' -o -name 'moon.pkg.json')

  # Invariant B: pinned dowdiness/incr version must equal the library version.
  member_mod=""
  for candidate in "$member_dir/moon.mod" "$member_dir/moon.mod.json"; do
    [ -f "$candidate" ] && member_mod="$candidate" && break
  done
  [ -n "$member_mod" ] || continue
  # Two pin syntaxes: moon.mod TOML-style `"dowdiness/incr@X"` and legacy
  # moon.mod.json JSON-style `"dowdiness/incr": "X"`.
  pins=$({
    grep -oE '"dowdiness/incr@[^"]+"' "$member_mod" | sed 's/.*@//; s/"$//'
    grep -oE '"dowdiness/incr"[[:space:]]*:[[:space:]]*"[^"]+"' "$member_mod" \
      | sed 's/.*:[[:space:]]*"//; s/"$//'
  } 2>/dev/null || true)
  for pin in $pins; do
    if [ "$pin" != "$lib_version" ]; then
      echo "FAIL: $member_mod pins dowdiness/incr@$pin but incr/moon.mod is $lib_version"
      fail=1
    fi
  done
done

exit "$fail"
