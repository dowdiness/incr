#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../../.." && pwd)
module=examples/spikes/incr_query_nodeflow_kernel
provider="$module/nodeflow"
application="$module/application"
consumer="$module/consumer"
interface="$repo/$provider/pkg.generated.mbti"
application_interface="$repo/$application/pkg.generated.mbti"
kernel_interface="$repo/incr_query/kernel/pkg.generated.mbti"

cd "$repo"

kernel_before=$(sha256sum "$kernel_interface")
application_interface_before=$(sha256sum "$application_interface")
interface_before=$(sha256sum "$interface")
NEW_MOON_MOD=0 moon fmt --check "$application" "$provider" "$consumer"
NEW_MOON_MOD=0 moon info "$application"
NEW_MOON_MOD=0 moon info "$provider"
application_interface_after=$(sha256sum "$application_interface")
interface_after=$(sha256sum "$interface")
if [ "$application_interface_before" != "$application_interface_after" ]; then
  echo 'FAIL: generated application interface was stale before the harness' >&2
  exit 1
fi
if [ "$interface_before" != "$interface_after" ]; then
  echo 'FAIL: generated Nodeflow interface was stale before the harness' >&2
  exit 1
fi

for target in default native js wasm-gc; do
  if [ "$target" = default ]; then
    args=()
  else
    args=(--target "$target")
  fi
  echo "==> Nodeflow $target check/test"
  NEW_MOON_MOD=0 moon check "${args[@]}" "$provider"
  NEW_MOON_MOD=0 moon test "${args[@]}" "$provider"
  NEW_MOON_MOD=0 moon test "${args[@]}" "$consumer"
done

bash "$module/check-negative-probes.sh"

if grep -Eq '@incr_query|dowdiness/incr_query"|RuntimeNode|GraphState|DocumentWire|NumberEvaluation|DisplayActionPreparation' "$interface"; then
  echo 'FAIL: generated Nodeflow interface leaks an Incr Query representation' >&2
  exit 1
fi
if grep -Eq '"dowdiness/incr_query"|/nodeflow' "$application_interface"; then
  echo 'FAIL: generated application interface imports an adapter or kernel' >&2
  exit 1
fi
if ! grep -Fq '"dowdiness/incr_query_nodeflow_kernel/application",' "$interface"; then
  echo 'FAIL: generated Nodeflow interface does not import application' >&2
  exit 1
fi
if grep -Fq '"dowdiness/incr_query",' "$repo/$consumer/moon.pkg"; then
  echo 'FAIL: public consumer imports Incr Query directly' >&2
  exit 1
fi

kernel_after=$(sha256sum "$kernel_interface")
if [ "$kernel_before" != "$kernel_after" ]; then
  echo 'FAIL: Nodeflow evidence changed the Incr Query generated interface' >&2
  exit 1
fi

bash incr_query/tools/check-layout.sh
python3 scripts/check-documentation-boundaries.py
git diff --check

echo 'Nodeflow evidence harness: PASS'
