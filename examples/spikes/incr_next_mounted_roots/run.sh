#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SPIKE=examples/spikes/incr_next_mounted_roots
NEG="$SPIKE/negative"
TMP="$NEG/probe.mbt"
COPY_TMP=$(mktemp -d)
trap 'rm -f "$TMP"; rm -rf "$COPY_TMP"' EXIT

printf '%s\n' '== Incr Next mounted-root scheduling evidence =='
# Generate interfaces only in a disposable, dereferenced copy. A stale check
# must fail without rewriting either this spike or its guarded symlink targets.
cp -LR "$SPIKE"/. "$COPY_TMP"/
moon info "$COPY_TMP/fresh_provider" "$COPY_TMP/incremental_provider" \
  "$COPY_TMP/consumer" "$COPY_TMP/native_rc" "$COPY_TMP/negative"
mbti_files=(
  fresh_provider/pkg.generated.mbti
  incremental_provider/pkg.generated.mbti
  consumer/pkg.generated.mbti
  native_rc/pkg.generated.mbti
  negative/pkg.generated.mbti
)
for relative in "${mbti_files[@]}"; do
  if ! cmp -s "$SPIKE/$relative" "$COPY_TMP/$relative"; then
    printf 'generated interface was stale before the harness: %s\n' \
      "$relative" >&2
    diff -u "$SPIKE/$relative" "$COPY_TMP/$relative" || true
    exit 1
  fi
done
# Check formatting only for files owned by this spike. Removing source paths
# that were symlinks prevents the formatter from checking or rewriting copies
# of guarded prior evidence; package manifests and C stubs remain available.
while IFS= read -r link; do
  relative=${link#"$SPIKE"/}
  case "$relative" in
    */moon.pkg | *.c) ;;
    *) rm -f "$COPY_TMP/$relative" ;;
  esac
done < <(find "$SPIKE" -type l | sort)
(cd "$COPY_TMP" && moon fmt --check .)

printf '%s\n' '-- mounted-root providers and consumer checks --'
moon check --target wasm-gc "$SPIKE/fresh_provider" \
  "$SPIKE/incremental_provider" "$SPIKE/consumer"
moon check --target native "$SPIKE/fresh_provider" \
  "$SPIKE/incremental_provider" "$SPIKE/consumer"
moon test --target native "$SPIKE/consumer"
moon test --target wasm-gc "$SPIKE/consumer"

printf '%s\n' '-- native exact parity, wake, cutoff, cycle, and eviction evidence --'
native_output=$(moon run "$SPIKE/consumer" --target native)
printf '%s\n' "$native_output"
printf '%s\n' '-- wasm-gc exact parity, wake, cutoff, cycle, and eviction evidence --'
wasm_output=$(moon run "$SPIKE/consumer" --target wasm-gc)
printf '%s\n' "$wasm_output"
if [[ "$native_output" != "$wasm_output" ]]; then
  printf '%s\n' 'native and wasm mount/evaluator outcomes differ' >&2
  diff -u <(printf '%s\n' "$native_output") <(printf '%s\n' "$wasm_output") || true
  exit 1
fi

printf '%s\n' '-- unchanged prior evidence executables --'
moon run examples/spikes/incr_next_fresh_evaluator/consumer --target native
moon run examples/spikes/incr_next_incremental_parity/consumer --target native
moon run examples/spikes/incr_next_cycle_detection/consumer --target native
moon run examples/spikes/incr_next_cutoff_backdating/consumer --target native
moon run examples/spikes/incr_next_memo_eviction/consumer --target native

printf '%s\n' '-- native RC mounted-root ownership evidence --'
moon check --target native "$SPIKE/native_rc"
rc_output=$(moon run "$SPIKE/native_rc" --target native)
printf '%s\n' "$rc_output"
grep -Fq 'runner_registry=true' <<<"$rc_output"
grep -Fq 'index_ownership=true' <<<"$rc_output"
grep -Fq 'view_recipe_ownership=true' <<<"$rc_output"
grep -Fq 'current_value_ownership=true' <<<"$rc_output"
grep -Fq 'success_footprint=true' <<<"$rc_output"
grep -Fq 'failed_attempt_footprint=true' <<<"$rc_output"
grep -Fq 'eviction_quiet=true' <<<"$rc_output"
grep -Fq 'region_close_wake=true' <<<"$rc_output"
grep -Fq 'dispose_idempotent=true' <<<"$rc_output"
grep -Fq 'dispose_releases_exclusive_view_key_current=true' <<<"$rc_output"
grep -Fq 'full_state live=[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]' <<<"$rc_output"
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
run_negative private_wake_token 4032
run_negative private_footprint 4032
run_negative private_runner_registry 4032
run_negative private_mount_index 4032
run_negative external_mount_literal 4036
run_negative external_mount_mutation 4091
run_negative view_mount 4015
run_negative disposed_mount_mutation 4091

