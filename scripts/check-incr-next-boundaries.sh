#!/usr/bin/env bash
# Check the K1.1 module and Fresh/incremental package boundary.
set -euo pipefail

root="${INCR_NEXT_BOUNDARY_ROOT:-.}"
fail=0

extract_scoped_imports() {
  local file="$1"
  awk '
    function emit(  i) {
      for (i = 1; i <= count; i++) print scope "\t" imports[i]
    }
    /^[[:space:]]*import[[:space:]]*\{/ {
      block = 1
      count = 0
      scope = "normal"
      next
    }
    block {
      if ($0 ~ /^[[:space:]]*}/) {
        if (match($0, /for[[:space:]]+"[^"]+"/)) {
          qualifier = substr($0, RSTART, RLENGTH)
          sub(/^for[[:space:]]+"/, "", qualifier)
          sub(/"$/, "", qualifier)
          scope = qualifier
        }
        emit()
        block = 0
        next
      }
      line = $0
      while (match(line, /"[^"]+"/)) {
        value = substr(line, RSTART + 1, RLENGTH - 2)
        if (value != "test" && value !~ /^-?[0-9]+$/) imports[++count] = value
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$file"
}

extract_imports() {
  local file="$1"
  extract_scoped_imports "$file" | cut -f2
}

if [ ! -f "$root/moon.work" ]; then
  echo "MISSING: $root/moon.work" >&2
  exit 1
fi
for required in "$root/incr_next/moon.mod" "$root/incr_next/moon.pkg" \
  "$root/incr_next_testkit/moon.mod" "$root/incr_next_testkit/model/moon.pkg" \
  "$root/incr_next_testkit/fresh/moon.pkg" \
  "$root/incr_next_testkit/incremental_adapter/moon.pkg"; do
  if [ ! -f "$required" ]; then
    echo "MISSING: $required" >&2
    fail=1
  fi
done

if grep -Eq 'dowdiness/incr_next_testkit|moonbitlang/quickcheck' \
  "$root/incr_next/moon.mod"; then
  echo "FAIL: production kernel module depends on test evidence" >&2
  fail=1
fi

while IFS= read -r pkg; do
  case "$pkg" in
    "$root/incr_next/native_rc/moon.pkg"|"$root/incr_next/negative/moon.pkg") ;;
    "$root/incr_next/"*)
      while IFS=$'\t' read -r scope import; do
        case "$import" in
          dowdiness/incr_next_testkit/*|moonbitlang/quickcheck*)
            echo "FAIL: production kernel imports test evidence: $pkg [$scope] -> $import" >&2
            fail=1
            ;;
          dowdiness/incr/*|dowdiness/incr_next)
            echo "FAIL: kernel imports current Incr: $pkg [$scope] -> $import" >&2
            fail=1
            ;;
        esac
      done < <(extract_scoped_imports "$pkg")
      ;;
  esac
done < <(find "$root/incr_next" -name moon.pkg -type f -print)

adapter_imports=$(extract_imports "$root/incr_next_testkit/incremental_adapter/moon.pkg")
if ! echo "$adapter_imports" | grep -Fxq 'dowdiness/incr_next'; then
  echo "FAIL: incremental_adapter does not import dowdiness/incr_next" >&2
  fail=1
fi

# Traverse every local testkit package. The Fresh-reachable subgraph is
# stricter: it may only use local testkit packages and may never reach the
# kernel through a direct, local-transitive, or external-module edge.
queue=("$root/incr_next_testkit/fresh")
visited=""
while [ "${#queue[@]}" -gt 0 ]; do
  pkg_dir="${queue[0]}"
  queue=("${queue[@]:1}")
  case " $visited " in *" $pkg_dir "*) continue ;; esac
  visited="$visited $pkg_dir"
  pkg="$pkg_dir/moon.pkg"
  if [ ! -f "$pkg" ]; then
    echo "FAIL: Fresh-reachable import has no local package: $pkg_dir" >&2
    fail=1
    continue
  fi
  while IFS= read -r import; do
    case "$import" in
      dowdiness/incr_next|dowdiness/incr_next/*)
        echo "FAIL: Fresh-reachable package imports kernel: $pkg -> $import" >&2
        fail=1
        ;;
      dowdiness/incr_next_testkit/*)
        sub="${import#dowdiness/incr_next_testkit/}"
        local_pkg="$root/incr_next_testkit/$sub/moon.pkg"
        if [ ! -f "$local_pkg" ]; then
          echo "FAIL: Fresh-reachable package escapes local testkit DAG: $pkg -> $import" >&2
          fail=1
        else
          queue+=("$root/incr_next_testkit/$sub")
        fi
        ;;
      "") ;;
      *)
        echo "FAIL: Fresh-reachable package imports external/indirect dependency: $pkg -> $import" >&2
        fail=1
        ;;
    esac
  done < <(extract_imports "$pkg")
done

while IFS= read -r pkg; do
  while IFS= read -r import; do
    case "$import" in
      dowdiness/incr_next_testkit/*)
        sub="${import#dowdiness/incr_next_testkit/}"
        if [ ! -f "$root/incr_next_testkit/$sub/moon.pkg" ]; then
          echo "FAIL: local testkit package indirection has no local target: $pkg -> $import" >&2
          fail=1
        fi
        ;;
    esac
  done < <(extract_imports "$pkg")
done < <(find "$root/incr_next_testkit" -name moon.pkg -type f -print)

if grep -R -n -E 'examples/spikes/incr_next_(keyed_view_recipe|fresh_evaluator)|spike/incr-next' \
  "$root/incr_next" "$root/incr_next_testkit" >/dev/null 2>&1; then
  echo "FAIL: production/testkit path contains an evidence-provider import or materialization" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "Incr Next boundary check: PASS"
