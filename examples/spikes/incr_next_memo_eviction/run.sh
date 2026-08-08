#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SPIKE=examples/spikes/incr_next_memo_eviction
NEG="$SPIKE/negative"
TMP="$NEG/probe.mbt"
FMT_TMP=$(mktemp -d)
trap 'rm -f "$TMP"; rm -rf "$FMT_TMP"' EXIT

printf '%s\n' '== Incr Next explicit memo eviction/rematerialization evidence =='
# Check only files owned by this spike. Running moon fmt on package directories
# containing source symlinks can write through into guarded prior evidence.
cp -LR "$SPIKE"/. "$FMT_TMP"/
while IFS= read -r link; do
  relative=${link#"$SPIKE"/}
  case "$relative" in
    */moon.pkg | *.c) ;;
    *) rm -f "$FMT_TMP/$relative" ;;
  esac
done < <(find "$SPIKE" -type l | sort)
(cd "$FMT_TMP" && moon fmt --check .)
mbti_files=(
  "$SPIKE/fresh_provider/pkg.generated.mbti"
  "$SPIKE/incremental_provider/pkg.generated.mbti"
  "$SPIKE/consumer/pkg.generated.mbti"
  "$SPIKE/native_rc/pkg.generated.mbti"
  "$NEG/pkg.generated.mbti"
)
mbti_before=$(sha256sum "${mbti_files[@]}")
moon info "$SPIKE/fresh_provider" "$SPIKE/incremental_provider" \
  "$SPIKE/consumer" "$SPIKE/native_rc" "$NEG"
mbti_after=$(sha256sum "${mbti_files[@]}")
if [[ "$mbti_before" != "$mbti_after" ]]; then
  printf '%s\n' 'generated interfaces were stale before the harness:' >&2
  diff -u <(printf '%s\n' "$mbti_before") <(printf '%s\n' "$mbti_after") || true
  exit 1
fi

printf '%s\n' '-- eviction-aware provider and consumer checks --'
moon check --target wasm-gc "$SPIKE/fresh_provider" \
  "$SPIKE/incremental_provider" "$SPIKE/consumer"
moon check --target native "$SPIKE/fresh_provider" \
  "$SPIKE/incremental_provider" "$SPIKE/consumer"

printf '%s\n' '-- native exact parity, cutoff, cycle, and eviction evidence --'
moon run "$SPIKE/consumer" --target native
printf '%s\n' '-- wasm-gc exact parity, cutoff, cycle, and eviction evidence --'
moon run "$SPIKE/consumer" --target wasm-gc

printf '%s\n' '-- unchanged prior evidence executables --'
moon run examples/spikes/incr_next_fresh_evaluator/consumer --target native
moon run examples/spikes/incr_next_incremental_parity/consumer --target native
moon run examples/spikes/incr_next_cycle_detection/consumer --target native
moon run examples/spikes/incr_next_cutoff_backdating/consumer --target native

printf '%s\n' '-- native RC eviction ownership evidence --'
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
run_negative private_memo_entry 4032
run_negative view_evict 4015

printf '%s\n' '-- interface, documentation, workspace, and prior-tree boundaries --'
./scripts/check-documentation-boundaries.py
grep -Fq 'conservative propagation stamp' "$SPIKE/README.md"
if rg -n 'MemoEntry|CutoffPolicy|eviction_phase_error|ExecutionMode|TrustedCutoff|query_by' \
  "$SPIKE/fresh_provider/pkg.generated.mbti" \
  "$SPIKE/incremental_provider/pkg.generated.mbti"; then
  printf '%s\n' 'private memo/eviction/cutoff representation leaked through .mbti' >&2
  exit 1
