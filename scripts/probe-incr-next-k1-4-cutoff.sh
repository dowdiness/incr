#!/usr/bin/env bash
# Reproduce the K1.4 typed cutoff constructor and trait-bound interface probe.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base="f875e5326df3659674cd8574f947322ec960caaf"
toolchain="0.10.4+ade96c819"
binary_sha256="5cce093c6795211fcade5e5ff697d88ec4ff416d2785197f004188aca724a753"
core_sha256="e2bf3cc765412055242384fb72a618b62ad4889eae11956251ff921839d022d2"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

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
export NEW_MOON_MOD=0
moon -C "$tmp/moon/lib/core" bundle --warn-list -a --all >/dev/null 2>&1
moon -C "$tmp/moon/lib/core" bundle --warn-list -a --target wasm-gc \
  --quiet >/dev/null 2>&1
version_output=$(moon version --all)
printf '%s\n' "$version_output"
grep -Fq 'moon 0.1.20260713 (75c7e1f 2026-07-13)' <<<"$version_output"
grep -Fq 'moonc v0.10.4+ade96c819 (2026-07-13)' <<<"$version_output"
resolved_base=$(git -C "$repo" rev-parse "$base^{commit}")
test "$resolved_base" = "$base"
echo "probe base: $resolved_base"

base_interface="$tmp/base.mbti"
git -C "$repo" show "$base:incr_next/pkg.generated.mbti" >"$base_interface"
diff -u "$base_interface" "$repo/incr_next/pkg.generated.mbti" \
  >"$tmp/current-delta" || true
echo '=== exact current-candidate delta ==='
if [ -s "$tmp/current-delta" ]; then
  cat "$tmp/current-delta"
  python3 - "$tmp/current-delta" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
added = [
    line[1:]
    for line in lines
    if line.startswith("+") and not line.startswith("+++") and line != "+"
]
removed = [
    line[1:]
    for line in lines
    if line.startswith("-") and not line.startswith("---") and line != "-"
]
expected = [
    "pub fn[K : Hash + Eq, V] Region::query_always_changed(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]",
    "pub fn[K : Hash + Eq, V : Eq] Region::query_eq(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]",
    "pub fn[K : Hash + Eq, V : CutoffEq] Region::query_type_owned(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]",
    "pub(open) trait CutoffEq {",
    "  fn cutoff_equal(Self, Self) -> Bool",
    "}",
]
if removed or added != expected:
    raise SystemExit(
        f"unexpected public interface delta: removed={removed!r}, added={added!r}"
    )
PY
else
  echo '(empty; production remains at the commissioned K1.4 base)'
fi

make_module() {
  local variant=$1
  mkdir -p "$tmp/$variant/api" "$tmp/$variant/consumer"
  printf 'name = "probe/%s_cutoff"\nversion = "0.1.0"\n' "$variant" \
    >"$tmp/$variant/moon.mod"
  : >"$tmp/$variant/api/moon.pkg"
  cat >"$tmp/$variant/consumer/moon.pkg" <<EOF
import {
  "probe/${variant}_cutoff/api" @api,
}
pkgtype(kind: "executable")
EOF
}

write_common_api() {
  local path=$1
  cat >"$path" <<'EOF'
///|
pub struct Region {
  priv marker : Unit
}

///|
pub fn Region::new() -> Region {
  { marker: () }
}

///|
pub struct Query[K, V] {
  priv marker : Unit
}

///|
pub struct View[V] {
  priv marker : Unit
}

///|
pub struct QueryContext {
  priv marker : Unit
}

///|
pub(all) enum ReadError {
  Probe
} derive(Eq, Debug)

///|
pub(all) enum RegionError {
  Probe
} derive(Eq, Debug)

///|
pub fn[K : Hash + Eq, V] Region::query(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  ignore(self)
  ignore(compute)
  Err(Probe)
}

///|
pub fn[K, V] Query::at(self : Query[K, V], key : K) -> View[V] {
  ignore(self)
  ignore(key)
  { marker: () }
}
EOF
}

make_module a
write_common_api "$tmp/a/api/probe.mbt"
cat >>"$tmp/a/api/probe.mbt" <<'EOF'

///|
pub fn[K : Hash + Eq, V] Region::query_always_changed(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  self.query(compute)
}

///|
pub fn[K : Hash + Eq, V : Eq] Region::query_eq(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  self.query(compute)
}

///|
pub(open) trait CutoffEq {
  fn cutoff_equal(Self, Self) -> Bool
}

///|
pub fn[K : Hash + Eq, V : CutoffEq] Region::query_type_owned(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  self.query(compute)
}
EOF
cat >"$tmp/a/consumer/main.mbt" <<'EOF'
///|
struct NonEq {
  value : Int
}

