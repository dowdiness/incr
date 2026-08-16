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
cat > "$tmp/incr_next_testkit/incremental_adapter/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next",
}
EOF
INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker"

cat > "$tmp/incr_next/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next_testkit/model" @model,
  "dowdiness/incr_next_testkit/fresh" @fresh,
  "moonbitlang/quickcheck/gen" @gen,
} for "wbtest"
EOF
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: permanent kernel wbtest evidence import was not rejected" >&2
  exit 1
fi
: > "$tmp/incr_next/moon.pkg"
cat >> "$tmp/incr_next/moon.mod" <<'EOF'
import {
  "dowdiness/incr_next_testkit@0.1.0-alpha.1",
}
EOF
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: kernel module evidence dependency was not rejected" >&2
  exit 1
fi
printf 'name = "dowdiness/incr_next"\n' > "$tmp/incr_next/moon.mod"

cat > "$tmp/incr_next/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next_testkit/model",
}
EOF
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: normal testkit import was not rejected" >&2
  exit 1
fi
cat > "$tmp/incr_next/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next_testkit/model",
} for "test"
EOF
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: black-box testkit import was not rejected" >&2
  exit 1
fi
cat > "$tmp/incr_next/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next_testkit/incremental_adapter",
} for "wbtest"
EOF
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: forbidden wbtest adapter import was not rejected" >&2
  exit 1
fi
: > "$tmp/incr_next/moon.pkg"

cat > "$tmp/incr_next_testkit/fresh/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next_testkit/model",
}
EOF
cat > "$tmp/incr_next_testkit/model/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next",
}
EOF
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: transitive Fresh negative control was not rejected" >&2
  exit 1
fi
cat > "$tmp/incr_next_testkit/fresh/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next",
}
EOF
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: direct Fresh negative control was not rejected" >&2
  exit 1
fi
cat > "$tmp/incr_next_testkit/fresh/moon.pkg" <<'EOF'
import {
  "external/workspace-indirection",
}
EOF
if INCR_NEXT_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: external Fresh negative control was not rejected" >&2
  exit 1
fi
echo "Incr Next boundary self-test: PASS"
