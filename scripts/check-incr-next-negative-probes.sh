#!/usr/bin/env bash
set -euo pipefail

root="${INCR_NEXT_ROOT:-incr_next}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R "$root" "$tmp/kernel"
for probe in "$tmp/kernel"/negative/*.mbt.disabled; do
  candidate="${probe%.disabled}"
  cp "$probe" "$candidate"
  if (cd "$tmp/kernel" && moon check negative) >"$tmp/output" 2>&1; then
    echo "FAIL: negative probe unexpectedly compiled: $probe" >&2
    exit 1
  fi
  rm -f "$candidate"
done
echo "Incr Next negative capability probes: PASS"
