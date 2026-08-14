#!/usr/bin/env bash
# Reproduce the K1.3 public Cycle witness interface comparison.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base="621180cf460661aa95eb89da58553681688fa502"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export NEW_MOON_MOD=0
moon version --all
resolved_base=$(git -C "$repo" rev-parse "$base^{commit}")
test "$resolved_base" = "$base"
echo "probe base: $resolved_base"

make_module() {
  local variant=$1
  mkdir -p "$tmp/$variant"
  printf 'name = "probe/%s_cycle_witness"\n' "$variant" \
    >"$tmp/$variant/moon.mod"
  : >"$tmp/$variant/moon.pkg"
}

make_module inline
cat >"$tmp/inline/probe.mbt" <<'EOF'
///|
pub(all) enum ReadError {
  Cycle(Array[Int])
} derive(Eq, Debug)
EOF

make_module opaque
cat >"$tmp/opaque/probe.mbt" <<'EOF'
///|
pub struct CycleWitness {
  priv path : Array[Int]
} derive(Eq, Debug)

///|
fn cycle_witness(path : Array[Int]) -> CycleWitness {
  { path: path.copy() }
}

///|
pub fn CycleWitness::path(self : CycleWitness) -> Array[Int] {
  self.path.copy()
}

///|
pub(all) enum ReadError {
  Cycle(CycleWitness)
} derive(Eq, Debug)
EOF

make_module typed
cat >"$tmp/typed/probe.mbt" <<'EOF'
///|
pub struct QueryId {
  priv value : Int
} derive(Eq, Debug)

///|
pub fn QueryId::value(self : QueryId) -> Int {
  self.value
}

///|
pub struct CycleWitness {
  priv path : Array[QueryId]
} derive(Eq, Debug)

///|
pub fn CycleWitness::path(self : CycleWitness) -> Array[QueryId] {
  self.path.copy()
}

///|
pub(all) enum ReadError {
  Cycle(CycleWitness)
} derive(Eq, Debug)
EOF

for variant in inline opaque typed; do
  (
    cd "$tmp/$variant"
    moon fmt >/dev/null
    moon check >/dev/null
    moon info >/dev/null
  )
  echo "=== $variant interface ==="
  grep -E '^pub (struct (CycleWitness|QueryId)|fn (CycleWitness|QueryId)::path|fn QueryId::value|\(all\) enum ReadError)|^  Cycle' \
    "$tmp/$variant/pkg.generated.mbti"
done

inline="$tmp/inline/pkg.generated.mbti"
opaque="$tmp/opaque/pkg.generated.mbti"
typed="$tmp/typed/pkg.generated.mbti"
grep -Fq 'Cycle(Array[Int])' "$inline"
grep -Fq 'pub struct CycleWitness' "$opaque"
grep -Fq 'pub fn CycleWitness::path(Self) -> Array[Int]' "$opaque"
grep -Fq 'Cycle(CycleWitness)' "$opaque"
if grep -Fq 'pub struct QueryId' "$opaque"; then
  echo 'FAIL: opaque witness unexpectedly exposes QueryId' >&2
  exit 1
fi
grep -Fq 'pub struct QueryId' "$typed"
grep -Fq 'pub fn CycleWitness::path(Self) -> Array[QueryId]' "$typed"

base_interface="$tmp/base.mbti"
candidate_interface="$repo/incr_next/pkg.generated.mbti"
git -C "$repo" show "$base:incr_next/pkg.generated.mbti" >"$base_interface"
diff -u "$base_interface" "$candidate_interface" >"$tmp/interface.diff" || true
echo '=== exact candidate public delta ==='
cat "$tmp/interface.diff"
python3 - "$tmp/interface.diff" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
added = [line[1:] for line in lines if line.startswith("+") and not line.startswith("+++")]
removed = [line[1:] for line in lines if line.startswith("-") and not line.startswith("---")]
expected = [
    "pub struct CycleWitness {",
    "  // private fields",
    "} derive(Eq, @debug.Debug)",
    "pub fn CycleWitness::path(Self) -> Array[Int]",
    "",
    "  Cycle(CycleWitness)",
]
if removed or added != expected:
    raise SystemExit(
        f"unexpected public interface delta: removed={removed!r}, added={added!r}"
    )
PY

echo 'K1.3 Cycle witness interface probe: PASS'
