#!/usr/bin/env bash
# Enforce the physical Incr Query product-family layout without changing module identities.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
fail=0

module_roots=(kernel testkit docs consumer_probe)
module_names=(
  dowdiness/incr_query
  dowdiness/incr_query_testkit
  dowdiness/incr_query_docs
  dowdiness/incr_query_consumer_probe
)
for i in "${!module_roots[@]}"; do
  module_root="${module_roots[$i]}"
  module_name="${module_names[$i]}"
  manifest="$repo/incr_query/$module_root/moon.mod"
  if [ ! -f "$manifest" ]; then
    echo "MISSING: $manifest" >&2
    fail=1
  elif ! grep -Fxq "name = \"$module_name\"" "$manifest"; then
    echo "FAIL: $manifest does not retain module identity $module_name" >&2
    fail=1
  fi
done

for umbrella_manifest in moon.mod moon.pkg; do
  if [ -e "$repo/incr_query/$umbrella_manifest" ]; then
    echo "FAIL: the Incr Query umbrella must not contain $umbrella_manifest" >&2
    fail=1
  fi
done

for legacy_root in incr_query_testkit incr_query_docs incr_query_consumer_probe; do
  if [ -e "$repo/$legacy_root" ]; then
    echo "FAIL: legacy repository-root directory remains: $legacy_root" >&2
    fail=1
  fi
done

expected_members=(
  './incr_query/kernel'
  './incr_query/testkit'
  './incr_query/docs'
  './incr_query/consumer_probe'
)
for member in "${expected_members[@]}"; do
  if ! grep -Fq "\"$member\"" "$repo/moon.work"; then
    echo "FAIL: moon.work is missing member $member" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo 'Incr Query physical layout: PASS'
