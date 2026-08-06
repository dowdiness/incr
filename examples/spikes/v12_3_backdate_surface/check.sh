#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
spike=examples/spikes/v12_3_backdate_surface
probe="$root/$spike/consumer/negative_probe.mbt"

cleanup() {
  rm -f "$probe"
}
trap cleanup EXIT

cd "$root"
echo '=== positive runtime probes ==='
NEW_MOON_MOD=0 moon run "$spike/consumer" --target native

expect_failure() {
  local disabled=$1
  local message=$2
  local output
  cp "$disabled" "$probe"
  set +e
  output=$(NEW_MOON_MOD=0 moon check "$spike/consumer" 2>&1)
  local status=$?
  set -e
  rm -f "$probe"
  printf '\n=== expected compile failure: %s ===\n%s\n' "$(basename "$disabled")" "$output"
  if [[ $status -eq 0 ]]; then
    echo "expected compilation to fail" >&2
    exit 1
  fi
  grep -Fq 'Error: [4018]' <<<"$output"
  grep -Fq "$message" <<<"$output"
}

expect_failure "$root/$spike/consumer/negative_common_non_eq.mbt.disabled" \
  "does not implement trait Eq"
expect_failure "$root/$spike/consumer/negative_missing_backdate_eq.mbt.disabled" \
  "does not implement trait @dowdiness/incr/types.BackdateEq"

echo
echo 'negative_probes=PASS'
echo 'verdict=PASS_WITH_CONSTRAINTS'
