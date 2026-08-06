#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SPIKE=examples/spikes/incr_next_fresh_evaluator
NEG="$SPIKE/negative"
TMP="$NEG/probe.mbt"
trap 'rm -f "$TMP"' EXIT

printf '%s\n' '== issue #461 fresh evaluator evidence =='
moon fmt "$SPIKE"
moon info "$SPIKE/provider" "$SPIKE/consumer" "$SPIKE/native_rc" "$NEG"

printf '%s\n' '-- provider/consumer checks --'
moon check --target wasm-gc "$SPIKE/provider" "$SPIKE/consumer"
moon check --target native "$SPIKE/consumer"

printf '%s\n' '-- native fresh semantics --'
moon run "$SPIKE/consumer" --target native
printf '%s\n' '-- wasm-gc fresh semantics --'
moon run "$SPIKE/consumer" --target wasm-gc

printf '%s\n' '-- native RC ownership evidence --'
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
    printf 'negative probe failed: %s (expected [%s] at copied probe)\n' "$name" "$code" >&2
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

printf '%s\n' '-- documentation/workspace boundaries --'
./scripts/check-documentation-boundaries.py
grep -Fq 'No replacement-kernel authorization and no ADR' "$SPIKE/README.md"
if {
  git diff --name-only origin/main...HEAD
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u | grep -Eq '^(incr/|docs/)'; then
  printf '%s\n' 'forbidden committed, staged, unstaged, or untracked production/canonical-doc change detected' >&2
  exit 1
fi
printf '%s\n' 'documentation boundaries: PASS'
printf '%s\n' 'harness state: fmt=PASS info=PASS checks=PASS fresh_native=PASS fresh_wasm=PASS native_rc=PASS negatives=PASS boundaries=PASS'
printf '%s\n' 'constrained verdict: PASS — memo-free FreshEval and atomic Transaction semantics are executable; no incremental kernel is authorized.'