fi
expected_links=$(cat <<'LINKS'
consumer/cutoff.mbt -> ../../incr_next_cutoff_backdating/consumer/cutoff.mbt
consumer/cycles.mbt -> ../../incr_next_cutoff_backdating/consumer/cycles.mbt
fresh_provider/core.mbt -> ../../incr_next_cutoff_backdating/fresh_provider/core.mbt
fresh_provider/ids.mbt -> ../../incr_next_cutoff_backdating/fresh_provider/ids.mbt
fresh_provider/moon.pkg -> ../../incr_next_cutoff_backdating/fresh_provider/moon.pkg
fresh_provider/region_store.mbt -> ../../incr_next_cutoff_backdating/fresh_provider/region_store.mbt
fresh_provider/source.mbt -> ../../incr_next_cutoff_backdating/fresh_provider/source.mbt
fresh_provider/transaction.mbt -> ../../incr_next_cutoff_backdating/fresh_provider/transaction.mbt
fresh_provider/view.mbt -> ../../incr_next_cutoff_backdating/fresh_provider/view.mbt
incremental_provider/core.mbt -> ../../incr_next_cutoff_backdating/incremental_provider/core.mbt
incremental_provider/cutoff_policy_probe.c -> ../../incr_next_cutoff_backdating/incremental_provider/cutoff_policy_probe.c
incremental_provider/ids.mbt -> ../../incr_next_cutoff_backdating/incremental_provider/ids.mbt
incremental_provider/moon.pkg -> ../../incr_next_cutoff_backdating/incremental_provider/moon.pkg
incremental_provider/region_store.mbt -> ../../incr_next_cutoff_backdating/incremental_provider/region_store.mbt
incremental_provider/source.mbt -> ../../incr_next_cutoff_backdating/incremental_provider/source.mbt
incremental_provider/transaction.mbt -> ../../incr_next_cutoff_backdating/incremental_provider/transaction.mbt
incremental_provider/view.mbt -> ../../incr_next_cutoff_backdating/incremental_provider/view.mbt
negative/anchor.mbt -> ../../incr_next_cutoff_backdating/negative/anchor.mbt
negative/arbitrary_cutoff_predicate.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/arbitrary_cutoff_predicate.mbt.disabled
negative/eval_id_accessor.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/eval_id_accessor.mbt.disabled
negative/external_eval_ctx_constructor.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/external_eval_ctx_constructor.mbt.disabled
negative/external_eval_ctx_literal.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/external_eval_ctx_literal.mbt.disabled
negative/external_transaction_constructor.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/external_transaction_constructor.mbt.disabled
negative/external_transaction_literal.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/external_transaction_literal.mbt.disabled
negative/external_view_literal.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/external_view_literal.mbt.disabled
negative/private_cutoff_policy.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/private_cutoff_policy.mbt.disabled
negative/source_set.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/source_set.mbt.disabled
negative/view_call.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/view_call.mbt.disabled
negative/view_get.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/view_get.mbt.disabled
negative/view_read.mbt.disabled -> ../../incr_next_cutoff_backdating/negative/view_read.mbt.disabled
LINKS
)
actual_links=$(find "$SPIKE" -type l -printf '%P -> %l\n' | sort)
if [[ "$actual_links" != "$expected_links" ]]; then
  printf '%s\n' 'memo eviction evidence symlink manifest drifted:' >&2
  diff -u <(printf '%s\n' "$expected_links") <(printf '%s\n' "$actual_links") || true
  exit 1
fi
git diff --exit-code 4e2e265 -- examples/spikes/incr_next_fresh_evaluator
git diff --cached --exit-code 4e2e265 -- examples/spikes/incr_next_fresh_evaluator
git diff --exit-code d54e780 -- examples/spikes/incr_next_incremental_parity
git diff --cached --exit-code d54e780 -- examples/spikes/incr_next_incremental_parity
git diff --exit-code b0244adaea59e0684bac53026220c9bd0d247bea -- examples/spikes/incr_next_cycle_detection
git diff --cached --exit-code b0244adaea59e0684bac53026220c9bd0d247bea -- examples/spikes/incr_next_cycle_detection
git diff --exit-code c640f65124b2a0eb362f3f08a1b6220e6647b6b7 -- examples/spikes/incr_next_cutoff_backdating
git diff --cached --exit-code c640f65124b2a0eb362f3f08a1b6220e6647b6b7 -- examples/spikes/incr_next_cutoff_backdating
if git status --short -- examples/spikes/incr_next_fresh_evaluator \
  examples/spikes/incr_next_incremental_parity \
  examples/spikes/incr_next_cycle_detection \
  examples/spikes/incr_next_cutoff_backdating | grep -q .; then
  printf '%s\n' 'forbidden prior-evidence working-tree change detected' >&2
  exit 1
fi
changed_paths=$({
  git diff --name-only c640f65124b2a0eb362f3f08a1b6220e6647b6b7...HEAD
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)
forbidden_paths=$(grep -Ev '^(moon\.work|examples/spikes/README\.md|examples/spikes/incr_next_memo_eviction(/.*)?)$' <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the memo eviction evidence allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi
printf '%s\n' 'interfaces/docs/workspace/#461/#462/#463/#464 boundaries: PASS'
printf '%s\n' 'harness state: fmt=PASS info=PASS checks=PASS native=PASS wasm=PASS prior=PASS native_rc=PASS negatives=PASS boundaries=PASS'
printf '%s\n' 'constrained verdict: PASS - explicit eviction forgets proof and rematerializes conservatively.'
