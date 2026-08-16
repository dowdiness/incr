#!/usr/bin/env bash
# Run K1.6 package-private evidence without adding a production testkit edge.
set -euo pipefail

root="${INCR_NEXT_K1_6_ROOT:-.}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/work"
cp -R "$root/incr_next" "$tmp/work/incr_next"
cp -R "$root/incr_next_testkit" "$tmp/work/incr_next_testkit"
cat > "$tmp/work/moon.work" <<'EOF'
members = [
  "./incr_next",
  "./incr_next_testkit",
]
EOF

for fixture in "$tmp/work/incr_next/private_evidence"/*.mbt.disabled; do
  cp "$fixture" "$tmp/work/incr_next/$(basename "${fixture%.disabled}")"
done
cat >> "$tmp/work/incr_next/moon.mod" <<'EOF'

import {
  "dowdiness/incr_next_testkit@0.1.0-alpha.1",
  "moonbitlang/quickcheck@0.14.0",
}
EOF
python3 - "$tmp/work/incr_next/moon.pkg" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
imports = '''import {
  "dowdiness/incr_next_testkit/model",
  "dowdiness/incr_next_testkit/fresh",
  "moonbitlang/core/debug",
  "moonbitlang/quickcheck/gen" @qcgen,
} for "wbtest"

'''
marker = "options("
if marker not in text:
    raise SystemExit("incr_next/moon.pkg has no options block")
path.write_text(text.replace(marker, imports + marker, 1))
PY

cd "$tmp/work"
NEW_MOON_MOD=0 moon fmt --check
for target in default native js wasm-gc; do
  if [ "$target" = default ]; then
    target_args=()
  else
    target_args=(--target "$target")
  fi
  for evidence in \
    incr_next/k1_6_tracer_wbtest.mbt \
    incr_next/k1_6_lifetime_property_wbtest.mbt \
    incr_next/k1_6_work_counts_wbtest.mbt; do
    NEW_MOON_MOD=0 moon test "${target_args[@]}" "$evidence"
  done
done

before=$(sha256sum incr_next/pkg.generated.mbti)
(cd incr_next && NEW_MOON_MOD=0 moon info)
after=$(sha256sum incr_next/pkg.generated.mbti)
if [ "$before" != "$after" ]; then
  echo "FAIL: K1.6 private evidence changed the public interface" >&2
  exit 1
fi
echo "Incr Next K1.6 private evidence: PASS"
