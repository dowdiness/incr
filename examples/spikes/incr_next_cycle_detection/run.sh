#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SPIKE=examples/spikes/incr_next_cycle_detection
NEG="$SPIKE/negative"
TMP="$NEG/probe.mbt"
trap 'rm -f "$TMP"' EXIT

printf '%s\n' '== issue #463 invocation-level cycle evidence =='
moon fmt "$SPIKE"
moon info "$SPIKE/fresh_provider" "$SPIKE/incremental_provider" \
  "$SPIKE/consumer" "$SPIKE/native_rc" "$NEG"

printf '%s\n' '-- cycle-aware provider and consumer checks --'
moon check --target wasm-gc "$SPIKE/fresh_provider" \
  "$SPIKE/incremental_provider" "$SPIKE/consumer"
moon check --target native "$SPIKE/fresh_provider" \
  "$SPIKE/incremental_provider" "$SPIKE/consumer"

printf '%s\n' '-- native acyclic and cycle parity --'
moon run "$SPIKE/consumer" --target native
printf '%s\n' '-- wasm-gc acyclic and cycle parity --'
moon run "$SPIKE/consumer" --target wasm-gc

printf '%s\n' '-- unchanged prior evidence executables --'
moon run examples/spikes/incr_next_fresh_evaluator/consumer --target native
moon run examples/spikes/incr_next_incremental_parity/consumer --target native

printf '%s\n' '-- native RC cycle ownership evidence --'
moon check --target native "$SPIKE/native_rc"
moon run "$SPIKE/native_rc" --target native

printf '%s\n' '-- expected compiler boundaries --'
run_negative() {
  local name="$1"
  local code="$2"
  cp "$NEG/$name.mbt.disabled" "$TMP"
  set +e
  local output
  output=$(moon check --target wasm-gc "$NEG" 2>&1)
  local status=$?
  set -e
  rm -f "$TMP"
  printf '%s\n' "$output"
  if [[ "$status" -eq 0 ]] ||
    ! grep -Fq "Error: [$code]" <<<"$output" ||
    ! grep -Fq '/negative/probe.mbt:' <<<"$output"; then
    printf 'negative probe failed: %s (expected [%s])\n' "$name" "$code" >&2
    exit 1
  fi
  printf 'negative %s: PASS ([%s])\n' "$name" "$code"
}
run_negative external_view_literal 4036
run_negative external_eval_ctx_literal 4036
run_negative external_eval_ctx_constructor 4021
run_negative external_transaction_literal 4036
run_negative external_transaction_constructor 4021
run_negative view_get 4015
run_negative view_read 4015
run_negative view_call 4014
run_negative source_set 4015
run_negative eval_id_accessor 4015

printf '%s\n' '-- documentation, workspace, and prior-tree boundaries --'
./scripts/check-documentation-boundaries.py
grep -Fq 'old verification Cycle → RecomputeRequired' "$SPIKE/README.md"
git diff --exit-code 4e2e265 -- examples/spikes/incr_next_fresh_evaluator
git diff --cached --exit-code 4e2e265 -- examples/spikes/incr_next_fresh_evaluator
git diff --exit-code d54e780 -- examples/spikes/incr_next_incremental_parity
git diff --cached --exit-code d54e780 -- examples/spikes/incr_next_incremental_parity
if git status --short -- examples/spikes/incr_next_fresh_evaluator \
  examples/spikes/incr_next_incremental_parity | grep -q .; then
  printf '%s\n' 'forbidden #461/#462 working-tree change detected' >&2
  exit 1
fi
changed_paths=$({
  git diff --name-only d54e780...HEAD
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)
forbidden_paths=$(grep -Ev '^(moon\.work|examples/spikes/README\.md|examples/spikes/incr_next_cycle_detection(/.*)?)$' <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the issue #463 allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi
printf '%s\n' 'documentation/workspace/#461/#462 boundaries: PASS'
printf '%s\n' 'harness state: fmt=PASS info=PASS checks=PASS native=PASS wasm=PASS prior=PASS native_rc=PASS negatives=PASS boundaries=PASS'
printf '%s\n' 'constrained verdict: PASS — invocation-level cycles are structured, cleaned, and parity-checked without changing prior evidence.'
