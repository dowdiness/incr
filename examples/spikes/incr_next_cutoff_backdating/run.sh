#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SPIKE=examples/spikes/incr_next_cutoff_backdating
NEG="$SPIKE/negative"
TMP="$NEG/probe.mbt"
trap 'rm -f "$TMP"' EXIT

printf '%s\n' '== Incr Next typed cutoff/backdating evidence =='
moon fmt "$SPIKE"
moon info "$SPIKE/fresh_provider" "$SPIKE/incremental_provider" \
  "$SPIKE/consumer" "$SPIKE/native_rc" "$NEG"

printf '%s\n' '-- cutoff-aware provider and consumer checks --'
moon check --target wasm-gc "$SPIKE/fresh_provider" \
  "$SPIKE/incremental_provider" "$SPIKE/consumer"
moon check --target native "$SPIKE/fresh_provider" \
  "$SPIKE/incremental_provider" "$SPIKE/consumer"

printf '%s\n' '-- native exact parity, cutoff, and cycle evidence --'
moon run "$SPIKE/consumer" --target native
printf '%s\n' '-- wasm-gc exact parity, cutoff, and cycle evidence --'
moon run "$SPIKE/consumer" --target wasm-gc

printf '%s\n' '-- unchanged prior evidence executables --'
moon run examples/spikes/incr_next_fresh_evaluator/consumer --target native
moon run examples/spikes/incr_next_incremental_parity/consumer --target native
moon run examples/spikes/incr_next_cycle_detection/consumer --target native

printf '%s\n' '-- native RC cutoff ownership evidence --'
moon check --target native "$SPIKE/native_rc"
moon run "$SPIKE/native_rc" --target native
moon test --target native "$SPIKE/incremental_provider"

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
run_negative arbitrary_cutoff_predicate 4015
run_negative private_cutoff_policy 4024

printf '%s\n' '-- interface, documentation, workspace, and prior-tree boundaries --'
./scripts/check-documentation-boundaries.py
grep -Fq 'false positive' "$SPIKE/README.md"
if rg -n 'CutoffPolicy|HasChangedAt|BackdateEq|TrustedCutoff|query_by' \
  "$SPIKE/fresh_provider/pkg.generated.mbti" \
  "$SPIKE/incremental_provider/pkg.generated.mbti"; then
  printf '%s\n' 'private/legacy cutoff representation leaked through .mbti' >&2
  exit 1
fi
expected_links=$(cat <<'LINKS'
consumer/cycles.mbt -> ../../incr_next_cycle_detection/consumer/cycles.mbt
fresh_provider/core.mbt -> ../../incr_next_cycle_detection/fresh_provider/core.mbt
fresh_provider/ids.mbt -> ../../incr_next_cycle_detection/fresh_provider/ids.mbt
fresh_provider/region_store.mbt -> ../../incr_next_cycle_detection/fresh_provider/region_store.mbt
fresh_provider/source.mbt -> ../../incr_next_cycle_detection/fresh_provider/source.mbt
fresh_provider/transaction.mbt -> ../../incr_next_cycle_detection/fresh_provider/transaction.mbt
fresh_provider/view.mbt -> ../../incr_next_cycle_detection/fresh_provider/view.mbt
incremental_provider/core.mbt -> ../../incr_next_cycle_detection/incremental_provider/core.mbt
incremental_provider/ids.mbt -> ../../incr_next_cycle_detection/incremental_provider/ids.mbt
incremental_provider/region_store.mbt -> ../../incr_next_cycle_detection/incremental_provider/region_store.mbt
incremental_provider/source.mbt -> ../../incr_next_cycle_detection/incremental_provider/source.mbt
incremental_provider/transaction.mbt -> ../../incr_next_cycle_detection/incremental_provider/transaction.mbt
incremental_provider/view.mbt -> ../../incr_next_cycle_detection/incremental_provider/view.mbt
negative/anchor.mbt -> ../../incr_next_cycle_detection/negative/anchor.mbt
negative/eval_id_accessor.mbt.disabled -> ../../incr_next_cycle_detection/negative/eval_id_accessor.mbt.disabled
negative/external_eval_ctx_constructor.mbt.disabled -> ../../incr_next_cycle_detection/negative/external_eval_ctx_constructor.mbt.disabled
negative/external_eval_ctx_literal.mbt.disabled -> ../../incr_next_cycle_detection/negative/external_eval_ctx_literal.mbt.disabled
negative/external_transaction_constructor.mbt.disabled -> ../../incr_next_cycle_detection/negative/external_transaction_constructor.mbt.disabled
negative/external_transaction_literal.mbt.disabled -> ../../incr_next_cycle_detection/negative/external_transaction_literal.mbt.disabled
negative/external_view_literal.mbt.disabled -> ../../incr_next_cycle_detection/negative/external_view_literal.mbt.disabled
negative/source_set.mbt.disabled -> ../../incr_next_cycle_detection/negative/source_set.mbt.disabled
negative/view_call.mbt.disabled -> ../../incr_next_cycle_detection/negative/view_call.mbt.disabled
negative/view_get.mbt.disabled -> ../../incr_next_cycle_detection/negative/view_get.mbt.disabled
negative/view_read.mbt.disabled -> ../../incr_next_cycle_detection/negative/view_read.mbt.disabled
LINKS
)
actual_links=$(find "$SPIKE" -type l -printf '%P -> %l\n' | sort)
if [[ "$actual_links" != "$expected_links" ]]; then
  printf '%s\n' 'cutoff evidence symlink manifest drifted:' >&2
  diff -u <(printf '%s\n' "$expected_links") <(printf '%s\n' "$actual_links") || true
  exit 1
fi
git diff --exit-code 4e2e265 -- examples/spikes/incr_next_fresh_evaluator
git diff --cached --exit-code 4e2e265 -- examples/spikes/incr_next_fresh_evaluator
git diff --exit-code d54e780 -- examples/spikes/incr_next_incremental_parity
git diff --cached --exit-code d54e780 -- examples/spikes/incr_next_incremental_parity
git diff --exit-code b0244adaea59e0684bac53026220c9bd0d247bea -- \
  examples/spikes/incr_next_cycle_detection
git diff --cached --exit-code b0244adaea59e0684bac53026220c9bd0d247bea -- \
  examples/spikes/incr_next_cycle_detection
if git status --short -- examples/spikes/incr_next_fresh_evaluator \
  examples/spikes/incr_next_incremental_parity \
  examples/spikes/incr_next_cycle_detection | grep -q .; then
  printf '%s\n' 'forbidden prior-evidence working-tree change detected' >&2
  exit 1
fi
changed_paths=$({
  git diff --name-only b0244adaea59e0684bac53026220c9bd0d247bea...HEAD
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)
forbidden_paths=$(grep -Ev '^(moon\.work|examples/spikes/README\.md|examples/spikes/incr_next_cutoff_backdating(/.*)?)$' <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the cutoff evidence allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi
printf '%s\n' 'interfaces/docs/workspace/#461/#462/#463 boundaries: PASS'
printf '%s\n' 'harness state: fmt=PASS info=PASS checks=PASS native=PASS wasm=PASS prior=PASS native_rc=PASS negatives=PASS boundaries=PASS'
printf '%s\n' 'constrained verdict: PASS - typed cutoff backdates stamps while replacing successful values and traces.'
