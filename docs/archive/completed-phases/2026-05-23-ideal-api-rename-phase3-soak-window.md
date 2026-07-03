# Phase 3a — Compatibility-to-Facade Migration Guide and Codemod

**Date:** 2026-05-23
**Revised:** 2026-05-26
**Status:** Complete
**Decision record:** No ADR needed: superseded by issue #345's revised decision (2026-07-03) — the compatibility surface was removed directly as 0.13.0 with no deprecation/soak stage, and the codemod (`scripts/migrate-to-target-facades.py`) was deleted in the same release.
**Parent plan:** [2026-05-21-ideal-api-rename-migration.md](2026-05-21-ideal-api-rename-migration.md)
**ADR:** [2026-05-21-public-api-ideal-naming.md](../../decisions/2026-05-21-public-api-ideal-naming.md)

## Revision note

The original 2026-05-23 draft proposed adding target-vocabulary methods directly
on the compatibility handles `Memo`, `HybridMemo`, and `MemoMap` as a same-receiver
bridge. That direction is rejected.

`Derived`, `ReachableDerived`, and `DerivedMap` already provide the target read
surface. If the compatibility handles are eventual cleanup/removal targets, adding
new methods to those handles creates churn: users migrate to API that exists only
to be deleted later. Phase 3a is therefore a **documentation and codemod** phase:
migrate users to the target facades themselves, not to new methods on old
receivers.

## Context

The target facade work has shipped:

- `Derived[T]` wraps `Memo[T]` and exposes target reads:
  `get() -> Result`, `get_or_abort()`, `read() -> Result`, `read_or_abort()`,
  and `watch()`.
- `ReachableDerived[T]` wraps `HybridMemo[T]` with the same target read
  vocabulary where applicable.
- `DerivedMap[K, V]` wraps `MemoMap[K, V]` and exposes target keyed reads:
  `get() -> Result`, `get_or_abort()`, `read() -> Result`, `read_or_abort()`,
  `read_or`, `read_or_else`, plus cache-named helpers.

The remaining compatibility names are useful for old code, accumulator recipes,
and low-level introspection, but they should not gain a second target-like method
set. New code should construct the target facade it intends to use.

## Goals

1. Publish a migration guide that moves callers from `Memo` / `HybridMemo` /
   `MemoMap` to `Derived` / `ReachableDerived` / `DerivedMap`.
2. Provide a conservative codemod that handles mechanically safe type,
   constructor, and method renames.
3. Report context-sensitive read sites instead of rewriting them blindly.
4. Keep the public API unchanged in this phase: zero new methods, zero method
   deletions, zero return-type changes.
5. Prepare a future breaking cleanup that can remove or isolate compatibility
   handles without first creating more compatibility surface.

## Non-goals

- Do not add `Memo::read`, `Memo::get_or_abort`, `HybridMemo::read`,
  `MemoMap::read`, `MemoMap::get_or_abort`, or any other target-vocabulary
  method to compatibility handles.
- Do not deprecate individual compatibility read methods with replacements on
  the same receiver.
- Do not change `Memo::get`, `HybridMemo::get`, or `MemoMap::get` return types.
- Do not delete compatibility handles in Phase 3a.
- Do not coordinate loom/canopy migrations in the same PR. Downstream repos can
  run the migration guide/codemod on their own schedule.
- Do not touch `Signal::get`; inputs cannot cycle and already map cleanly to
  `Input::get`.

## Migration guide

### Type and constructor migration

| Compatibility surface | Target surface | Notes |
|---|---|---|
| `Memo[T]` | `Derived[T]` | Use when the value is an ordinary lazy derived cell. |
| `Memo(rt, compute, label=...)` | `Derived(rt, compute, label=...)` | Preferred constructor form. |
| `Memo::new(rt, compute, label=...)` | `Derived(rt, compute, label=...)` | Modern constructor style avoids `::new`. |
| `HybridMemo[T]` | `ReachableDerived[T]` | Use when reachability propagation is required. |
| `HybridMemo(rt, compute, label=...)` | `ReachableDerived(rt, compute, label=...)` | Same runtime/compute shape. |
| `MemoMap[K, V]` | `DerivedMap[K, V]` | Use for per-key lazy derived values. |
| `MemoMap(rt, compute, label=...)` | `DerivedMap(rt, compute, label=...)` | Same key compute shape. |

