#!/usr/bin/env bash
# Build and consume an unpublished Incr Query candidate without source fallback.
set -euo pipefail

repo_root="${INCR_QUERY_K23_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
moon_bin="${MOON_BIN:-moon}"
consumer_moon_bin="${INCR_QUERY_K23_CONSUMER_MOON_BIN:-$moon_bin}"
policy_probe_moon_bin="${INCR_QUERY_K23_POLICY_PROBE_MOON_BIN:-}"
source_only="${INCR_QUERY_K23_SOURCE_ONLY:-0}"
module="$repo_root/incr_query/kernel"
consumer="$repo_root/incr_query/consumer_probe"
expected_files="$module/distribution/package-files.txt"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/k23-dist.XXXXXX")
if [ -n "${INCR_QUERY_K23_OUTPUT_DIR:-}" ]; then
  output="$INCR_QUERY_K23_OUTPUT_DIR"
  rm -rf "$output"
  mkdir -p "$output"
else
  output="$tmp/evidence"
  mkdir -p "$output"
fi
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

for command in cmp diff find grep gzip sed sha256sum sort unzip; do
  require_command "$command"
done
[ -x "$(command -v "$moon_bin" 2>/dev/null || true)" ] || fail "MoonBit packager executable not found: $moon_bin"
[ -x "$(command -v "$consumer_moon_bin" 2>/dev/null || true)" ] || fail "MoonBit consumer executable not found: $consumer_moon_bin"
if [ -n "$policy_probe_moon_bin" ]; then
  [ -x "$(command -v "$policy_probe_moon_bin" 2>/dev/null || true)" ] || fail "MoonBit policy-probe executable not found: $policy_probe_moon_bin"
fi

for required in \
  "$repo_root/LICENSE" \
  "$module/.moonignore" \
  "$module/moon.mod" \
  "$module/moon.pkg" \
  "$module/pkg.generated.mbti" \
  "$module/README.mbt.md" \
  "$expected_files" \
  "$consumer/moon.mod" \
  "$consumer/moon.pkg" \
  "$consumer/main.mbt"; do
  [ -f "$required" ] || fail "required input missing: $required"
done

if find "$module" -type l -print -quit | grep -q .; then
  fail "source module contains a symlink"
fi
if grep -Eq '\]\((\.\.?/|docs/)' "$module/README.mbt.md"; then
  fail "candidate README contains a candidate-external relative link"
fi

for pattern in \
  '*_test.mbt' \
  '*_wbtest.mbt' \
  'evidence/' \
  'distribution/' \
  'negative/' \
  'private_evidence/' \
  'native_rc/*' \
  '!native_rc/rc_probe.c'; do
  grep -Fxq "$pattern" "$module/.moonignore" || fail ".moonignore is missing policy line: $pattern"
done

sorted_expected="$tmp/expected-files.txt"
LC_ALL=C sort -u "$expected_files" > "$sorted_expected"
cmp -s "$expected_files" "$sorted_expected" || fail "package-files.txt must be sorted and duplicate-free"

canonical="$tmp/canonical"
mkdir -p "$canonical"
cat > "$canonical/consumer.moon.mod" <<'EOF'
name = "dowdiness/incr_query_consumer_probe"

version = "0.1.0"

readme = "README.md"

import {
  "dowdiness/incr_query@0.1.0-alpha.1",
}
EOF
cat > "$canonical/consumer.moon.pkg" <<'EOF'
import {
  "dowdiness/incr_query",
}

pkgtype(kind: "executable")
EOF
cmp -s "$consumer/moon.mod" "$canonical/consumer.moon.mod" || fail "consumer moon.mod is not the accepted public-only manifest"
cmp -s "$consumer/moon.pkg" "$canonical/consumer.moon.pkg" || fail "consumer moon.pkg is not the accepted public-only manifest"

{
  echo "source_head=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo unavailable)"
  echo "source_tree=$(git -C "$repo_root" rev-parse 'HEAD^{tree}' 2>/dev/null || echo unavailable)"
  echo "packager_moon_bin=$moon_bin"
  echo "consumer_moon_bin=$consumer_moon_bin"
  echo "publish_invocations=0"
  echo "registry_mutations=0"
  echo
  echo "[packager moon version]"
  "$moon_bin" version --all
  echo
  echo "[consumer moon version]"
  "$consumer_moon_bin" version --all
  if [ -n "$policy_probe_moon_bin" ]; then
    echo
    echo "[policy-probe moon version]"
    "$policy_probe_moon_bin" version --all
  fi
  echo
  echo "[moon package --help]"
  "$moon_bin" package --help
  echo
  echo "[moon publish --help]"
  "$moon_bin" publish --help
} > "$output/tooling.txt" 2>&1
if grep -Fq -- '--dry-run' "$output/tooling.txt"; then
  echo "publish_dry_run=supported-not-executed" >> "$output/tooling.txt"
