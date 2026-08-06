#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
spike=examples/spikes/v12_3_eager_surface
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
  local code=$2
  local message=$3
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
  grep -Fq "Error: [$code]" <<<"$output"
  grep -Fq "$message" <<<"$output"
}

expect_failure "$root/$spike/consumer/negative_view_stop.mbt.disabled" \
  4015 "has no method stop"
expect_failure "$root/$spike/consumer/negative_stop_read.mbt.disabled" \
  4014 "function type"
expect_failure "$root/$spike/consumer/negative_private_construct.mbt.disabled" \
  4036 "Cannot create values of the read-only type"
expect_failure "$root/$spike/consumer/negative_private_mutate.mbt.disabled" \
  4091 "has no field mount"

echo
echo 'negative_probes=PASS'
echo 'verdict=PASS_WITH_CONSTRAINTS'
