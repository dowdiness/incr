#!/usr/bin/env bash
# Known-negative controls for check-incr-next-boundaries.sh.
set -euo pipefail

checker="$(cd "$(dirname "$0")" && pwd)/check-incr-next-boundaries.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/incr_next" "$tmp/incr_next_testkit"/{model,fresh,incremental_adapter}
cat > "$tmp/moon.work" <<'EOF'
members = ["./incr_next", "./incr_next_testkit"]
EOF
printf 'name = "dowdiness/incr_next"\n' > "$tmp/incr_next/moon.mod"
printf 'name = "dowdiness/incr_next_testkit"\n' > "$tmp/incr_next_testkit/moon.mod"
for p in "$tmp/incr_next/moon.pkg" "$tmp/incr_next_testkit/model/moon.pkg" \
  "$tmp/incr_next_testkit/fresh/moon.pkg" "$tmp/incr_next_testkit/incremental_adapter/moon.pkg"; do
  : > "$p"
done
printf 'import { "dowdiness/incr_next" }\n' > "$tmp/incr_next_testkit/incremental_adapter/moon.pkg"
INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker"

printf 'import { "dowdiness/incr_next_testkit/model" }\n' > "$tmp/incr_next_testkit/fresh/moon.pkg"
printf 'import { "dowdiness/incr_next" }\n' > "$tmp/incr_next_testkit/model/moon.pkg"
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: transitive Fresh negative control was not rejected" >&2
  exit 1
fi
printf 'import { "dowdiness/incr_next" }\n' > "$tmp/incr_next_testkit/fresh/moon.pkg"
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: direct Fresh negative control was not rejected" >&2
  exit 1
fi
echo "Incr Next boundary self-test: PASS"