else
  echo "publish_dry_run=unsupported-not-executed" >> "$output/tooling.txt"
fi

: > "$output/raw-commands.log"
run_capture() {
  local name=$1
  local cwd=$2
  shift 2
  {
    printf '[%s] $ cd %q &&' "$name" "$cwd"
    printf ' %q' "$@"
    printf '\n'
  } >> "$output/raw-commands.log"
  set +e
  (cd "$cwd" && "$@") > "$output/$name.stdout" 2> "$output/$name.stderr"
  local status=$?
  set -e
  {
    printf 'exit=%s\n' "$status"
    cat "$output/$name.stdout"
    cat "$output/$name.stderr"
    printf '\n'
  } >> "$output/raw-commands.log"
  return "$status"
}

build_candidate() {
  local run=$1
  local stage="$tmp/stage-$run"
  local extract="$tmp/extract-$run"
  mkdir -p "$stage" "$extract"
  cp -a "$module"/. "$stage"/
  rm -rf "$stage/_build" "$stage/.mooncakes"
  cp -p "$repo_root/LICENSE" "$stage/LICENSE"
  cmp -s "$repo_root/LICENSE" "$stage/LICENSE" || fail "staged LICENSE differs from repository source"

  run_capture "package-$run" "$stage" "$moon_bin" package --list --frozen || fail "moon package failed in isolated staging run $run"
  mapfile -t archives < <(find "$stage/_build/publish" -maxdepth 1 -name '*.zip' -type f -print)
  [ "${#archives[@]}" -eq 1 ] || fail "expected exactly one candidate archive in run $run"
  local archive=${archives[0]}
  local actual="$tmp/package-files-$run.txt"
  unzip -Z1 "$archive" | LC_ALL=C sort > "$actual"
  if ! cmp -s "$expected_files" "$actual"; then
    diff -u "$expected_files" "$actual" >&2 || true
    fail "candidate archive file manifest differs in run $run"
  fi
  unzip -q "$archive" -d "$extract"
  if find "$extract" -type l -print -quit | grep -q .; then
    fail "candidate archive contains a symlink"
  fi
  if grep -R -a -Fq "$repo_root" "$extract"; then
    fail "candidate archive contains the original repository path"
  fi
  cmp -s "$repo_root/LICENSE" "$extract/LICENSE" || fail "candidate LICENSE differs from repository source"
  sha256sum "$archive" | awk '{print $1}' > "$tmp/archive-$run.sha256"
  (
    cd "$extract"
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
  ) > "$tmp/content-$run.sha256"
  printf '%s\n' "$archive" > "$tmp/archive-$run.path"
}

build_candidate 1
build_candidate 2
cmp -s "$tmp/archive-1.sha256" "$tmp/archive-2.sha256" || fail "candidate ZIP is not byte reproducible"
cmp -s "$tmp/content-1.sha256" "$tmp/content-2.sha256" || fail "candidate extracted content is not reproducible"
cp "$tmp/package-files-1.txt" "$output/package-files.txt"
cp "$tmp/content-1.sha256" "$output/package-content-sha256.txt"
cp "$tmp/archive-1.sha256" "$output/archive-sha256.txt"

if [ -n "$policy_probe_moon_bin" ]; then
  policy_stage="$tmp/policy-probe-stage"
  mkdir -p "$policy_stage"
  cp -a "$module"/. "$policy_stage"/
  rm -rf \
    "$policy_stage/_build" \
    "$policy_stage/.mooncakes" \
    "$policy_stage/distribution/evidence"
  cp -p "$repo_root/LICENSE" "$policy_stage/LICENSE"
  run_capture policy-probe-package "$policy_stage" "$policy_probe_moon_bin" package --list --frozen || fail "policy-probe moon package command failed"
  mapfile -t policy_archives < <(find "$policy_stage/_build/publish" -maxdepth 1 -name '*.zip' -type f -print)
  [ "${#policy_archives[@]}" -eq 1 ] || fail "expected exactly one policy-probe archive"
  unzip -Z1 "${policy_archives[0]}" | LC_ALL=C sort > "$output/policy-probe-package-files.txt"
  {
    "$policy_probe_moon_bin" version --all
    if cmp -s "$expected_files" "$output/policy-probe-package-files.txt"; then
      echo "moonignore_policy=honored"
    else
      echo "moonignore_policy=not-honored"
      diff -u "$expected_files" "$output/policy-probe-package-files.txt" || true
    fi
  } > "$output/policy-probe.txt" 2>&1
