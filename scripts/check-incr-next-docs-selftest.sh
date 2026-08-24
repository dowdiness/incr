#!/usr/bin/env bash
# Negative controls for scripts/check-incr-next-docs.sh manifest enforcement.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/scripts/check-incr-next-docs.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

docs="$fixture/incr_next_docs"
mkdir -p "$docs/expected_divergence" "$fixture/fakebin"
cat > "$docs/moon.mod" <<'EOF'
name = "dowdiness/incr_next_docs"

version = "0.1.0"

readme = "README.mbt.md"

import {
  "dowdiness/incr_next@0.1.0-alpha.1",
}
EOF
for pkg in "$docs/moon.pkg" "$docs/expected_divergence/moon.pkg"; do
  cat > "$pkg" <<'EOF'
import {
  "dowdiness/incr_next",
} for "test"
EOF
done
printf '# Successful docs\n' > "$docs/README.mbt.md"
printf '# Expected divergence\n' > "$docs/expected_divergence/README.mbt.md"
cat > "$fixture/fakebin/moon" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture/fakebin/moon"

run_checker() {
  PATH="$fixture/fakebin:$PATH" INCR_NEXT_DOCS_ROOT="$fixture" \
    "$checker" default
}

expect_failure() {
  local pattern="$1"
  set +e
  output=$(run_checker 2>&1)
  status=$?
  set -e
  if [ "$status" -eq 0 ] || ! grep -Fq "$pattern" <<<"$output"; then
    echo "self-test expected failure containing: $pattern" >&2
    echo "$output" >&2
    exit 1
  fi
}

run_checker >/dev/null
echo "selftest ok: clean public-only fixture passes"

cat > "$docs/expected_divergence/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next_testkit/model",
} for "test"
EOF
expect_failure 'must match the canonical public-only package manifest'
echo "selftest ok: forbidden TOML import fails"

cat > "$docs/expected_divergence/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next",
} for "test"
import { "dowdiness/incr_next_testkit/model" } for "test"
EOF
expect_failure 'must match the canonical public-only package manifest'
echo "selftest ok: inline second import block fails"

cat > "$docs/expected_divergence/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next",
} for "test"
EOF
printf '\n' >> "$docs/expected_divergence/moon.pkg"
expect_failure 'must match the canonical public-only package manifest'
echo "selftest ok: trailing blank line fails byte-exact comparison"

cat > "$docs/expected_divergence/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next",
} for "test"
EOF
cat > "$docs/README.mbt.md" <<'EOF'
---
moonbit:
  import:
    - path: dowdiness/incr_next_testkit/model
      alias: model
---
# Successful docs
EOF
expect_failure 'front matter is forbidden'
echo "selftest ok: front matter moonbit.import fails"
printf '# Successful docs\n' > "$docs/README.mbt.md"

cat > "$docs/expected_divergence/README.mbt.md" <<'EOF'

---
moonbit:
  deps:
    dowdiness/incr_next_testkit: 0.1.0-alpha.1
---
# Expected divergence
EOF
expect_failure 'front matter is forbidden'
echo "selftest ok: front matter moonbit.deps fails"
printf '# Expected divergence\n' > "$docs/expected_divergence/README.mbt.md"

mkdir -p "$docs/legacy"
printf '{}\n' > "$docs/legacy/moon.pkg.json"
expect_failure 'uses unsupported moon.pkg.json'
echo "selftest ok: JSON manifest fails closed"