///|
impl @api.CutoffEq for NonEq with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
fn main {
  let region = @api.Region::new()
  let baseline = region.query((ctx, key : Unit) => {
    ignore(ctx)
    ignore(key)
    Ok(NonEq::{ value: 1 })
  })
  let always = region.query_always_changed((ctx, key : Unit) => {
    ignore(ctx)
    ignore(key)
    Ok(NonEq::{ value: 1 })
  })
  let eq = region.query_eq((ctx, key : Unit) => {
    ignore(ctx)
    ignore(key)
    Ok(1)
  })
  let type_owned = region.query_type_owned((ctx, key : Unit) => {
    ignore(ctx)
    ignore(key)
    Ok(NonEq::{ value: 1 })
  })
  ignore(baseline)
  ignore(always)
  ignore(eq)
  ignore(type_owned)
}
EOF

make_module b
write_common_api "$tmp/b/api/probe.mbt"
python3 - "$tmp/b/api/probe.mbt" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
old = "pub fn[K : Hash + Eq, V] Region::query("
if source.count(old) != 1:
    raise SystemExit("unexpected baseline query shape")
path.write_text(source.replace(old, "pub fn[K : Hash + Eq, V : Eq] Region::query("))
PY
cat >"$tmp/b/consumer/main.mbt" <<'EOF'
///|
struct NonEq {
  value : Int
}

///|
fn main {
  let region = @api.Region::new()
  let baseline = region.query((ctx, key : Unit) => {
    ignore(ctx)
    ignore(key)
    Ok(NonEq::{ value: 1 })
  })
  ignore(baseline)
}
EOF

make_module c
write_common_api "$tmp/c/api/probe.mbt"
cat >>"$tmp/c/api/probe.mbt" <<'EOF'

///|
pub(all) enum CutoffPolicy[V] {
  AlwaysChanged
  Compare((V, V) -> Bool)
}

///|
pub fn[K : Hash + Eq, V] Region::query_with_policy(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
  policy : CutoffPolicy[V],
) -> Result[Query[K, V], RegionError] {
  ignore(policy)
  self.query(compute)
}
EOF
cat >"$tmp/c/consumer/main.mbt" <<'EOF'
///|
struct NonEq {
  value : Int
}

///|
fn main {
  let region = @api.Region::new()
  let query = region.query_with_policy(
    (ctx, key : Unit) => {
      ignore(ctx)
      ignore(key)
      Ok(NonEq::{ value: 1 })
    },
    @api.CutoffPolicy::Compare((left, right) => left.value == right.value),
  )
  ignore(query)
}
EOF

make_module d_standalone
write_common_api "$tmp/d_standalone/api/probe.mbt"
cat >>"$tmp/d_standalone/api/probe.mbt" <<'EOF'

///|
pub(open) trait CutoffEq {
  fn cutoff_equal(Self, Self) -> Bool
}

///|
pub fn[K : Hash + Eq, V : CutoffEq] Region::query_type_owned(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  self.query(compute)
}
EOF
cat >"$tmp/d_standalone/consumer/main.mbt" <<'EOF'
///|
struct NonEq {
  value : Int
}

///|
impl @api.CutoffEq for NonEq with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
fn main {
  let region = @api.Region::new()
  let query = region.query_type_owned((ctx, key : Unit) => {
    ignore(ctx)
    ignore(key)
    Ok(NonEq::{ value: 1 })
  })
  ignore(query)
}
EOF

make_module d_supertrait
write_common_api "$tmp/d_supertrait/api/probe.mbt"
cat >>"$tmp/d_supertrait/api/probe.mbt" <<'EOF'

///|
pub(open) trait CutoffEq : Eq {
  fn cutoff_equal(Self, Self) -> Bool
}

///|
pub fn[K : Hash + Eq, V : CutoffEq] Region::query_type_owned(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  self.query(compute)
}
EOF
cat >"$tmp/d_supertrait/consumer/main.mbt" <<'EOF'
///|
struct NonEq {
  value : Int
}

///|
impl @api.CutoffEq for NonEq with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
fn main {
  let region = @api.Region::new()
  let query = region.query_type_owned((ctx, key : Unit) => {
    ignore(ctx)
    ignore(key)
    Ok(NonEq::{ value: 1 })
  })
  ignore(query)
}
EOF

make_module d_changed_at
write_common_api "$tmp/d_changed_at/api/probe.mbt"
cat >>"$tmp/d_changed_at/api/probe.mbt" <<'EOF'

///|
pub(open) trait HasChangedAt {
  fn changed_at(Self) -> Int
}

///|
pub(open) trait CutoffEq : HasChangedAt {
  fn cutoff_equal(Self, Self) -> Bool
}

///|
pub fn[K : Hash + Eq, V : CutoffEq] Region::query_type_owned(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
) -> Result[Query[K, V], RegionError] {
  self.query(compute)
}
EOF
cat >"$tmp/d_changed_at/consumer/main.mbt" <<'EOF'
///|
struct SemanticValue {
  value : Int
}

///|
impl @api.CutoffEq for SemanticValue with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
fn main {
  let region = @api.Region::new()
  let query = region.query_type_owned((ctx, key : Unit) => {
    ignore(ctx)
    ignore(key)
    Ok(SemanticValue::{ value: 1 })
  })
  ignore(query)
}
EOF

check_module() {
  local variant=$1
  (
    cd "$tmp/$variant"
    moon fmt >/dev/null 2>&1
    moon check >/dev/null 2>&1
    moon info >/dev/null 2>&1
  )
}

