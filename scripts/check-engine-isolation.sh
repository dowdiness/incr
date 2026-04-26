#!/usr/bin/env bash
# scripts/check-engine-isolation.sh
# Asserts internal-package isolation rules for the incr library.
set -euo pipefail

fail=0
# Engine siblings — sibling-isolation rule (invariant 1) applies to these.
engines=(pull push datalog)
# All internal packages — back-edge rule (invariant 3) applies to all of these,
# and invariant 4 forbids them from importing kernel.
internals=(pull push datalog shared kernel)

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

# Invariant 2: internal/shared imports no other internal packages
# (no engine, no kernel — shared is the leaf the rest of internal/ rests on).
# The back-edge check for shared is covered by invariant 3 below; invariant 4
# covers shared not importing kernel.
shared_pkg="cells/internal/shared/moon.pkg"
if [ -f "$shared_pkg" ]; then
  imports=$(extract_imports "$shared_pkg")
  for other in "${engines[@]}"; do
    if echo "$imports" | grep -Fxq "dowdiness/incr/cells/internal/$other"; then
      echo "FAIL: cells/internal/shared imports cells/internal/$other"
      fail=1
    fi
  done
else
  echo "MISSING: $shared_pkg"
  fail=1
fi

# Invariant 3: no back-edges from any internal/* (engines, shared, kernel) to cells/.
for pkg_name in "${internals[@]}"; do
  pkg="cells/internal/$pkg_name/moon.pkg"
  [ -f "$pkg" ] || continue
  imports=$(extract_imports "$pkg")
  # Any import starting with "dowdiness/incr/cells" that is NOT a
  # "dowdiness/incr/cells/internal/..." path counts as a back-edge.
  if echo "$imports" | grep -E '^dowdiness/incr/cells($|/)' | grep -vE '^dowdiness/incr/cells/internal($|/)' | grep -q .; then
    echo "FAIL: cells/internal/$pkg_name imports cells/ (back-edge)"
    fail=1
  fi
done

# Invariant 4: kernel is one-way — engines/shared must not import kernel.
# Only cells/*.mbt (top level) may import @kernel, otherwise we form a cycle
# with invariant 3 (kernel imports the engines + shared).
for pkg_name in "${engines[@]}" shared; do
  pkg="cells/internal/$pkg_name/moon.pkg"
  [ -f "$pkg" ] || continue
  imports=$(extract_imports "$pkg")
  if echo "$imports" | grep -Fxq 'dowdiness/incr/cells/internal/kernel'; then
    echo "FAIL: cells/internal/$pkg_name imports cells/internal/kernel (must be cells/*.mbt only)"
    fail=1
  fi
done

exit "$fail"
