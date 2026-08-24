#!/usr/bin/env bash
# Negative controls for the K2.3 distribution boundary.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/scripts/check-incr-next-k2-3-distribution.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/incr-next-k2-3-selftest.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/incr_next" "$fixture/incr_next_consumer_probe"
cp -a "$repo_root/incr_next"/. "$fixture/incr_next"/
cp -a "$repo_root/incr_next_consumer_probe"/. "$fixture/incr_next_consumer_probe"/
cp -p "$repo_root/LICENSE" "$fixture/LICENSE"
rm -rf \
  "$fixture/incr_next/_build" \
  "$fixture/incr_next/.mooncakes" \
  "$fixture/incr_next_consumer_probe/_build" \
  "$fixture/incr_next_consumer_probe/.mooncakes"

run_checker() {
  INCR_NEXT_K23_ROOT="$fixture" \
  INCR_NEXT_K23_SOURCE_ONLY=1 \
  INCR_NEXT_K23_OUTPUT_DIR="$fixture/evidence" \
    "$checker"
}

expect_failure() {
  local pattern=$1
  set +e
  output=$(run_checker 2>&1)
  status=$?
  set -e
  if [ "$status" -eq 0 ] || ! grep -Fq "$pattern" <<<"$output"; then
    echo "selftest expected failure containing: $pattern" >&2
    echo "$output" >&2
    exit 1
  fi
}

run_checker >/dev/null
echo "selftest ok: clean source/package policy passes"

cp "$fixture/incr_next/README.mbt.md" "$fixture/README.saved"
printf '\n[leak](../private_evidence/)\n' >> "$fixture/incr_next/README.mbt.md"
expect_failure 'candidate-external relative link'
mv "$fixture/README.saved" "$fixture/incr_next/README.mbt.md"
echo "selftest ok: candidate-external README link fails"

mv "$fixture/LICENSE" "$fixture/LICENSE.saved"
expect_failure 'required input missing'
mv "$fixture/LICENSE.saved" "$fixture/LICENSE"
echo "selftest ok: missing root LICENSE fails"

printf 'unexpected\n' > "$fixture/incr_next/unexpected.txt"
expect_failure 'candidate archive file manifest differs'
rm "$fixture/incr_next/unexpected.txt"
echo "selftest ok: unexpected archive content fails"

cp "$fixture/incr_next/.moonignore" "$fixture/moonignore.saved"
grep -Fvx '!native_rc/rc_probe.c' "$fixture/moonignore.saved" > "$fixture/incr_next/.moonignore"
expect_failure '.moonignore is missing policy line: !native_rc/rc_probe.c'
mv "$fixture/moonignore.saved" "$fixture/incr_next/.moonignore"
echo "selftest ok: native stub inclusion policy is mandatory"

ln -s README.mbt.md "$fixture/incr_next/README-link"
expect_failure 'source module contains a symlink'
rm "$fixture/incr_next/README-link"
echo "selftest ok: source symlink fails"

cp "$fixture/incr_next_consumer_probe/moon.pkg" "$fixture/consumer-pkg.saved"
printf '\nimport { "dowdiness/incr_next_testkit/model" }\n' >> "$fixture/incr_next_consumer_probe/moon.pkg"
expect_failure 'consumer moon.pkg is not the accepted public-only manifest'
mv "$fixture/consumer-pkg.saved" "$fixture/incr_next_consumer_probe/moon.pkg"
echo "selftest ok: consumer testkit import fails"

if grep -Eq '"?\$?moon_bin"? publish --dry-run|moon publish --dry-run' "$checker"; then
  echo "selftest found a forbidden publish dry-run invocation" >&2
  exit 1
fi
# Match the literal variable reference in the checker, not this process's value.
# shellcheck disable=SC2016
grep -Fq '"$moon_bin" publish --help' "$checker"
echo "selftest ok: publish is characterized by help only"