Do not migrate automatically when a compatibility handle is used for behavior
that the target facade intentionally does not expose, such as accumulator
collection, low-level dependency timestamps, or compatibility-only observer
recipes. Those sites need a manual choice: keep the compatibility handle for the
low-level operation, or refactor the owning API to expose a target facade plus a
separate diagnostic/introspection path.

### `Memo` read migration

| Compatibility call | Target call | Context |
|---|---|---|
| `memo.get()` | `derived.get_or_abort()` | Inside a tracked compute closure; preserves aborting bare-`T` semantics. |
| `memo.get_result()` | `derived.get()` | Inside a tracked compute closure when cycles should be values. |
| `memo.get_result()` | `derived.read()` | Outside the graph, or in a top-level/test/event-handler read. |
| `rt.read(memo)` | `derived.read_or_abort()` | Outside the graph, aborting convenience. |
| `memo.observe()` | `derived.watch()` | Prefer `Watch` on target facades for long-lived roots. |
| `memo.get_or(fallback)` | `match derived.read() { Ok(v) => v; Err(_) => fallback }` | No single-value target shorthand exists today. |
| `memo.get_or_else(f)` | `match derived.read() { Ok(v) => v; Err(e) => f(e) }` | No single-value target shorthand exists today. |

`memo.get_result()` is intentionally context-sensitive. A codemod must not turn
all call sites into either `get()` or `read()` without knowing whether the read
is inside an active compute closure.

### `HybridMemo` read migration

| Compatibility call | Target call | Context |
|---|---|---|
| `hybrid.get()` | `reachable.get_or_abort()` | Inside a tracked compute closure. |
| `rt.read_hybrid(hybrid)` | `reachable.read_or_abort()` | Outside the graph, aborting convenience. |
| `hybrid.observe()` | `reachable.watch()` | Long-lived outside read root. |

`ReachableDerived::read()` is available for outside reads that should return
`Result[T, CycleError]` instead of aborting.

### `MemoMap` migration

| Compatibility call | Target call | Context |
|---|---|---|
| `map.get_tracked(key)` | `derived_map.get_or_abort(key)` | Strict tracked read, aborting. |
| `map.get_result(key)` | `derived_map.get(key)` | Inside a tracked compute closure when cycles should be values. |
| `map.get_result(key)` | `derived_map.read(key)` | Outside the graph. |
| `map.get(key)` | `derived_map.read_or_abort(key)` | Preserves current permissive aborting semantics. |
| `map.get_or(key, fallback)` | `derived_map.read_or(key, fallback)` | Permissive fallback. |
| `map.get_or_else(key, f)` | `derived_map.read_or_else(key, f)` | Permissive fallback function. |
| `map.contains(key)` | `derived_map.has_cached(key)` | Cache predicate. |
| `map.length()` | `derived_map.cache_len()` | Cache size. |
| `map.sweep()` | `derived_map.sweep_cache()` | Sweep disposed cached entries. |
| `map.clear()` | `derived_map.clear_cache()` | Clear cached entries. |

`MemoMap::get_result(key)` is also context-sensitive. Use `DerivedMap::get(key)`
inside a tracked compute closure and `DerivedMap::read(key)` outside the graph.

## Codemod scope

The codemod should be conservative and report ambiguous sites.

### Safe automatic rewrites

These are syntactic and preserve intent when the surrounding type is also
migrated to the target facade:

- Type names:
  - `@incr.Memo[` → `@incr.Derived[`
  - `@incr.HybridMemo[` → `@incr.ReachableDerived[`
  - `@incr.MemoMap[` → `@incr.DerivedMap[`
