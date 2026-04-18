#!/usr/bin/env bash
# scripts/check-engine-isolation.sh
# Asserts internal-package isolation rules for the incr library.
set -euo pipefail

fail=0
engines=(pull push datalog)

# Extract imports as exact quoted strings from a moon.pkg file.
# Returns each imported package path, one per line, without quotes.
# Handles both `#` and `//` line comments (this repo uses `//`), and
# excludes the `"test"` discriminator from `} for "test"` import blocks.
# No-match from any stage is treated as an empty import list: without the
# `|| true`, `set -o pipefail` would propagate `grep`'s exit 1 out through
# the `imports=$(...)` callers and silently abort the script for packages
# that happen to have no quoted imports.
extract_imports() {
  local file="$1"
  {
    sed 's|//.*$||; s|#.*$||' "$file" \
      | grep -oE '"[^"]+"' \
      | tr -d '"' \
      | grep -vFx 'test'
  } || true
}

# Invariant 1: no cross-engine sibling imports.
for engine in "${engines[@]}"; do
  pkg="cells/internal/$engine/moon.pkg"
  if [ ! -f "$pkg" ]; then
    echo "MISSING: $pkg"
    fail=1
    continue
  fi
  imports=$(extract_imports "$pkg")
  for other in "${engines[@]}"; do
    [ "$engine" = "$other" ] && continue
    if echo "$imports" | grep -Fxq "dowdiness/incr/cells/internal/$other"; then
      echo "FAIL: cells/internal/$engine imports cells/internal/$other"
      fail=1
    fi
  done
done

# Invariant 2: internal/shared is a leaf — no engine imports, no back-edge.
shared_pkg="cells/internal/shared/moon.pkg"
if [ -f "$shared_pkg" ]; then
  imports=$(extract_imports "$shared_pkg")
  for other in "${engines[@]}"; do
    if echo "$imports" | grep -Fxq "dowdiness/incr/cells/internal/$other"; then
      echo "FAIL: cells/internal/shared imports cells/internal/$other"
      fail=1
    fi
  done
  # shared must not back-edge into cells/
  if echo "$imports" | grep -E '^dowdiness/incr/cells($|/)' | grep -vE '^dowdiness/incr/cells/internal($|/)' | grep -q .; then
    echo "FAIL: cells/internal/shared imports cells/ (back-edge)"
    fail=1
  fi
fi

# Invariant 3: no back-edges from any internal/* to cells/.
for engine in shared "${engines[@]}"; do
  pkg="cells/internal/$engine/moon.pkg"
  [ -f "$pkg" ] || continue
  imports=$(extract_imports "$pkg")
  # Any import starting with "dowdiness/incr/cells" that is NOT a
  # "dowdiness/incr/cells/internal/..." path counts as a back-edge.
  if echo "$imports" | grep -E '^dowdiness/incr/cells($|/)' | grep -vE '^dowdiness/incr/cells/internal($|/)' | grep -q .; then
    echo "FAIL: cells/internal/$engine imports cells/ (back-edge)"
    fail=1
  fi
done

exit "$fail"
