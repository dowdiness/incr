#!/usr/bin/env bash
# Check the K1.1 module and Fresh/incremental package boundary.
set -euo pipefail

root="${INCR_NEXT_BOUNDARY_ROOT:-.}"
fail=0

extract_imports() {
  local file="$1"
  { sed 's|//.*$||; s|#.*$||' "$file" \
      | grep -oE '"[^"]+"' | tr -d '"' | grep -vFx 'test'; } || true
}

if [ ! -f "$root/moon.work" ]; then
  echo "MISSING: $root/moon.work" >&2
  exit 1
fi
for required in "$root/incr_next/moon.mod" "$root/incr_next/moon.pkg" \
  "$root/incr_next_testkit/moon.mod" "$root/incr_next_testkit/model/moon.pkg" \
  "$root/incr_next_testkit/fresh/moon.pkg" \
  "$root/incr_next_testkit/incremental_adapter/moon.pkg"; do
  if [ ! -f "$required" ]; then
    echo "MISSING: $required" >&2
    fail=1
  fi
done

while IFS= read -r pkg; do
  imports=$(extract_imports "$pkg")
  case "$pkg" in
    "$root/incr_next/"*)
      if echo "$imports" | grep -E '^(dowdiness/incr|dowdiness/incr_next_testkit)(/|$)' >/dev/null; then
        echo "FAIL: kernel imports current Incr or testkit: $pkg" >&2
        fail=1
      fi
      ;;
  esac
done < <(find "$root/incr_next" -name moon.pkg -type f -print)

adapter_imports=$(extract_imports "$root/incr_next_testkit/incremental_adapter/moon.pkg")
if ! echo "$adapter_imports" | grep -Fxq 'dowdiness/incr_next'; then
  echo "FAIL: incremental_adapter does not import dowdiness/incr_next" >&2
  fail=1
fi

# Traverse only package manifests reachable from Fresh. This catches a
# transitive fresh -> model -> incr_next edge, not just a direct import.
queue=("$root/incr_next_testkit/fresh")
visited=""
while [ "${#queue[@]}" -gt 0 ]; do
  pkg_dir="${queue[0]}"
  queue=("${queue[@]:1}")
  case " $visited " in *" $pkg_dir "*) continue ;; esac
  visited="$visited $pkg_dir"
  pkg="$pkg_dir/moon.pkg"
  [ -f "$pkg" ] || continue
  while IFS= read -r import; do
    case "$import" in
      dowdiness/incr_next|dowdiness/incr_next/*)
        echo "FAIL: Fresh-reachable package imports kernel: $pkg -> $import" >&2
        fail=1
        ;;
      dowdiness/incr_next_testkit/*)
        sub="${import#dowdiness/incr_next_testkit/}"
        queue+=("$root/incr_next_testkit/$sub")
        ;;
    esac
  done < <(extract_imports "$pkg")
done

if grep -R -n -E 'examples/spikes/incr_next_(keyed_view_recipe|fresh_evaluator)|spike/incr-next' \
  "$root/incr_next" "$root/incr_next_testkit" >/dev/null 2>&1; then
  echo "FAIL: production/testkit path contains an evidence-provider import or materialization" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "Incr Next boundary check: PASS"