for variant in a c d_standalone; do
  check_module "$variant"
done

printf '%s\n' '=== A selected constructors ==='
grep -E '^pub fn\[K|^pub\(open\) trait CutoffEq|^  fn cutoff_equal' \
  "$tmp/a/api/pkg.generated.mbti"
printf '%s\n' '=== C policy leak ==='
grep -E '^pub\(all\) enum CutoffPolicy|^  (AlwaysChanged|Compare)|^pub fn\[K.*Region::query_with_policy' \
  "$tmp/c/api/pkg.generated.mbti"
printf '%s\n' '=== D standalone trait ==='
grep -E '^pub\(open\) trait CutoffEq|^  fn cutoff_equal|^pub fn\[K.*Region::query_type_owned' \
  "$tmp/d_standalone/api/pkg.generated.mbti"

# The Eq-supertrait spelling is a compiling API variant, but its commissioned
# non-Eq consumer must be rejected.
(
  cd "$tmp/d_supertrait"
  moon fmt >/dev/null 2>&1
  moon info api >/dev/null 2>&1
)
printf '%s\n' '=== D Eq-supertrait interface ==='
grep -E '^pub\(open\) trait CutoffEq|^  fn cutoff_equal|^pub fn\[K.*Region::query_type_owned' \
  "$tmp/d_supertrait/api/pkg.generated.mbti" || true
if (cd "$tmp/d_supertrait" && moon check) >"$tmp/d_supertrait.log" 2>&1; then
  echo 'FAIL: Eq-supertrait accepted the commissioned non-Eq consumer' >&2
  exit 1
fi
grep -Fq 'Eq' "$tmp/d_supertrait.log"
echo 'D Eq-supertrait non-Eq consumer: rejected'

(
  cd "$tmp/d_changed_at"
  moon fmt >/dev/null 2>&1
  moon info api >/dev/null 2>&1
)
printf '%s\n' '=== D HasChangedAt-supertrait interface ==='
grep -E '^pub\(open\) trait (CutoffEq|HasChangedAt)|^  fn (cutoff_equal|changed_at)|^pub fn\[K.*Region::query_type_owned' \
  "$tmp/d_changed_at/api/pkg.generated.mbti" || true
if (cd "$tmp/d_changed_at" && moon check) >"$tmp/d_changed_at.log" 2>&1; then
  echo 'FAIL: HasChangedAt-supertrait accepted a consumer without changed_at' >&2
  exit 1
fi
grep -Fq 'HasChangedAt' "$tmp/d_changed_at.log"
echo 'D HasChangedAt-supertrait consumer without changed_at: rejected'

if (cd "$tmp/b" && moon check) >"$tmp/b.log" 2>&1; then
  echo 'FAIL: V:Eq baseline accepted the non-Eq consumer' >&2
  exit 1
fi
grep -Fq 'Eq' "$tmp/b.log"
echo 'B V:Eq baseline non-Eq consumer: rejected'

# Guard the selected generated-interface facts and the intentionally rejected
# public policy shape. The exact whitespace is compiler output, not hand-edited.
grep -Fq 'pub fn[K : Hash + Eq, V] Region::query(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]' \
  "$tmp/a/api/pkg.generated.mbti"
grep -Fq 'pub fn[K : Hash + Eq, V] Region::query_always_changed(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]' \
  "$tmp/a/api/pkg.generated.mbti"
grep -Fq 'pub fn[K : Hash + Eq, V : Eq] Region::query_eq(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]' \
  "$tmp/a/api/pkg.generated.mbti"
grep -Fq 'pub fn[K : Hash + Eq, V : CutoffEq] Region::query_type_owned(Self, (QueryContext, K) -> Result[V, ReadError]) -> Result[Query[K, V], RegionError]' \
  "$tmp/a/api/pkg.generated.mbti"
grep -Fq 'pub(open) trait CutoffEq {' "$tmp/a/api/pkg.generated.mbti"
grep -Fq 'Compare((V, V) -> Bool)' "$tmp/c/api/pkg.generated.mbti"
grep -Fq 'pub fn[K : Hash + Eq, V] Region::query_with_policy' "$tmp/c/api/pkg.generated.mbti"
grep -Fq 'pub(open) trait CutoffEq {' "$tmp/d_standalone/api/pkg.generated.mbti"
grep -Fq 'pub(open) trait CutoffEq : Eq {' "$tmp/d_supertrait/api/pkg.generated.mbti" || {
  echo 'D Eq-supertrait generated interface did not contain expected spelling:' >&2
  cat "$tmp/d_supertrait/api/pkg.generated.mbti" >&2
  exit 1
}
grep -Fq 'pub(open) trait CutoffEq : HasChangedAt {' \
  "$tmp/d_changed_at/api/pkg.generated.mbti" || {
  echo 'D HasChangedAt-supertrait interface did not contain expected spelling:' >&2
  cat "$tmp/d_changed_at/api/pkg.generated.mbti" >&2
  exit 1
}

echo 'K1.4 typed cutoff constructor interface probe: PASS'