printf '%s\n' '-- interface, documentation, workspace, and prior-tree boundaries --'
./scripts/check-documentation-boundaries.py
grep -Fq '`Fresh` is the oracle' "$SPIKE/README.md"
grep -Fq 'functional core' "$SPIKE/README.md"
grep -Fq 'WakeToken' "$SPIKE/README.md"
grep -Fq 'Existing API First' "$SPIKE/README.md"
grep -Fq 'The evidence result is **Pass with constraints**.' "$SPIKE/README.md"
grep -Fq 'not an admissible Formula operation' "$SPIKE/README.md"
grep -Fq 'selective evaluation' "$SPIKE/README.md"
if rg -n 'MemoEntry|CutoffPolicy|WakeToken|MountCore|TrackingFrame|attempted_footprint|mount_index|runner_registry|eviction_phase_error|ExecutionMode|TrustedCutoff|query_by' \
  "$SPIKE/fresh_provider/pkg.generated.mbti" \
  "$SPIKE/incremental_provider/pkg.generated.mbti"; then
  printf '%s\n' 'private memo/eviction/cutoff representation leaked through .mbti' >&2
  exit 1
fi
expected_links=$(cat <<'LINKS'
consumer/cutoff.mbt -> ../../incr_next_memo_eviction/consumer/cutoff.mbt
consumer/cycles.mbt -> ../../incr_next_memo_eviction/consumer/cycles.mbt
consumer/eviction.mbt -> ../../incr_next_memo_eviction/consumer/eviction.mbt
fresh_provider/moon.pkg -> ../../incr_next_memo_eviction/fresh_provider/moon.pkg
incremental_provider/cutoff_policy_native_wbtest.mbt -> ../../incr_next_memo_eviction/incremental_provider/cutoff_policy_native_wbtest.mbt
incremental_provider/cutoff_policy_probe.c -> ../../incr_next_memo_eviction/incremental_provider/cutoff_policy_probe.c
incremental_provider/moon.pkg -> ../../incr_next_memo_eviction/incremental_provider/moon.pkg
negative/anchor.mbt -> ../../incr_next_memo_eviction/negative/anchor.mbt
negative/arbitrary_cutoff_predicate.mbt.disabled -> ../../incr_next_memo_eviction/negative/arbitrary_cutoff_predicate.mbt.disabled
negative/eval_id_accessor.mbt.disabled -> ../../incr_next_memo_eviction/negative/eval_id_accessor.mbt.disabled
negative/external_eval_ctx_constructor.mbt.disabled -> ../../incr_next_memo_eviction/negative/external_eval_ctx_constructor.mbt.disabled
negative/external_eval_ctx_literal.mbt.disabled -> ../../incr_next_memo_eviction/negative/external_eval_ctx_literal.mbt.disabled
negative/external_transaction_constructor.mbt.disabled -> ../../incr_next_memo_eviction/negative/external_transaction_constructor.mbt.disabled
negative/external_transaction_literal.mbt.disabled -> ../../incr_next_memo_eviction/negative/external_transaction_literal.mbt.disabled
negative/external_view_literal.mbt.disabled -> ../../incr_next_memo_eviction/negative/external_view_literal.mbt.disabled
negative/private_cutoff_policy.mbt.disabled -> ../../incr_next_memo_eviction/negative/private_cutoff_policy.mbt.disabled
negative/private_memo_entry.mbt.disabled -> ../../incr_next_memo_eviction/negative/private_memo_entry.mbt.disabled
negative/source_set.mbt.disabled -> ../../incr_next_memo_eviction/negative/source_set.mbt.disabled
negative/view_call.mbt.disabled -> ../../incr_next_memo_eviction/negative/view_call.mbt.disabled
negative/view_evict.mbt.disabled -> ../../incr_next_memo_eviction/negative/view_evict.mbt.disabled
negative/view_get.mbt.disabled -> ../../incr_next_memo_eviction/negative/view_get.mbt.disabled
negative/view_read.mbt.disabled -> ../../incr_next_memo_eviction/negative/view_read.mbt.disabled
LINKS
)
actual_links=$(find "$SPIKE" -type l -printf '%P -> %l\n' | sort)
if [[ "$actual_links" != "$expected_links" ]]; then
  printf '%s\n' 'symlink manifest changed:' >&2
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
git diff --exit-code 5e79f111d92ee49645687f2a548b6e12f2063b14 -- examples/spikes/incr_next_memo_eviction
git diff --cached --exit-code 5e79f111d92ee49645687f2a548b6e12f2063b14 -- examples/spikes/incr_next_memo_eviction
if git status --short -- examples/spikes/incr_next_fresh_evaluator \
  examples/spikes/incr_next_incremental_parity \
  examples/spikes/incr_next_cycle_detection \
  examples/spikes/incr_next_cutoff_backdating \
  examples/spikes/incr_next_memo_eviction | grep -q .; then
  printf '%s\n' 'forbidden prior-evidence working-tree change detected' >&2
  exit 1
fi
changed_paths=$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)
forbidden_paths=$(grep -Ev '^(moon\.work|examples/spikes/README\.md|examples/spikes/incr_next_mounted_roots(/.*)?)$' <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the memo eviction evidence allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi
printf '%s\n' 'interfaces/docs/workspace/#461/#462/#463/#464/#465 boundaries: PASS'
printf '%s\n' 'harness state: fmt=PASS info=PASS checks=PASS consumer_tests=PASS native=PASS wasm=PASS prior=#461-#465-PASS native_rc=PASS negatives=PASS boundaries=PASS'
printf '%s\n' 'constrained verdict: PASS - active mounts wake from private transitive footprints and release ownership on dispose.'
