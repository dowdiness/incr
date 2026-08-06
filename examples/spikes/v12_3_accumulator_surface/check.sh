#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root"
probe="examples/spikes/v12_3_accumulator_surface/consumer/negative_probe.mbt"
output=$(mktemp)
cleanup() {
  rm -f "$probe" "$output"
}
trap cleanup EXIT HUP INT TERM

printf '%s\n' '=== positive surface scenarios ==='
positive=$(NEW_MOON_MOD=0 moon run examples/spikes/v12_3_accumulator_surface/consumer 2>&1)
printf '%s\n' "$positive"
grep -Fq 'positive_probes=PASS' <<<"$positive"

printf '%s\n' '' '=== current-engine rollback oracle ==='
NEW_MOON_MOD=0 moon test incr/cells/accumulator_wbtest.mbt \
  --release \
  -f '*ON_ABORT restores prior buffer*'
printf '%s\n' 'rollback_oracle=PASS'

probe_case() {
  local name=$1
  local expected=$2
  local body=$3
  {
    printf '///|\n'
    printf 'fn probe() -> Unit {\n%s\n}\n' "$body"
  } >"$probe"
  : >"$output"
  NEW_MOON_MOD=0 moon check \
    examples/spikes/v12_3_accumulator_surface/consumer \
    >"$output" 2>&1 || true
  if ! grep -Fq "Error: [$expected]" "$output"; then
    printf 'negative=%s expected=%s\n' "$name" "$expected"
    cat "$output"
    exit 1
  fi
  printf 'negative=%s diagnostic=%s\n' "$name" "$expected"
}

printf '%s\n' '' '=== expected compile failures ==='
probe_case contribution_call 4014 '  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator()
  let (_, contribution) = accumulator.derived(store, () => 1)
  contribution()'
probe_case contribution_push 4015 '  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator()
  let (_, contribution) = accumulator.derived(store, () => 1)
  contribution.push(1)'
probe_case accumulator_call 4014 '  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator()
  accumulator()'
probe_case accumulator_read 4015 '  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator()
  accumulator.read()'
probe_case contribution_literal 4036 '  let contribution : @provider.Contribution[Int] = {
    values: () => [],
    snapshot: () => [],
  }
  ignore(contribution)'
probe_case private_field_mutation 4091 '  let store = @provider.Store()
  let accumulator : @provider.Accumulator[Int] = store.accumulator()
  accumulator.raw = accumulator.raw'

printf '%s\n' 'negative_probes=PASS' 'verdict=PASS_WITH_CONSTRAINTS'