fi

if [ "$source_only" = 1 ]; then
  echo "K2.3 source/package policy: PASS"
  echo "evidence=$output"
  exit 0
fi
[ "$source_only" = 0 ] || fail "INCR_QUERY_K23_SOURCE_ONLY must be 0 or 1"

fresh="$tmp/fresh"
mkdir -p "$fresh/candidate" "$fresh/consumer"
unzip -q "$(cat "$tmp/archive-1.path")" -d "$fresh/candidate"
cp -a "$consumer"/. "$fresh/consumer"/
rm -rf "$fresh/consumer/_build" "$fresh/consumer/.mooncakes"
cat > "$fresh/moon.work" <<'EOF'
members = [
  "./candidate",
  "./consumer",
]
EOF

if find "$fresh/candidate" "$fresh/consumer" -type l -print -quit | grep -q .; then
  fail "fresh workspace contains a symlink"
fi
if grep -R -a -Fq "$repo_root" "$fresh/candidate" "$fresh/consumer"; then
  fail "fresh inputs contain the original repository path"
fi

run_capture dependency-tree "$fresh/consumer" "$consumer_moon_bin" tree || fail "fresh dependency tree failed"
cp "$output/dependency-tree.stdout" "$output/dependency-tree.txt"
grep -Fq "local $fresh/candidate" "$output/dependency-tree.txt" || fail "dependency tree does not resolve the unpacked candidate"
if grep -Fq "$repo_root" "$output/dependency-tree.txt"; then
  fail "dependency tree resolved the original repository"
fi

cat > "$tmp/expected-run.txt" <<'EOF'
initial.selected=2
initial.doubled=4

atomic_switch.selected=13
atomic_switch.doubled=26

switch_back.selected=5
switch_back.doubled=10

close.result=ClosedRegion
EOF

for target in default native js wasm-gc; do
  args=()
  if [ "$target" != default ]; then
    args=(--target "$target")
  fi
  run_capture "$target-check" "$fresh" "$consumer_moon_bin" check --frozen "${args[@]}" ./consumer || fail "$target consumer check failed"
  run_capture "$target-test" "$fresh" "$consumer_moon_bin" test --frozen "${args[@]}" ./consumer || fail "$target consumer test failed"
  run_capture "$target-run" "$fresh" "$consumer_moon_bin" run --frozen "${args[@]}" ./consumer || fail "$target consumer run failed"
  cmp -s "$tmp/expected-run.txt" "$output/$target-run.stdout" || fail "$target consumer output differs from the accepted K2.1 behavior"
done

if grep -R -a -Fq "$repo_root" "$fresh"; then
  fail "fresh workspace build metadata contains the original repository path"
fi

rm -rf "$fresh/candidate" "$fresh/_build" "$fresh/.mooncakes" "$fresh/consumer/_build" "$fresh/consumer/.mooncakes"
cat > "$fresh/moon.work" <<'EOF'
members = [
  "./consumer",
]
EOF
if run_capture candidate-absent "$fresh" "$consumer_moon_bin" check --frozen ./consumer; then
  fail "consumer succeeded after the candidate workspace member was removed"
fi
grep -Fq 'dowdiness/incr_query' "$output/candidate-absent.stderr" || fail "candidate-absent control failed for an unrelated reason"

{
  echo "archive_sha256=$(cat "$output/archive-sha256.txt")"
  echo "archive_files=$(wc -l < "$output/package-files.txt")"
  echo "content_manifest_sha256=$(sha256sum "$output/package-content-sha256.txt" | awk '{print $1}')"
  echo "packager_moon_bin=$moon_bin"
  echo "consumer_moon_bin=$consumer_moon_bin"
  echo "targets=default,native,js,wasm-gc"
  echo "candidate_absent=expected-failure"
  echo "source_fallback=not-observed"
  echo "symlinks=0"
  echo "registry_mutations=0"
  echo "result=PASS"
} > "$output/summary.txt"

# Preserve exact command/tooling output as deterministic gzip while keeping a
# whitespace-clean human-readable tooling summary for repository review.
cp "$output/tooling.txt" "$output/tooling.raw.txt"
gzip -n "$output/tooling.raw.txt"
sed -i 's/[[:space:]]\+$//' "$output/tooling.txt"
gzip -n "$output/raw-commands.log"

echo "K2.3 distribution candidate: PASS"
echo "archive_sha256=$(cat "$output/archive-sha256.txt")"
echo "evidence=$output"
