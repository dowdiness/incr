#!/usr/bin/env bash
# Check the public-only Incr Next executable documentation and caller-contract examples.
set -euo pipefail

root="${INCR_NEXT_DOCS_ROOT:-.}"
target="${1:-default}"
docs="$root/incr_next_docs"

case "$target" in
  default|native|js|wasm-gc) ;;
  *)
    echo "usage: $0 [default|native|js|wasm-gc]" >&2
    exit 2
    ;;
esac

for required in \
  "$docs/moon.mod" \
  "$docs/moon.pkg" \
  "$docs/README.mbt.md" \
  "$docs/expected_divergence/moon.pkg" \
  "$docs/expected_divergence/README.mbt.md"; do
  if [ ! -f "$required" ]; then
    echo "MISSING: $required" >&2
    exit 1
  fi
done

json_manifest=$(find "$docs" -name moon.pkg.json -type f -print -quit)
if [ -n "$json_manifest" ]; then
  echo "FAIL: $json_manifest uses unsupported moon.pkg.json; Incr Next docs require auditable moon.pkg manifests" >&2
  exit 1
fi

canonical=$(mktemp -d)
trap 'rm -rf "$canonical"' EXIT
cat > "$canonical/moon.mod" <<'EOF'
name = "dowdiness/incr_next_docs"

version = "0.1.0"

readme = "README.mbt.md"

import {
  "dowdiness/incr_next@0.1.0-alpha.1",
}
EOF
if ! cmp -s "$docs/moon.mod" "$canonical/moon.mod"; then
  echo "FAIL: $docs/moon.mod must match the canonical public-only manifest" >&2
  exit 1
fi

cat > "$canonical/moon.pkg" <<'EOF'
import {
  "dowdiness/incr_next",
} for "test"
EOF
while IFS= read -r pkg; do
  if ! cmp -s "$pkg" "$canonical/moon.pkg"; then
    echo "FAIL: $pkg must match the canonical public-only package manifest" >&2
    exit 1
  fi
done < <(find "$docs" -name moon.pkg -type f -print | sort)

mapfile -t checked_docs < <(find "$docs" -name '*.mbt.md' -type f -print | sort)
if [ "${#checked_docs[@]}" -lt 2 ]; then
  echo "FAIL: expected successful and expected-divergence checked docs" >&2
  exit 1
fi

for file in "${checked_docs[@]}"; do
  first_nonempty=$(
    awk 'NF {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      print line
      exit
    }' "$file"
  )
  if [ "$first_nonempty" = '---' ]; then
    echo "FAIL: $file front matter is forbidden in public-only Incr Next docs" >&2
    exit 1
  fi
done

args=()
if [ "$target" != default ]; then
  args=(--target "$target")
fi

for file in "${checked_docs[@]}"; do
  echo "==> moon check ${args[*]} $file"
  moon check "${args[@]}" "$file"
  echo "==> moon test ${args[*]} $file"
  moon test "${args[@]}" "$file"
done
