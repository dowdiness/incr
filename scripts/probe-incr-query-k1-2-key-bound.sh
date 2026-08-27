#!/usr/bin/env bash
# Reproduce the K1.2 public Hash/Eq-bound interface comparison.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base="0c5ae4e50622f55b288aa536722e3ac77a71e030"
toolchain="0.10.4+ade96c819"
binary_sha256="5cce093c6795211fcade5e5ff697d88ec4ff416d2785197f004188aca724a753"
core_sha256="e2bf3cc765412055242384fb72a618b62ad4889eae11956251ff921839d022d2"
tmp=$(mktemp -d)
consumer=""
cleanup() {
  if [ -n "$consumer" ] && [ -e "$consumer/.git" ]; then
    git -C "$repo" worktree remove --force "$consumer" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

version_path="${toolchain//+/%2B}"
binary_uri="https://cli.moonbitlang.com/binaries/${version_path}/moonbit-linux-x86_64.tar.gz"
core_uri="https://cli.moonbitlang.com/cores/core-${version_path}.tar.gz"
binary_tarball="$tmp/moonbit.tar.gz"
core_tarball="$tmp/moonbit-core.tar.gz"
curl --fail --location --retry 3 --silent --show-error \
  --output "$binary_tarball" "$binary_uri"
printf '%s  %s\n' "$binary_sha256" "$binary_tarball" \
  | sha256sum --check --status
mkdir -p "$tmp/moon/bin" "$tmp/moon/lib"
tar -xzf "$binary_tarball" --directory="$tmp/moon"
find "$tmp/moon/bin" -type f -exec chmod +x {} +
echo 'verified MoonBit binary archive'
curl --fail --location --retry 3 --silent --show-error \
  --output "$core_tarball" "$core_uri"
printf '%s  %s\n' "$core_sha256" "$core_tarball" \
  | sha256sum --check --status
tar -xzf "$core_tarball" --directory="$tmp/moon/lib"
echo 'verified MoonBit core archive'
export PATH="$tmp/moon/bin:$PATH"
moon -C "$tmp/moon/lib/core" bundle --warn-list -a --all >/dev/null
moon -C "$tmp/moon/lib/core" bundle --warn-list -a --target wasm-gc \
  --quiet >/dev/null
export NEW_MOON_MOD=0
version_output=$(moon version --all)
printf '%s\n' "$version_output"
grep -Fq 'moon 0.1.20260713 (75c7e1f 2026-07-13)' <<<"$version_output"
grep -Fq 'moonc v0.10.4+ade96c819 (2026-07-13)' <<<"$version_output"
resolved_base=$(git -C "$repo" rev-parse "$base^{commit}")
test "$resolved_base" = "$base"
echo "probe base: $resolved_base"

make_module() {
  local variant=$1
  mkdir -p "$tmp/$variant"
  printf 'name = "probe/%s_bound"\nversion = "0.1.0"\n' "$variant" \
    >"$tmp/$variant/moon.mod"
  : >"$tmp/$variant/moon.pkg"
}

make_module region
cat >"$tmp/region/probe.mbt" <<'EOF'
pub struct Region {}
pub struct View[V] { priv read : () -> V }
pub struct Query[K, V] { priv make_view : (K) -> View[V] }

pub fn[K : Hash + Eq, V] Region::query(
  self : Region,
  compute : (K) -> V,
) -> Query[K, V] {
  ignore(self)
  let memos : Map[K, V] = Map([])
  {
    make_view: key => {
      read: () =>
        match memos.get(key) {
          Some(value) => value
          None => {
            let value = compute(key)
            memos[key] = value
            value
          }
        },
    },
  }
}

pub fn[K, V] Query::at(self : Query[K, V], key : K) -> View[V] {
  (self.make_view)(key)
}
EOF

make_module at
cat >"$tmp/at/probe.mbt" <<'EOF'
pub struct Region {}
pub struct View[V] { priv read : () -> V }
pub struct Query[K, V] {
  priv compute : (K) -> V
  priv memos : Ref[Map[K, V]?]
}

pub fn[K, V] Region::query(
  self : Region,
  compute : (K) -> V,
) -> Query[K, V] {
  ignore(self)
  { compute, memos: Ref(None) }
}

pub fn[K : Hash + Eq, V] Query::at(
  self : Query[K, V],
  key : K,
) -> View[V] {
  let memos = match self.memos.val {
    Some(memos) => memos
    None => {
      let memos : Map[K, V] = Map([])
      self.memos.val = Some(memos)
      memos
    }
  }
  {
    read: () =>
      match memos.get(key) {
        Some(value) => value
        None => {
          let value = (self.compute)(key)
          memos[key] = value
          value
        }
      },
  }
}
EOF

make_module type
cat >"$tmp/type/probe.mbt" <<'EOF'
pub struct Region {}
pub struct View[V] { priv read : () -> V }
pub struct Query[K : Hash + Eq, V] {
  priv compute : (K) -> V
  priv memos : Map[K, V]
}

pub fn[K : Hash + Eq, V] Region::query(
  self : Region,
  compute : (K) -> V,
) -> Query[K, V] {
  ignore(self)
  { compute, memos: Map([]) }
}

pub fn[K : Hash + Eq, V] Query::at(
  self : Query[K, V],
  key : K,
) -> View[V] {
  {
    read: () =>
      match self.memos.get(key) {
        Some(value) => value
        None => {
          let value = (self.compute)(key)
          self.memos[key] = value
          value
        }
      },
  }
}
EOF

for variant in region at; do
  (
    cd "$tmp/$variant"
    moon fmt >/dev/null
    moon check >/dev/null
    moon info >/dev/null
    echo "=== $variant-bound interface ==="
    grep -E '^pub (struct Query|fn.*Region::query|fn.*Query::at)' \
      pkg.generated.mbti
  )
done

if (cd "$tmp/type" && moon check) >"$tmp/type.log" 2>&1; then
  echo "FAIL: Query type-bound probe unexpectedly compiled" >&2
  exit 1
fi
grep -Fq 'Error: [3002]' "$tmp/type.log"
echo '=== type-bound result ==='
grep -F -m1 'Parse error' "$tmp/type.log"

consumer="$tmp/consumer"
git -C "$repo" worktree add --detach "$consumer" "$base" >/dev/null
python3 - "$consumer/incr_next/query.mbt" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
old = "pub fn[K, V] Region::query("
if source.count(old) != 1:
    raise SystemExit("unexpected Region::query source shape")
path.write_text(source.replace(old, "pub fn[K : Hash + Eq, V] Region::query("))
PY
(
  cd "$consumer/incr_next"
  moon fmt >/dev/null
  moon info >/dev/null
)
echo '=== exact-base public delta ==='
git -C "$consumer" diff -- incr_next/pkg.generated.mbti
(
  cd "$consumer/incr"
  moon update >/dev/null
)
(
  cd "$consumer"
  moon test incr_next >"$tmp/kernel-tests.log" 2>&1
  moon test incr_next_testkit/differential >"$tmp/differential-tests.log" 2>&1
)
grep -Fq 'Total tests: 26, passed: 26, failed: 0.' "$tmp/kernel-tests.log"
grep -Fq 'Total tests: 5, passed: 5, failed: 0.' "$tmp/differential-tests.log"
grep -F 'Total tests:' "$tmp/kernel-tests.log"
grep -F 'Total tests:' "$tmp/differential-tests.log"
