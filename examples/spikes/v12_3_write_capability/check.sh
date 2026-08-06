#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
spike=examples/spikes/v12_3_write_capability
consumer_probe="$root/$spike/consumer/negative_probe.mbt"
provider_probe="$root/$spike/provider/negative_probe.mbt"

cleanup() {
  rm -f "$consumer_probe" "$provider_probe"
}
trap cleanup EXIT

cd "$root"
echo '=== positive runtime probes ==='
NEW_MOON_MOD=0 moon run "$spike/consumer" --target native

expect_failure() {
  local disabled=$1
  local probe=$2
  local package=$3
  local code=$4
  local message=$5
  local output
  cp "$disabled" "$probe"
  set +e
  output=$(NEW_MOON_MOD=0 moon check "$package" 2>&1)
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

expect_failure "$root/$spike/consumer/negative_non_eq_set.mbt.disabled" \
  "$consumer_probe" "$spike/consumer" 4018 "does not implement trait Eq"
expect_failure "$root/$spike/consumer/negative_view_write.mbt.disabled" \
  "$consumer_probe" "$spike/consumer" 4015 "has no method set"
expect_failure "$root/$spike/consumer/negative_write_read.mbt.disabled" \
  "$consumer_probe" "$spike/consumer" 4014 "function type"
expect_failure "$root/$spike/consumer/negative_private_construct.mbt.disabled" \
  "$consumer_probe" "$spike/consumer" 4036 "Cannot create values of the read-only type"
expect_failure "$root/$spike/consumer/negative_private_mutate.mbt.disabled" \
  "$consumer_probe" "$spike/consumer" 4091 "has no field input"
expect_failure "$root/$spike/provider/negative_current_read_error.mbt.disabled" \
  "$provider_probe" "$spike/provider" 4127 "is not an error type"

echo
echo 'negative_probes=PASS'
echo 'verdict=PASS_WITH_CONSTRAINTS'
