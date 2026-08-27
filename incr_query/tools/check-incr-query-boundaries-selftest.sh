#!/usr/bin/env bash
# Known-negative controls for check-incr-query-boundaries.sh.
set -euo pipefail

checker="$(cd "$(dirname "$0")" && pwd)/check-incr-query-boundaries.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/incr_query/kernel" "$tmp/incr_query/testkit"/{model,fresh,incremental_adapter}
cat > "$tmp/moon.work" <<'EOF'
members = ["./incr_query/kernel", "./incr_query/testkit"]
EOF
printf 'name = "dowdiness/incr_query"\n' > "$tmp/incr_query/kernel/moon.mod"
printf 'name = "dowdiness/incr_query_testkit"\n' > "$tmp/incr_query/testkit/moon.mod"
for p in "$tmp/incr_query/kernel/moon.pkg" "$tmp/incr_query/testkit/model/moon.pkg" \
  "$tmp/incr_query/testkit/fresh/moon.pkg" "$tmp/incr_query/testkit/incremental_adapter/moon.pkg"; do
  : > "$p"
done
cat > "$tmp/incr_query/testkit/incremental_adapter/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_query",
}
EOF
INCR_QUERY_BOUNDARY_ROOT="$tmp" bash "$checker"

cat > "$tmp/incr_query/kernel/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_query_testkit/model" @model,
  "dowdiness/incr_query_testkit/fresh" @fresh,
  "moonbitlang/quickcheck/gen" @gen,
} for "wbtest"
EOF
if INCR_QUERY_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: permanent kernel wbtest evidence import was not rejected" >&2
  exit 1
fi
: > "$tmp/incr_query/kernel/moon.pkg"
cat >> "$tmp/incr_query/kernel/moon.mod" <<'EOF'
import {
  "dowdiness/incr_query_testkit@0.1.0-alpha.1",
}
EOF
if INCR_QUERY_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: kernel module evidence dependency was not rejected" >&2
  exit 1
fi
printf 'name = "dowdiness/incr_query"\n' > "$tmp/incr_query/kernel/moon.mod"

cat > "$tmp/incr_query/kernel/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_query_testkit/model",
}
EOF
if INCR_QUERY_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: normal testkit import was not rejected" >&2
  exit 1
fi
cat > "$tmp/incr_query/kernel/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_query_testkit/model",
} for "test"
EOF
if INCR_QUERY_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: black-box testkit import was not rejected" >&2
  exit 1
fi
cat > "$tmp/incr_query/kernel/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_query_testkit/incremental_adapter",
} for "wbtest"
EOF
if INCR_QUERY_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: forbidden wbtest adapter import was not rejected" >&2
  exit 1
fi
: > "$tmp/incr_query/kernel/moon.pkg"

cat > "$tmp/incr_query/testkit/fresh/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_query_testkit/model",
}
EOF
cat > "$tmp/incr_query/testkit/model/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_query",
}
EOF
if INCR_QUERY_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: transitive Fresh negative control was not rejected" >&2
  exit 1
fi
cat > "$tmp/incr_query/testkit/fresh/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_query",
}
EOF
if INCR_QUERY_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: direct Fresh negative control was not rejected" >&2
  exit 1
fi
cat > "$tmp/incr_query/testkit/fresh/moon.pkg" <<'EOF'
import {
  "external/workspace-indirection",
}
EOF
if INCR_QUERY_BOUNDARY_ROOT="$tmp" bash "$checker" >/dev/null 2>&1; then
  echo "FAIL: external Fresh negative control was not rejected" >&2
  exit 1
fi
echo "Incr Query boundary self-test: PASS"
