#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SPIKE=examples/spikes/incr_next_cross_program_ports
NEG="$SPIKE/negative"
TMP="$NEG/probe.mbt"
COPY_TMP=$(mktemp -d)
trap 'rm -f "$TMP"; rm -rf "$COPY_TMP"' EXIT

printf '%s\n' '== Incr Next cross-program port evidence =='

printf '%s\n' '-- disposable formatting and generated-interface freshness --'
cp -LR "$SPIKE"/. "$COPY_TMP"/
while IFS= read -r link; do
  relative=${link#"$SPIKE"/}
  rm -f "$COPY_TMP/$relative"
done < <(find "$SPIKE" -type l | sort)
(cd "$COPY_TMP" && moon fmt --check .)
mbti_files=(
  program/pkg.generated.mbti
  feature_provider/pkg.generated.mbti
  feature_consumer/pkg.generated.mbti
  negative/pkg.generated.mbti
)
moon info "$COPY_TMP/program" "$COPY_TMP/feature_provider" "$COPY_TMP/feature_consumer" "$COPY_TMP/negative"
for relative in "${mbti_files[@]}"; do
  if [[ ! -f "$SPIKE/$relative" ]] || ! cmp -s "$SPIKE/$relative" "$COPY_TMP/$relative"; then
    printf 'generated interface was stale: %s\n' "$relative" >&2
    diff -u "$SPIKE/$relative" "$COPY_TMP/$relative" || true
    exit 1
  fi
done

printf '%s\n' '-- package checks and tests --'
moon check --target native "$SPIKE/program" "$SPIKE/feature_provider" "$SPIKE/feature_consumer" "$SPIKE/negative"
moon check --target wasm-gc "$SPIKE/program" "$SPIKE/feature_provider" "$SPIKE/feature_consumer" "$SPIKE/negative"
moon test --target native "$SPIKE/feature_consumer"
moon test --target wasm-gc "$SPIKE/feature_consumer"

printf '%s\n' '-- native/wasm exact output --'
native_output=$(moon run "$SPIKE/feature_consumer" --target native)
wasm_output=$(moon run "$SPIKE/feature_consumer" --target wasm-gc)
printf '%s\n' "$native_output"
printf '%s\n' "$wasm_output"
if [[ "$native_output" != "$wasm_output" ]]; then
  printf '%s\n' 'native and wasm outputs differ' >&2
  diff -u <(printf '%s\n' "$native_output") <(printf '%s\n' "$wasm_output") || true
  exit 1
fi
grep -Fxq 'cross_program_ports workloads=true' <<<"$native_output"

printf '%s\n' '-- unchanged #461-#467 executable evidence --'
moon run examples/spikes/incr_next_fresh_evaluator/consumer --target native
moon run examples/spikes/incr_next_incremental_parity/consumer --target native
moon run examples/spikes/incr_next_cycle_detection/consumer --target native
moon run examples/spikes/incr_next_cutoff_backdating/consumer --target native
moon run examples/spikes/incr_next_memo_eviction/consumer --target native
moon run examples/spikes/incr_next_mounted_roots/consumer --target native
moon run examples/spikes/incr_next_read_ports/consumer --target native

printf '%s\n' '-- expected package-boundary compiler failures --'
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
run_negative raw_export_view 4074
run_negative raw_port_view 4074
run_negative formula_view 4015
run_negative export_literal 4036
run_negative port_literal 4036
run_negative query_key 4032
run_negative provider_literal 4036

printf '%s\n' '-- privacy, docs, and prior-tree guards --'
if rg -n '@kernel|incremental_provider|View\[|Query\[' \
  "$SPIKE/feature_provider/pkg.generated.mbti"; then
  printf '%s\n' 'raw kernel View/Query type leaked through feature_provider interface' >&2
  exit 1
fi
if rg -n 'incremental_provider|kernel' "$SPIKE/feature_consumer/moon.pkg"; then
  printf '%s\n' 'feature_consumer imports the kernel directly' >&2
  exit 1
fi
if rg -n 'registry|Registry|Mount|Action|Resource|Canopy|LRU' \
  "$SPIKE" --glob '*.mbt'; then
  printf '%s\n' 'out-of-scope registry/effect architecture found in spike' >&2
  exit 1
fi
./scripts/check-documentation-boundaries.py
npx slopless "$SPIKE/README.md" >/tmp/incr-next-cross-program-ports-slopless.json
python3 - <<'PY'
import json
with open('/tmp/incr-next-cross-program-ports-slopless.json') as handle:
    reports = json.load(handle)
messages = [message for report in reports for message in report.get('messages', [])]
if messages:
    raise SystemExit(f'slopless findings: {messages}')
print('slopless: PASS')
PY

# Published prior evidence trees are immutable from this spike.
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
git diff --exit-code 89eee9a -- examples/spikes/incr_next_read_ports
git diff --cached --exit-code 89eee9a -- examples/spikes/incr_next_read_ports
if git status --short -- examples/spikes/incr_next_fresh_evaluator \
  examples/spikes/incr_next_incremental_parity \
  examples/spikes/incr_next_cycle_detection \
  examples/spikes/incr_next_cutoff_backdating \
  examples/spikes/incr_next_memo_eviction \
  examples/spikes/incr_next_mounted_roots \
  examples/spikes/incr_next_read_ports | grep -q .; then
  printf '%s\n' 'forbidden prior-evidence working-tree change detected' >&2
  exit 1
fi

changed_paths=$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)
forbidden_paths=$(grep -Ev '^(moon\.work|examples/spikes/README\.md|examples/spikes/incr_next_cross_program_ports(/.*)?)$' <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the cross-program spike allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi

printf '%s\n' 'harness state: fmt=PASS info=PASS checks=PASS tests=PASS native=PASS wasm=PASS prior=#461-#467-PASS negatives=PASS privacy=PASS slopless=PASS'
grep -Fq 'The evidence result is **Pass with constraints**.' "$SPIKE/README.md"
printf '%s\n' 'constrained verdict: PASS - typed exports authorize consumer-owned ports without a global registry.'
