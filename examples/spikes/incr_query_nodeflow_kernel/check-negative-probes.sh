#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R "$repo/incr_query/kernel" "$tmp/kernel"
cp -R "$repo/examples/spikes/incr_query_nodeflow_kernel" "$tmp/spike"
rm -rf "$tmp/kernel/_build" "$tmp/spike/_build"
cat >"$tmp/moon.work" <<'WORK'
members = [
  "./kernel",
  "./spike",
]
WORK

expected_diagnostic() {
  case "$1" in
    node_reference_fields.mbt.disabled)
      printf '%s' 'NodeReference has no field node'
      ;;
    parameter_constructor.mbt.disabled)
      printf '%s' 'Cannot create values of the read-only type'
      ;;
    node_parameter_method.mbt.disabled)
      printf '%s' 'NodeReference has no method parameter'
      ;;
    action_reference_fields.mbt.disabled)
      printf '%s' 'ActionReference has no field action'
      ;;
    nodeflow_runtime.mbt.disabled)
      printf '%s' 'Nodeflow has no field runtime'
      ;;
    port_reference_fields.mbt.disabled)
      printf '%s' 'PortReference has no field port'
      ;;
    availability_prepared.mbt.disabled)
      printf '%s' 'which is a variant type and not a struct'
      ;;
    document_fields.mbt.disabled)
      printf '%s' 'GraphDocument has no field wire'
      ;;
    *)
      echo "FAIL: no expected diagnostic for $1" >&2
      return 1
      ;;
  esac
}

for probe in "$tmp/spike"/negative/*.mbt.disabled; do
  candidate="${probe%.disabled}"
  cp "$probe" "$candidate"
  if (cd "$tmp/spike" && NEW_MOON_MOD=0 moon check negative) >"$tmp/output" 2>&1; then
    echo "FAIL: negative probe unexpectedly compiled: $(basename "$probe")" >&2
    exit 1
  fi
  expected=$(expected_diagnostic "$(basename "$probe")")
  if ! grep -Fq "$expected" "$tmp/output"; then
    echo "FAIL: negative probe diagnostic drift: $(basename "$probe")" >&2
    echo "EXPECTED: $expected" >&2
    cat "$tmp/output" >&2
    exit 1
  fi
  rm -f "$candidate"
done

echo 'Nodeflow negative capability probes: PASS'
