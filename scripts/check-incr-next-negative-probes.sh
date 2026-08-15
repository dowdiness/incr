#!/usr/bin/env bash
set -euo pipefail

root="${INCR_NEXT_ROOT:-incr_next}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R "$root" "$tmp/kernel"

expected_diagnostic() {
  case "$1" in
    query_context_constructor.mbt.disabled)
      printf '%s' 'does not declare a custom constructor'
      ;;
    cycle_witness_constructor.mbt.disabled)
      printf '%s' 'does not declare a custom constructor'
      ;;
    cycle_witness_fields.mbt.disabled)
      printf '%s' 'CycleWitness has no field path'
      ;;
    query_context_fields.mbt.disabled)
      printf '%s' 'QueryContext has no field session'
      ;;
    query_context_revision_fake.mbt.disabled)
      printf '%s' 'Cannot create values of the read-only type: @dowdiness/incr_next.Revision'
      ;;
    source_set.mbt.disabled)
      printf '%s' 'Source[T] has no method set'
      ;;
    transaction_debug_methods.mbt.disabled)
      printf '%s' 'Transaction has no method is_poisoned'
      ;;
    transaction_fields.mbt.disabled)
      printf '%s' 'Transaction has no field session'
      ;;
    view_call.mbt.disabled)
      printf '%s' 'wanted   : function type'
      ;;
    view_constructor.mbt.disabled)
      printf '%s' 'does not declare a custom constructor'
      ;;
    view_fields.mbt.disabled)
      printf '%s' 'View[Int] has no field recipe'
      ;;
    arbitrary_cutoff_predicate.mbt.disabled)
      printf '%s' 'Region has no method query_with_policy'
      ;;
    public_cutoff_policy.mbt.disabled)
      printf '%s' 'Region has no method query_with_policy'
      ;;
    *)
      echo "FAIL: no expected diagnostic for $1" >&2
      return 1
      ;;
  esac
}

for probe in "$tmp/kernel"/negative/*.mbt.disabled; do
  candidate="${probe%.disabled}"
  cp "$probe" "$candidate"
  if (cd "$tmp/kernel" && moon check negative) >"$tmp/output" 2>&1; then
    echo "FAIL: negative probe unexpectedly compiled: $probe" >&2
    exit 1
  fi
  expected=$(expected_diagnostic "$(basename "$probe")")
  if ! grep -Fq "$expected" "$tmp/output"; then
    echo "FAIL: negative probe did not produce its capability diagnostic: $probe" >&2
    echo "EXPECTED: $expected" >&2
    cat "$tmp/output" >&2
    exit 1
  fi
  rm -f "$candidate"
done
echo "Incr Next negative capability probes: PASS"
