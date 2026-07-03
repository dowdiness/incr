#!/usr/bin/env bash
# scripts/check-workspace-boundaries-selftest.sh
# Known-positive/known-negative self-test for check-workspace-boundaries.sh.
# The checker's value depends on it actually firing; a regression in its
# manifest parsing would otherwise degrade silently to a vacuous pass
# (absence of matches reads as compliance). Run in CI before the real check.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
checker="$script_dir/check-workspace-boundaries.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

fail=0
expect() {
  local label="$1" expected="$2"
  local actual=0
  INCR_REPO_ROOT="$fixture" bash "$checker" > /dev/null 2>&1 || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    echo "SELFTEST FAIL: $label — expected exit $expected, got $actual"
    fail=1
  else
    echo "selftest ok: $label"
  fi
}

# Baseline fixture: library at 0.12.0, one TOML member, one JSON member,
# both clean and correctly pinned.
mkdir -p "$fixture/incr" "$fixture/demo_toml" "$fixture/demo_json"
printf 'members = [\n  "./incr",\n  "./demo_toml",\n  "./demo_json",\n]\n' > "$fixture/moon.work"
printf 'name = "dowdiness/incr"\nversion = "0.12.0"\n' > "$fixture/incr/moon.mod"
printf 'name = "demo_toml"\nimport {\n  "dowdiness/incr@0.12.0",\n}\n' > "$fixture/demo_toml/moon.mod"
printf 'import {\n  "dowdiness/incr",\n}\n' > "$fixture/demo_toml/moon.pkg"
printf '{ "name": "demo_json", "deps": { "dowdiness/incr": "0.12.0" } }\n' > "$fixture/demo_json/moon.mod.json"
printf '{ "import": ["dowdiness/incr"] }\n' > "$fixture/demo_json/moon.pkg.json"

expect "clean fixture passes" 0

# Invariant A: deep import in a moon.pkg fails.
printf 'import {\n  "dowdiness/incr",\n  "dowdiness/incr/cells",\n}\n' > "$fixture/demo_toml/moon.pkg"
expect "deep import (moon.pkg) fails" 1
printf 'import {\n  "dowdiness/incr",\n}\n' > "$fixture/demo_toml/moon.pkg"

# Invariant A: deep import in a legacy moon.pkg.json fails.
printf '{ "import": ["dowdiness/incr/types"] }\n' > "$fixture/demo_json/moon.pkg.json"
expect "deep import (moon.pkg.json) fails" 1
printf '{ "import": ["dowdiness/incr"] }\n' > "$fixture/demo_json/moon.pkg.json"

# Invariant B: stale TOML pin fails.
printf 'name = "demo_toml"\nimport {\n  "dowdiness/incr@0.9.0",\n}\n' > "$fixture/demo_toml/moon.mod"
expect "stale TOML pin fails" 1
printf 'name = "demo_toml"\nimport {\n  "dowdiness/incr@0.12.0",\n}\n' > "$fixture/demo_toml/moon.mod"

# Invariant B: stale legacy JSON pin fails.
printf '{ "name": "demo_json", "deps": { "dowdiness/incr": "0.5.0" } }\n' > "$fixture/demo_json/moon.mod.json"
expect "stale JSON pin fails" 1
printf '{ "name": "demo_json", "deps": { "dowdiness/incr": "0.12.0" } }\n' > "$fixture/demo_json/moon.mod.json"

# Restored fixture must be clean again (guards against test-order leakage).
expect "restored fixture passes" 0

exit "$fail"
