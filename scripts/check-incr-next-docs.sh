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

module_imports=$(
  awk '
    /^[[:space:]]*import[[:space:]]*\{/ { block = 1; next }
    block && /^[[:space:]]*}/ { block = 0; next }
    block {
      line = $0
      while (match(line, /"[^"]+"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$docs/moon.mod"
)
if [ "$module_imports" != 'dowdiness/incr_next@0.1.0-alpha.1' ]; then
  echo "FAIL: $docs/moon.mod must depend only on dowdiness/incr_next@0.1.0-alpha.1" >&2
  exit 1
fi

while IFS= read -r pkg; do
  package_imports=$(
    awk '
      /^[[:space:]]*import[[:space:]]*\{/ { block = 1; next }
      block && /^[[:space:]]*}/ { block = 0; next }
      block {
        line = $0
        while (match(line, /"[^"]+"/)) {
          value = substr(line, RSTART + 1, RLENGTH - 2)
          if (value != "test") print value
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$pkg"
  )
  if [ "$package_imports" != 'dowdiness/incr_next' ]; then
    echo "FAIL: $pkg must import only the dowdiness/incr_next public package" >&2
    exit 1
  fi
done < <(find "$docs" -name moon.pkg -type f -print | sort)

mapfile -t checked_docs < <(find "$docs" -name '*.mbt.md' -type f -print | sort)
if [ "${#checked_docs[@]}" -lt 2 ]; then
  echo "FAIL: expected successful and expected-divergence checked docs" >&2
  exit 1
fi

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
