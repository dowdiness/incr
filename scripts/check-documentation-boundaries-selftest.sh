#!/usr/bin/env bash
# Regression controls for scripts/check-documentation-boundaries.py.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
checker="$repo_root/scripts/check-documentation-boundaries.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cd "$tmp"
git init -q
mkdir -p docs example
cat > moon.work <<'EOF'
members = [
  "./docs",
  "./example",
]
EOF
printf '# Root\n' > README.md
printf '# Docs\n' > docs/README.md
printf '# Example\n' > example/README.md
git add .

python3 "$checker"

expect_failure() {
  local message="$1"
  if python3 "$checker" >"$tmp/output" 2>&1; then
    echo "FAIL: expected documentation checker failure: $message" >&2
    exit 1
  fi
  if ! grep -Fq "$message" "$tmp/output"; then
    echo "FAIL: expected error not found: $message" >&2
    cat "$tmp/output" >&2
    exit 1
  fi
}

mkdir docs/archive
expect_failure 'docs/archive/ must not exist'
rmdir docs/archive

rm example/README.md
git add -A
expect_failure 'example: lacks README.md or README.mbt.md'
printf '# Example\n' > example/README.md

printf '[missing](missing.md)\n' > docs/broken.md
git add -A
expect_failure 'docs/broken.md:missing.md'

printf '[missing line link](missing.md:12)\n' > docs/broken.md
git add -A
expect_failure 'docs/broken.md:missing.md:12'
printf '[ok](README.md:1)\n' > docs/broken.md
git add -A
python3 "$checker"
printf '[ok](README%2Emd:1)\n' > docs/broken.md
git add -A
python3 "$checker"
rm docs/broken.md
git add -A

echo 'Documentation boundary checker self-test OK.'