- Constructors:
  - `Memo(rt, ...` / `@incr.Memo(rt, ...` → `Derived(rt, ...` /
    `@incr.Derived(rt, ...`
  - `HybridMemo(rt, ...` → `ReachableDerived(rt, ...`
  - `MemoMap(rt, ...` → `DerivedMap(rt, ...`
  - `Memo::new(rt, ...` → `Derived(rt, ...`
  - `HybridMemo::new(rt, ...` → `ReachableDerived(rt, ...`
  - `MemoMap::new(rt, ...` → `DerivedMap(rt, ...`
- Cache/read names with unambiguous target equivalents:
  - `.get_tracked(` → `.get_or_abort(` after `MemoMap` → `DerivedMap`
  - `.get_or(` → `.read_or(` after `MemoMap` → `DerivedMap`
  - `.get_or_else(` → `.read_or_else(` after `MemoMap` → `DerivedMap`
  - `.contains(` → `.has_cached(` after `MemoMap` → `DerivedMap`
  - `.length()` → `.cache_len()` after `MemoMap` → `DerivedMap`
  - `.sweep()` → `.sweep_cache()` after `MemoMap` → `DerivedMap`
  - `.clear()` → `.clear_cache()` after `MemoMap` → `DerivedMap`

### Report-only patterns

The tool should print file/line diagnostics for these, with the migration table
reference in the message:

- `.get()` on values whose old type was `Memo` or `HybridMemo`.
- `.get_result()` on values whose old type was `Memo` or `MemoMap`.
- `Runtime::read(...)`, `read_hybrid(...)`, or `read_reactive(...)` when the
  argument type cannot be proven from the local syntax.
- Any migrated handle that still calls compatibility-only or non-automated APIs
  such as `Memo::get_or`, `Memo::get_or_else`, `Memo::dependencies`,
  `Memo::verified_at`, `Memo::on_change`, `HybridMemo::id`,
  `HybridMemo::dispose`, or `HybridMemo::is_disposed`.

A codemod that cannot distinguish tracked compute closures from top-level code
must not guess. It should leave a report for the developer to apply the strict
vs permissive rule manually.

## Implementation PR shape

Implemented as a docs/tooling slice with no public API edits:

1. **`docs(incr): document compatibility-to-facade read migration`**
   - Update `CHANGELOG.md` with a migration guide.
   - Update `docs/api-reference.mbt.md` compatibility sections to point from
     old handles to target facades.
   - Keep checked target examples unchanged unless a new guide snippet is added
     as a checked `.mbt.md` example.

2. **`chore(incr): add conservative target-facade migration codemod`**
   - Add a script under `scripts/`.
   - Support a dry-run/report mode by default.
   - Require an explicit `--apply` flag for safe rewrites; files with manual
     findings are skipped rather than half-migrated.
   - Scan MoonBit sources and `.mbt.md` literate examples by default; require
     `--include-md` before touching prose Markdown.
   - Print report-only sites for manual strict/permissive decisions.

3. **`docs(incr): revise Phase 3 plan around facade migration`**
   - Keep this plan and the parent migration plan aligned.
   - Do not add `.mbti` changes.

## Verification

Because Phase 3a no longer changes public API, expected interface diffs are
empty:

```bash
moon fmt
moon check
git diff -- '*.mbti'        # must be empty
git diff --check
```

If the codemod script is added, run it in dry-run mode against the repository
and confirm it reports ambiguous compatibility sites without editing files.

No `moon info` output should be committed unless another change requires it.

## Future cleanup

The next breaking phase should be a compatibility cleanup, not a same-receiver
semantic flip on `Memo` / `MemoMap`:

- remove compatibility handles and methods, or move them behind an explicitly
  legacy surface;
- keep target facades as the canonical API;
- update docs to present compatibility names only in migration notes or archive
  material.

If a future release decides to keep `Memo`, `HybridMemo`, or `MemoMap` as public
long-term names, that release can reconsider same-receiver aliases. Until then,
do not grow those handles.
