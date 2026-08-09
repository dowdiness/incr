#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SPIKE=examples/spikes/incr_next_read_ports
NEG="$SPIKE/negative"
TMP="$NEG/probe.mbt"
COPY_TMP=$(mktemp -d)
trap 'rm -f "$TMP"; rm -rf "$COPY_TMP"' EXIT

printf '%s\n' '== Incr Next typed read-port evidence =='

printf '%s\n' '-- disposable formatting and generated-interface freshness --'
cp -LR "$SPIKE"/. "$COPY_TMP"/
while IFS= read -r link; do
  relative=${link#"$SPIKE"/}
  rm -f "$COPY_TMP/$relative"
done < <(find "$SPIKE" -type l | sort)
(cd "$COPY_TMP" && moon fmt --check .)
mbti_files=(
  program_provider/pkg.generated.mbti
  consumer/pkg.generated.mbti
  negative/pkg.generated.mbti
)
moon info "$COPY_TMP/program_provider" "$COPY_TMP/consumer" "$COPY_TMP/negative"
for relative in "${mbti_files[@]}"; do
  if ! cmp -s "$SPIKE/$relative" "$COPY_TMP/$relative"; then
    printf 'generated interface was stale before the harness: %s\n' "$relative" >&2
    diff -u "$SPIKE/$relative" "$COPY_TMP/$relative" || true
    exit 1
  fi
done

printf '%s\n' '-- program provider and consumer checks/tests --'
moon check --target wasm-gc "$SPIKE/program_provider" "$SPIKE/consumer" "$SPIKE/negative"
moon check --target native "$SPIKE/program_provider" "$SPIKE/consumer"
moon test --target native "$SPIKE/consumer"
moon test --target wasm-gc "$SPIKE/consumer"

printf '%s\n' '-- native/wasm exact output --'
native_output=$(moon run "$SPIKE/consumer" --target native)
printf '%s\n' "$native_output"
wasm_output=$(moon run "$SPIKE/consumer" --target wasm-gc)
printf '%s\n' "$wasm_output"
if [[ "$native_output" != "$wasm_output" ]]; then
  printf '%s\n' 'native and wasm outputs differ' >&2
  diff -u <(printf '%s\n' "$native_output") <(printf '%s\n' "$wasm_output") || true
  exit 1
fi
grep -Fxq 'read_ports workloads=true' <<<"$native_output"

printf '%s\n' '-- unchanged #461-#466 executable evidence --'
moon run examples/spikes/incr_next_fresh_evaluator/consumer --target native
moon run examples/spikes/incr_next_incremental_parity/consumer --target native
moon run examples/spikes/incr_next_cycle_detection/consumer --target native
moon run examples/spikes/incr_next_cutoff_backdating/consumer --target native
moon run examples/spikes/incr_next_memo_eviction/consumer --target native
moon run examples/spikes/incr_next_mounted_roots/consumer --target native

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
run_negative external_read_port_literal 4036
run_negative external_declared_read_literal 4036
run_negative external_eval_ctx_literal 4036
run_negative external_formula_literal 4036
run_negative formula_mutation 4091
run_negative read_port_mutation 4091
run_negative declared_read_mutation 4091
run_negative program_eval_ctx_mutation 4091
run_negative raw_view_extraction 4091
run_negative private_auth_state 4091
run_negative private_observed_state 4091

printf '%s\n' '-- interface, docs, workspace, and prior-tree guards --'
if rg -n 'Query\[' "$SPIKE/program_provider/pkg.generated.mbti"; then
  printf '%s\n' 'kernel Query key type leaked through program_provider interface' >&2
  exit 1
fi
if rg -n '@incremental_provider\.EvalCtx|@incremental_provider\.Query' \
  "$SPIKE/program_provider/pkg.generated.mbti"; then
  printf '%s\n' 'raw kernel evaluation/query types leaked through generated interface' >&2
  exit 1
fi
./scripts/check-documentation-boundaries.py
npx slopless "$SPIKE/README.md" >/tmp/incr-next-read-ports-slopless.json
python3 - <<'PY'
import json
with open('/tmp/incr-next-read-ports-slopless.json') as handle:
    reports = json.load(handle)
messages = [message for report in reports for message in report.get('messages', [])]
if messages:
    raise SystemExit(f'slopless findings: {messages}')
print('slopless: PASS')
PY

# These are the published evidence snapshots this spike is not allowed to edit.
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
git diff --exit-code 4339435 -- examples/spikes/incr_next_mounted_roots
git diff --cached --exit-code 4339435 -- examples/spikes/incr_next_mounted_roots
git diff --exit-code 4339435 -- examples/spikes/incr_next_memo_eviction/incremental_provider
git diff --cached --exit-code 4339435 -- examples/spikes/incr_next_memo_eviction/incremental_provider
if git status --short -- examples/spikes/incr_next_fresh_evaluator \
  examples/spikes/incr_next_incremental_parity \
  examples/spikes/incr_next_cycle_detection \
  examples/spikes/incr_next_cutoff_backdating \
  examples/spikes/incr_next_memo_eviction \
  examples/spikes/incr_next_mounted_roots | grep -q .; then
  printf '%s\n' 'forbidden prior-evidence working-tree change detected' >&2
  exit 1
fi

changed_paths=$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)
forbidden_paths=$(grep -Ev '^(moon\.work|examples/spikes/README\.md|examples/spikes/incr_next_read_ports(/.*)?)$' <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the read-port spike allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi

printf '%s\n' 'harness state: fmt=PASS info=PASS checks=PASS tests=PASS native=PASS wasm=PASS prior=#461-#466-PASS negatives=PASS boundaries=PASS slopless=PASS'
printf '%s\n' 'constrained verdict: PASS - one typed builder supplies ordered declarations and runtime authorization over opaque kernel Views.'
