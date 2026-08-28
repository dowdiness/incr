#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../../.." && pwd)
module=examples/spikes/incr_query_nodeflow_kernel
provider="$module/nodeflow"
consumer="$module/consumer"
interface="$repo/$provider/pkg.generated.mbti"
kernel_interface="$repo/incr_query/kernel/pkg.generated.mbti"

cd "$repo"

kernel_before=$(sha256sum "$kernel_interface")
interface_before=$(sha256sum "$interface")
NEW_MOON_MOD=0 moon fmt --check "$provider" "$consumer"
NEW_MOON_MOD=0 moon info "$provider"
interface_after=$(sha256sum "$interface")
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
