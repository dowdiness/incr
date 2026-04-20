# Runtime Modularization Stage 5: Internal Package Split (narrow)

**Status:** Approved design (Option A — narrow scope)

**Date:** 2026-04-18

**Prerequisites:**
- Phase 2 PR #36 merged (coordinator routing via `propagate_changes`)
- MoonBit `internal` package feature available (verified on moon 0.1.20260409 — see [Phase 2 design](2026-04-16-runtime-modularization-phase2-design.md))

**Supersedes:** PR 2 section of [`2026-04-16-runtime-modularization-phase2-design.md`](2026-04-16-runtime-modularization-phase2-design.md). Two rounds of Codex review on 2026-04-18 identified six design-level issues in the original partition:

1. `CellLifecycle` method signatures take `Runtime` → moving to `internal/shared/` creates a back-edge. (Round 1)
2. `MemoData.compute` has type `Result[Bool, CycleError]` → moving `MemoData` requires `CycleError` to be visible from `internal/pull/`. (Round 1)
3. `PushEntry` stores `CellRef` → moving to `internal/push/` while `CellRef` stays in `cells/` creates a back-edge. (Round 1)
4. `pub` struct fields are readonly across packages; `cells/` mutates and constructs engine SoA types → the move requires `pub(all)`, not `pub`. (Round 2)
5. MoonBit only permits *private* extension methods on foreign types. `CycleError::format_path(rt : Runtime)` cannot live in `cells/` if `CycleError` is moved to `internal/shared/`. (Round 2)
6. Engine source files contain public handle types and constructors (`Reactive`, `Effect`, `Relation`, `FunctionalRelation`, `Rule`) — they cannot be deleted; they must be split into "SoA moves, handle stays." (Round 2)

This spec is **Option A: narrow scope** — the partition that survives all six constraints. It achieves structural isolation for push and datalog engines, and a *partial* split for pull (signals only), while leaving memos, `CycleError`, and all handles in `cells/`.

---

## Goal

Partition `cells/` into a thinner coordinator plus three engine sub-packages (shared + pull-signal + push + datalog) under `cells/internal/`. Establish compile-time and lint-time boundaries that prevent engines from coupling to each other and prevent external consumers from reaching engine internals.

**Hard constraints:**
- Zero public API change (`pkg.generated.mbti` for `incr/` and `incr/tests/` byte-identical before/after)
- Zero algorithm change (`verify.mbt`, `push_propagate.mbt`, `batch.mbt`, `datalog_fixpoint.mbt` stay in `cells/` unchanged)
- Zero handle relocation (`Signal[T]`, `Memo[T]`, `HybridMemo[T]`, `TrackedCell[T]`, `Reactive[T]`, `Effect`, `Relation[T]`, `FunctionalRelation[T, U]`, `Rule` all stay in `cells/`)
- All 506 existing tests pass after every commit

---

## Architecture

### Target package graph

```text
types/                           (pure values: CellId, Revision, Durability, GcRole, ...)
  ↑
cells/internal/shared/           (traits + CellMeta + CellRef; pub(open) for traits)
  ↑           ↑           ↑
internal/pull/  internal/push/  internal/datalog/   (engine SoA + pub impl trait impls)
  ↑           ↑           ↑
cells/                           (coordinator: Runtime, CycleError, MemoData,
                                  handles, algorithms, CellLifecycle, tests)
```

**No back-edges:** internal packages never import `dowdiness/incr/cells`.

**No cross-engine imports:** `internal/pull/` does not import `internal/push/` or `internal/datalog/`, and symmetrically for the other two.

**No internal-to-internal-engine imports from `shared/`:** `internal/shared/` imports only `types/` + hashset.

**MoonBit semantics relied on** (verified — Phase 2 spec + Codex round 2):
- Parent `cells/` can import `cells/internal/<child>/`. Allowed.
- External packages importing `cells/internal/<child>/` produce a compile error.
- Internal siblings can import each other — *not* blocked by `internal`. Must be enforced externally (see [Boundary verification](#boundary-verification)).
- Cross-package trait implementations require (a) the trait to be `pub(open)` and (b) the impl to be `pub impl`.
- A struct declared `pub` is readonly from other packages. To let another package construct or mutate instances, declare `pub(all)`.
- Methods defined on a foreign type must be *private* extension methods unless the method lives in the type's home package.
- Explicit `impl Trait for Type` is required even when defaults exist.

### Partition

| Destination                  | Symbols                                                                                                                                                                                                                                                                                                                   | Notes |
|------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------|
| `cells/internal/shared/`     | **Traits** (`pub(open)`): `CellOps`, `Committable`, `HasCellMeta`. **Types** (`pub(all)`): `CellMeta`, `CellRef`.                                                                                                                                                                                                         | Imports `types/` (which already owns `GcRole`) and `moonbitlang/core/hashset` (`CellMeta.subscribers : HashSet[CellId]`; `CellOps::subscribers` returns the same). **No `CycleError`** — it stays in `cells/` (see [Why `CycleError` stays](#why-cycleerror-stays)). |
| `cells/internal/pull/`       | **Type** (`pub(all)`): `PullSignalData`. **`pub impl`**: `CellOps for PullSignalData`, `HasCellMeta for PullSignalData`, `Committable for PullSignalData`.                                                                                                                                                                | **No `MemoData`** — it stays in `cells/` (see [Why `MemoData` stays](#why-memodata-stays)). No `PullVerifyFrame` — algorithm-local to `cells/verify.mbt`. |
| `cells/internal/push/`       | **Types** (`pub(all)`): `PushReactiveData`, `PushEffectData`. **`pub impl`**: `CellOps for PushReactiveData`, `HasCellMeta for PushReactiveData`, `CellOps for PushEffectData`, `HasCellMeta for PushEffectData`.                                                                                                         | No `PushEntry` — algorithm-local, stores `CellRef`, stays in `cells/push_propagate.mbt`. |
| `cells/internal/datalog/`    | **Types** (`pub(all)`): `RelationData`, `FunctionalRelationData`, `RuleData`. **`pub impl`**: `CellOps` + `HasCellMeta` for each.                                                                                                                                                                                         | Handle types (`Relation`, `FunctionalRelation`, `Rule`) stay in `cells/` — see Commit D. |
| **Stays in `cells/`**        | `Runtime`, `RuntimeCore`, `RevisionState`, `TrackingState`, `BatchState`, `PullState`, `PushState`, `DatalogState`, `PropagationPhase`, `ActiveQuery`. **`CellLifecycle` trait** + engine impls that need co-location (see Commit B/C/D notes below). **`CycleError`** (data + all methods including `format_path`). **`MemoData`** (SoA for memo cells — including its own `CellLifecycle` impl, which stays alongside the struct). **`PushEntry`** (push propagation priority-queue item). **`PullVerifyFrame`** (iterative verify frame). All handles (`Signal`, `Memo`, `HybridMemo`, `TrackedCell`, `Relation`, `FunctionalRelation`, `Reactive`, `Effect`, `Scope`, `Observer`, `MemoMap`) + their constructors. Public rule API (`Runtime::new_rule`, `Runtime::assert_rule_relation_id` — there is no `Rule` handle type; the user-facing identifier is `RuleId` from `types/`). All algorithms (`verify.mbt`, `push_propagate.mbt`, `batch.mbt`, `datalog_fixpoint.mbt`, `tracking.mbt`, `runtime.mbt`, `scope.mbt`, `memo_map.mbt`, `introspection.mbt`). All `*_test.mbt` and `*_wbtest.mbt`. | |

### Why `CellLifecycle` stays

`CellLifecycle` trait methods take `Runtime` (`cells/cell_ops.mbt:213-217`):

```moonbit
priv trait CellLifecycle {
  dispose_cell(Self, Runtime, CellId) -> Unit
  on_observe(Self, Runtime, CellId) -> Unit = _
  on_unobserve(Self, Runtime, CellId) -> Unit = _
}
```

Impls call `rt.remove_subscriber`, `rt.core.cell_index`, `rt.pull.free_memos.push`, etc. (e.g. `cells/pull_memo.mbt:43-60`). Moving the trait to `internal/shared/` forces engines to import `Runtime`, creating `cells/ → internal/* → cells/` cycles.

**Resolution:** Trait + all impls stay in `cells/` (impls extracted to dedicated `cells/{pull,push,datalog}_lifecycle.mbt` files for readability). MoonBit's orphan rule permits `impl LocalTrait for ForeignType`, and the impls reach into `internal/*/` SoA fields via the `pub(all)` visibility described above.

### Why `CycleError` stays

`CycleError::format_path(self, rt : Runtime) -> String` is part of the public API (`cells/cycle.mbt:81`). MoonBit permits only *private* extension methods on foreign types. If we move `CycleError` into `internal/shared/`, `format_path` must move with it — but `format_path` needs `Runtime` from `cells/`, which would create a back-edge.

Changing `format_path`'s signature to not take `Runtime` (e.g., take a `fn (CellId) -> String?` label-lookup callback) is a public API change, violating the `.mbti` byte-stability constraint.

**Resolution:** `CycleError` data + all methods stay in `cells/cycle.mbt` unchanged. The root facade's `pub using @internal { type CycleError }` (`incr.mbt:27`) continues to resolve without edit.

### Why `MemoData` stays

`MemoData.compute` has type `() -> Result[Bool, CycleError]` (`cells/pull_memo.mbt:9`). Moving `MemoData` to `internal/pull/` would require `CycleError` to be reachable there, which — given [Why `CycleError` stays](#why-cycleerror-stays) — would require either a back-edge or a signature change. Neither is acceptable.

**Resolution:** `MemoData` + its `CellOps`/`HasCellMeta` impls + the full `pull_memo.mbt` source stay in `cells/`. `internal/pull/` contains only `PullSignalData`. This is a narrower split than the original vision, but it is the largest slice compatible with the hard constraints.

A follow-up ticket can revisit this once `CycleError` can be redesigned (e.g., move its data payload into `types/` with a non-`Runtime` rendering API). Tracked in [Out of scope](#out-of-scope).

### Why `PushEntry` stays

`PushEntry` (`cells/push_propagate.mbt:7`) stores a `CellRef` and is used only by `push_propagate.mbt`'s priority queue. `CellRef` itself moves to `internal/shared/` (it stores indices, not engine types), but `PushEntry` is algorithm-local and has no cross-engine use.

**Resolution:** `PushEntry` + its `Eq`/`Compare` impls stay in `cells/push_propagate.mbt`.

### Why engine source files split, not delete

Files like `cells/push_reactive.mbt` contain *both* the SoA struct (`PushReactiveData`) and the public handle type (`Reactive[T]`) with its constructor. Handles must stay in `cells/` as the unified user-facing surface. So each engine source file splits:

| Original file                         | New location of SoA         | New location of handle                          |
|---------------------------------------|-----------------------------|-------------------------------------------------|
| `cells/pull_signal.mbt`               | `cells/internal/pull/pull_signal.mbt`   | (Signal handle is in `cells/signal.mbt` already) |
| `cells/push_reactive.mbt`             | `cells/internal/push/push_reactive_data.mbt` | `cells/push_reactive.mbt` (trimmed to `Reactive[T]` + constructor) |
| `cells/push_effect.mbt`               | `cells/internal/push/push_effect_data.mbt`   | `cells/push_effect.mbt` (trimmed to `Effect` + constructor) |
| `cells/datalog_relation.mbt`          | `cells/internal/datalog/relation_data.mbt`   | `cells/datalog_relation.mbt` (trimmed to `Relation[T]` + constructor) |
| `cells/datalog_functional_relation.mbt` | `cells/internal/datalog/functional_relation_data.mbt` | `cells/datalog_functional_relation.mbt` (trimmed to `FunctionalRelation[T, U]` + constructor) |
| `cells/datalog_rule.mbt`              | `cells/internal/datalog/rule_data.mbt`       | `cells/datalog_rule.mbt` (trimmed to the public `Runtime::new_rule` function and the `Runtime::assert_rule_relation_id` helper — there is no `Rule` handle struct in this codebase; `RuleId` is the only user-facing identifier and already lives in `types/`). |

### Visibility changes summary

| Symbol                    | Old (in `cells/`) | New                                              | Reason                                                       |
|---------------------------|-------------------|--------------------------------------------------|--------------------------------------------------------------|
| `CellOps`                 | `priv`            | `pub(open)` in `internal/shared/`                | Engine packages implement it from a different package.       |
| `HasCellMeta`             | `priv`            | `pub(open)` in `internal/shared/`                | Same.                                                        |
| `Committable`             | `priv`            | `pub(open)` in `internal/shared/`                | `PullSignalData` (in `internal/pull/`) implements it.        |
| `CellMeta`                | `priv`            | `pub(all)` in `internal/shared/`                 | Engines embed and construct it; `cells/` reads/mutates fields. |
| `CellRef`                 | `priv`            | `pub(all)` in `internal/shared/`                 | `cells/` matches on it and constructs new values (e.g. `Disposed`). |
| Engine SoA structs (PullSignalData, PushReactiveData, PushEffectData, RelationData, FunctionalRelationData, RuleData) | `priv` | `pub(all)` in their `internal/*/` | Coordinator + algorithms + lifecycle impls + wbtests read and mutate fields. |
| Engine SoA fields         | (struct-private)  | part of the `pub(all)` struct (plain `mut` fields) | Same.                                                        |
| Trait impls on moved SoA types | `impl`       | `pub impl`                                       | Required for cross-package trait-object dispatch (`&CellOps`, `&Committable`). |
| `CellLifecycle`           | `priv`            | `priv` (unchanged) in `cells/`                   | Stays — see above.                                           |
| `CycleError`              | `pub`             | `pub` (unchanged) in `cells/`                    | Stays — see above.                                           |
| `MemoData`                | `priv`            | `priv` (unchanged) in `cells/`                   | Stays — see above.                                           |

All visibility expansions are bounded by `internal/`: nothing leaks to external consumers.

---

## Invariants

### Behavioral invariants (preserved by existing 506 tests — the safety net)

1. **Push propagation is level-sorted.** Higher-level cells never compute before their lower-level inputs in a single propagation wave. Covered by `cells/push_reactive_wbtest.mbt`, `cells/push_reachable_wbtest.mbt`.
2. **Callback snapshot before propagation.** In `commit_batch` and `signal.set_unconditional`, per-cell `on_change` callbacks are snapshotted *before* `propagate_changes` runs. Callbacks registered or cleared during propagation do not affect the current wave. Covered by `cells/callback_test.mbt`, `cells/batch_wbtest.mbt`.
3. **Phase mutual exclusion.** `PropagationPhase` transitions never overlap; re-entry panics. Covered by `cells/cycle_test.mbt`.
4. **Pull-verify cycle detection returns `CycleError`.** Self-referential or mutually recursive memos return `Err(CycleDetected(...))`, never abort. Covered by `cells/cycle_path_test.mbt`, `cells/cycle_test.mbt`.
5. **Dispose/GC reference-count semantics.** `add_gc_root`/`remove_gc_root` maintain counts; `on_unobserve` fires only on `1→0` transitions. Covered by `cells/gc_test.mbt`, `cells/dispose_test.mbt`, `cells/observer_test.mbt`.
6. **Batch rollback preserves revision integrity.** A raised exception inside `Runtime::batch` rolls back pending writes; revision counter does not regress. Covered by `cells/batch_wbtest.mbt`, `tests/integration_test.mbt`.

### Structural invariants (new — verified by added boundary checks)

1. **Engine packages are pairwise-disjoint.** `cells/internal/pull/moon.pkg` does not import `cells/internal/push/` or `cells/internal/datalog/`. Symmetric for the other two.
2. **Shared is a leaf.** `cells/internal/shared/moon.pkg` imports only `dowdiness/incr/types` and `moonbitlang/core/hashset`. It does not import any engine package nor `cells/`.
3. **No back-edges.** No `cells/internal/*/moon.pkg` imports `dowdiness/incr/cells`.
4. **External-import guard.** External consumers cannot import `cells/internal/*` (MoonBit `internal` enforces; optional negative compile probe in Layer 3).
5. **`.mbti` stability.** `pkg.generated.mbti` for the root `incr/` package and for `incr/tests/` is byte-identical before vs. after the refactor.

---

## Boundary verification

Three layers, ordered from fastest to most thorough:

### Layer 1: `scripts/check-engine-isolation.sh`

Shell script run in CI and locally before each commit. Uses exact quoted-path matching (no substring grep). Asserts structural invariants 1, 2, and 3.

```bash
#!/usr/bin/env bash
# scripts/check-engine-isolation.sh
# Asserts internal-package isolation rules for the incr library.
set -euo pipefail

fail=0
engines=(pull push datalog)

# Extract imports as exact quoted strings from a moon.pkg file.
# Returns each imported package path, one per line, without quotes.
# Handles both `#` and `//` line comments (this repo uses `//`), and
# excludes the `"test"` discriminator from `} for "test"` import blocks.
extract_imports() {
  local file="$1"
  # Strip `//` line comments first (preserves the rest of the line), then
  # strip `#` line comments, then match quoted strings, then drop the
  # sentinel "test" value which is MoonBit import-block syntax, not an
  # import path. The `{ ... } || true` grouping ensures the function
  # returns exit 0 on "no matches" — without it, `set -o pipefail` would
  # propagate grep's exit 1 out through the `imports=$(...)` callers and
  # silently abort the script for packages with no quoted imports.
  {
    sed 's|//.*$||; s|#.*$||' "$file" \
      | grep -oE '"[^"]+"' \
      | tr -d '"' \
      | grep -vFx 'test'
  } || true
}

# Invariant 1: no cross-engine sibling imports.
for engine in "${engines[@]}"; do
  pkg="cells/internal/$engine/moon.pkg"
  if [ ! -f "$pkg" ]; then
    echo "MISSING: $pkg"
    fail=1
    continue
  fi
  imports=$(extract_imports "$pkg")
  for other in "${engines[@]}"; do
    [ "$engine" = "$other" ] && continue
    if echo "$imports" | grep -Fxq "dowdiness/incr/cells/internal/$other"; then
      echo "FAIL: cells/internal/$engine imports cells/internal/$other"
      fail=1
    fi
  done
done

# Invariant 2: internal/shared is a leaf — no engine imports, no back-edge.
shared_pkg="cells/internal/shared/moon.pkg"
if [ -f "$shared_pkg" ]; then
  imports=$(extract_imports "$shared_pkg")
  for other in "${engines[@]}"; do
    if echo "$imports" | grep -Fxq "dowdiness/incr/cells/internal/$other"; then
      echo "FAIL: cells/internal/shared imports cells/internal/$other"
      fail=1
    fi
  done
  # shared must not back-edge into cells/
  if echo "$imports" | grep -E '^dowdiness/incr/cells($|/)' | grep -vE '^dowdiness/incr/cells/internal($|/)' | grep -q .; then
    echo "FAIL: cells/internal/shared imports cells/ (back-edge)"
    fail=1
  fi
fi

# Invariant 3: no back-edges from any internal/* to cells/.
for engine in shared "${engines[@]}"; do
  pkg="cells/internal/$engine/moon.pkg"
  [ -f "$pkg" ] || continue
  imports=$(extract_imports "$pkg")
  # Any import starting with "dowdiness/incr/cells" that is NOT a
  # "dowdiness/incr/cells/internal/..." path counts as a back-edge.
  if echo "$imports" | grep -E '^dowdiness/incr/cells($|/)' | grep -vE '^dowdiness/incr/cells/internal($|/)' | grep -q .; then
    echo "FAIL: cells/internal/$engine imports cells/ (back-edge)"
    fail=1
  fi
done

exit "$fail"
```

The script matches import paths as *whole* strings (`grep -Fxq`) to avoid substring false-positives, filters out `#`-comment lines, and treats `moon.pkg` as an ordered list of quoted import paths (matches the format's actual grammar).

### Layer 2: `.mbti` diff check

Run after each commit:

```bash
moon info
git diff --exit-code pkg.generated.mbti tests/pkg.generated.mbti
```

A non-empty diff means a moved type has leaked into the public API surface. Investigate and fix before committing.

### Layer 3: Negative compile probe (deferred follow-up)

A tiny throwaway package outside `cells/` that imports `dowdiness/incr/cells/internal/pull` and asserts `moon check` rejects it. This validates MoonBit's `internal` enforcement on the *current* moon version. Not required for Stage 5 acceptance because it tests moon's behavior, not our code.

---

## Execution sequence

Six commits, staged shared-first. All commits run inside the worktree at `loom/incr/.worktrees/refactor-incr-structure` on branch `refactor/incr-structure`.

### Commit A: extract `cells/internal/shared/`

**Files added:**
- `cells/internal/shared/moon.pkg` — imports `dowdiness/incr/types` (alias `@incr_types`), `moonbitlang/core/hashset`.
- `cells/internal/shared/cell_meta.mbt` — `pub(all) struct CellMeta { ... }`.
- `cells/internal/shared/cell_ref.mbt` — `pub(all) enum CellRef { ... }`.
- `cells/internal/shared/cell_ops.mbt` — `pub(open) trait CellOps`, `pub(open) trait HasCellMeta`, `pub(open) trait Committable`, default impls (`GcRole` continues to come from `types/`).

**Files modified:**
- `cells/cell_ops.mbt` — keep only `priv trait CellLifecycle` + its default impls; `using @shared { trait CellOps, trait HasCellMeta, trait Committable, type CellMeta }`.
- `cells/cell.mbt` — add `using @shared { type CellRef }` so existing sites referencing `CellRef` unqualified keep compiling.
- `cells/cell_ref.mbt` — delete (content moved to `internal/shared/cell_ref.mbt`).
- `cells/moon.pkg` — add `import "dowdiness/incr/cells/internal/shared" @shared`.

**Not in this commit:** `CycleError` stays put; `MemoData` stays put.

**Verification:**
- `moon check` passes
- `moon test` passes (506 tests)
- `moon info && moon fmt`
- `git diff pkg.generated.mbti tests/pkg.generated.mbti` empty

**Commit message:**
```text
refactor: extract cells/internal/shared trait+type package

Move CellOps, HasCellMeta, Committable, CellMeta, CellRef into
cells/internal/shared/. Trait visibility flipped to pub(open);
struct/enum visibility to pub(all) so cells/ can continue to
construct and mutate instances. Bounded by MoonBit `internal` —
no external visibility change.

CycleError, MemoData, and CellLifecycle all stay in cells/ because
their method signatures or payloads reference Runtime.
```

### Commit B: move `PullSignalData` to `cells/internal/pull/`

**Files added:**
- `cells/internal/pull/moon.pkg` — imports `types`, `internal/shared`, `moonbitlang/core/hashset`, `moonbitlang/core/hashmap`.
- `cells/internal/pull/pull_signal.mbt` — `pub(all) struct PullSignalData { ... }`, `pub impl CellOps for PullSignalData`, `pub impl HasCellMeta for PullSignalData`, `pub impl Committable for PullSignalData`.

**Files added in `cells/`:**
- `cells/pull_lifecycle.mbt` — contains only `impl CellLifecycle for PullSignalData` (it replaces the impl that used to live inside `cells/pull_signal.mbt`). The `CellLifecycle for MemoData` impl stays in `cells/pull_memo.mbt` alongside `MemoData` itself — no need to co-locate impls for types that are not moving.

**Files modified:**
- `cells/pull_signal.mbt` — delete (content moved).
- `cells/pull_memo.mbt` — unchanged (struct, trait impls including `CellLifecycle`, all stay as they are today).
- `cells/runtime.mbt`, `cells/verify.mbt`, `cells/batch.mbt`, `cells/signal.mbt`, `cells/memo.mbt`, `cells/hybrid_memo.mbt`, `cells/introspection.mbt` — add `import "dowdiness/incr/cells/internal/pull" @pull` or `using @pull { type PullSignalData }` as needed.
- `cells/moon.pkg` — add the `@pull` import.
- `cells/*_wbtest.mbt` files that touch `PullSignalData` — update to reach through `@pull`.

**Verification:** same as Commit A.

**Commit message:**
```text
refactor: move PullSignalData to cells/internal/pull

PullSignalData + its CellOps, HasCellMeta, and Committable impls
move to cells/internal/pull with pub(all) visibility. The trait
impls are marked pub impl so cells/ can dispatch through &CellOps
and &Committable across the package boundary.

MemoData stays in cells/ because its compute closure references
CycleError (which cannot leave cells/ without breaking the
format_path public method). Its CellLifecycle impl stays inside
cells/pull_memo.mbt alongside the struct. The PullSignalData
CellLifecycle impl moves to cells/pull_lifecycle.mbt.
```

### Commit C: move push engine to `cells/internal/push/`

**Files added:**
- `cells/internal/push/moon.pkg` — imports `types`, `internal/shared`, `moonbitlang/core/hashset`.
- `cells/internal/push/push_reactive_data.mbt` — `pub(all) struct PushReactiveData { ... }`, `pub impl CellOps for PushReactiveData`, `pub impl HasCellMeta for PushReactiveData`.
- `cells/internal/push/push_effect_data.mbt` — `pub(all) struct PushEffectData { ... }`, `pub impl CellOps for PushEffectData`, `pub impl HasCellMeta for PushEffectData`.

**Files added in `cells/`:**
- `cells/push_lifecycle.mbt` — `impl CellLifecycle for PushReactiveData`, `impl CellLifecycle for PushEffectData`.

**Files modified (file split, not delete):**
- `cells/push_reactive.mbt` — remove `PushReactiveData` struct, its `CellOps`/`HasCellMeta` impls, and its `clear_slot` method (currently at approx. lines 1-114); keep `Reactive[T]` handle, `Reactive::new`, and user-facing methods (approx. lines 116-257). Add `using @push { type PushReactiveData }`.
- `cells/push_effect.mbt` — remove `PushEffectData` struct, its `CellOps`/`HasCellMeta` impls, and its `clear_slot` method (approx. lines 1-89); keep `Effect` handle + constructor (approx. lines 91-164). Add `using @push { type PushEffectData }`.
- `cells/push_propagate.mbt` — keep `PushEntry`; update imports.
- `cells/runtime.mbt`, `cells/introspection.mbt`, `cells/scope.mbt` — update imports.
- `cells/moon.pkg` — add `import "dowdiness/incr/cells/internal/push" @push`.
- `cells/*_wbtest.mbt` for push — update imports; any field access goes through the `pub(all)` fields.

**Verification:** same.

**Commit message:**
```text
refactor: move push engine SoA to cells/internal/push

PushReactiveData and PushEffectData move to cells/internal/push with
pub(all) visibility and pub impl for CellOps/HasCellMeta. Handle
types (Reactive[T], Effect) and their constructors remain in cells/
as the user-facing API. PushEntry stays with push_propagate.mbt;
CellLifecycle impls move to cells/push_lifecycle.mbt.
```

### Commit D: move datalog engine to `cells/internal/datalog/`

**Files added:**
- `cells/internal/datalog/moon.pkg` — imports `types`, `internal/shared`, `moonbitlang/core/hashset`.
- `cells/internal/datalog/relation_data.mbt` — `pub(all) struct RelationData { ... }`, `pub impl CellOps for RelationData`, `pub impl HasCellMeta for RelationData`.
- `cells/internal/datalog/functional_relation_data.mbt` — same pattern for `FunctionalRelationData`.
- `cells/internal/datalog/rule_data.mbt` — same pattern for `RuleData`.

**Files added in `cells/`:**
- `cells/datalog_lifecycle.mbt` — `impl CellLifecycle for RelationData`, `impl CellLifecycle for FunctionalRelationData`, `impl CellLifecycle for RuleData`.

**Files modified (file split):**
- `cells/datalog_relation.mbt` — remove `RelationData` struct + its `CellOps`/`HasCellMeta` impls (approx. lines 1-24); keep `Relation[T]` handle + `Relation::new` + user-facing methods (approx. lines 26-187). Add `using @datalog { type RelationData }`.
- `cells/datalog_functional_relation.mbt` — remove `FunctionalRelationData` struct + impls (approx. lines 1-28); keep `FunctionalRelation[T, U]` handle + constructor (approx. lines 30-250). Add `using @datalog { type FunctionalRelationData }`.
- `cells/datalog_rule.mbt` — remove `RuleData` struct + its `CellOps`/`HasCellMeta` impls (approx. lines 1-28); keep the public `Runtime::new_rule` method and `Runtime::assert_rule_relation_id` helper (approx. lines 31-98). There is no `Rule` handle struct. Add `using @datalog { type RuleData }`.
- `cells/datalog_fixpoint.mbt` — update imports.
- `cells/runtime.mbt`, `cells/introspection.mbt` — update imports.
- `cells/moon.pkg` — add `import "dowdiness/incr/cells/internal/datalog" @datalog`.
- `cells/*_wbtest.mbt` for datalog — update imports.

**Verification:** same.

**Commit message:**
```text
refactor: move datalog engine SoA to cells/internal/datalog

RelationData, FunctionalRelationData, RuleData move to
cells/internal/datalog with pub(all) visibility and pub impl for
CellOps/HasCellMeta. Handle types (Relation[T], FunctionalRelation
[T, U]) and their constructors remain in cells/. RuleData has no
handle type — rules are constructed via Runtime::new_rule, which
stays in cells/ alongside its helpers. CellLifecycle impls in
cells/datalog_lifecycle.mbt. Fixpoint algorithm unchanged.
```

### Commit E: add boundary checks

**Files added:**
- `scripts/check-engine-isolation.sh` (content above); `chmod +x`.

**Verification:**
- Run the script — must exit 0.
- Manually corrupt one engine's `moon.pkg` to import another, run the script, confirm exit 1, revert.
- Repeat for the shared-is-leaf and no-back-edge cases.

**Commit message:**
```text
test: add engine-isolation boundary checks

Shell script asserts (a) no cross-engine sibling imports,
(b) internal/shared is a leaf (no engine imports, no back-edge),
(c) no back-edges from cells/internal/* to cells/. Uses exact
quoted-path matching and filters # comments.
```

### Commit F: documentation

**Files modified:**
- `CLAUDE.md` — replace the package map's `cells/` section with the new `cells/` + `cells/internal/{shared,pull,push,datalog}/` layout. Document that (a) handles, algorithms, tests stay in `cells/`, (b) `MemoData` + `CycleError` stay in `cells/` for reasons described in this spec, (c) engine data types live in `internal/*/` with `pub(all)` visibility.
- `docs/todo.md` — for the "Runtime Modularization (Phase 4 — Remaining)" section, mark the first item partially done ("pull engine split: signals only; memos deferred pending CycleError redesign") and the second item done.
- `docs/design.md` — update the Architecture section to reference the `cells/internal/` layout.
- `docs/README.md` — link to this spec.

**Verification:**
- `bash check-docs.sh` passes.

**Commit message:**
```text
docs: update CLAUDE.md + todo + design.md for internal split

Refresh the package map to reflect cells/internal/{shared,pull,
push,datalog}/ layout. Note that pull-engine split is partial
(signals only; memos stay in cells/ because MemoData.compute
references CycleError). Track the memo move as a follow-up
requiring CycleError redesign.
```

---

## Risks

### R1: `CellLifecycle` orphan-rule confusion (low)
**Risk:** `impl CellLifecycle for PullSignalData` placed in `cells/` while `PullSignalData` lives in `internal/pull/` could be misread as an orphan-rule violation.
**Mitigation:** MoonBit's rule is "at least one of (trait, type) must be local." The trait is local to `cells/`; the impl is in the trait's home package. Caught immediately by `moon check` if wrong.

### R2: `pub(all)` visibility audit miss (medium)
**Risk:** An SoA field accessed or mutated by `cells/runtime.mbt`, `cells/verify.mbt`, `cells/introspection.mbt`, `cells/batch.mbt`, a lifecycle impl, or a wbtest may fail to compile if the containing struct is declared `pub` (readonly) instead of `pub(all)`. Codex round 2 enumerated the specific call sites: `runtime.mbt:290`, `memo.mbt:53`, `hybrid_memo.mbt:38`, `push_reactive.mbt:159`, `datalog_relation.mbt:56`, `batch_wbtest.mbt:352`.
**Mitigation:** Declare every moved struct `pub(all)` from the start. Per-commit `moon check` catches any miss. The exposure is bounded by `internal/` so no public API impact.

### R3: Missing `pub impl` on trait implementations (medium)
**Risk:** If `impl CellOps for PullSignalData` in `internal/pull/` is not declared `pub impl`, `cells/` cannot dispatch through `&CellOps` across the package boundary. Affected call sites include `runtime.mbt:63, 308`, `memo.mbt:74`, `signal.mbt:260`.
**Mitigation:** Every trait impl in a moved engine package must start with `pub impl`. Per-commit `moon check` catches omissions. Documented explicitly in each commit's file list.

### R4: Handle-file split leaves dead code or stale imports (medium)
**Risk:** Commits C and D split files like `cells/push_reactive.mbt` by removing the SoA portion and keeping the handle portion. Dead imports or unused helper functions may linger.
**Mitigation:** Run `moon check` for warnings after each split; delete any genuinely orphaned helper. Do not rename the remaining file unless the whole file is gone.

### R5: Whitebox test reachability (low)
**Risk:** Whitebox tests (`cells/cell_ref_wbtest.mbt`, `cells/verify_wbtest.mbt`, `cells/memo_map_wbtest.mbt`, `cells/batch_wbtest.mbt`, `cells/push_reactive_wbtest.mbt`, `cells/datalog_wbtest.mbt`) directly construct or mutate engine SoA fields. With `pub(all)` fields in `internal/*/`, the parent `cells/` (where wbtests live) retains field access.
**Mitigation:** Per-commit `moon test` (506 tests). Failures expected to be stale imports; mechanical to fix.

### R6: Behavioral regression hidden by mechanical-looking edits (medium)
**Risk:** Re-routing through new package boundaries could subtly change initialization order, default trait dispatch, or `pub(open)` impl resolution.
**Mitigation:**
- Existing 506 tests cover the behavioral invariants enumerated above.
- Run `moon bench --release` before Commit A and after Commit F. Investigate any >5% hot-path regression.

### R7: `internal` package feature regression in future moon versions (low)
**Risk:** A future `moon` version changes `internal` semantics, allowing external imports.
**Mitigation:** Layer 3 negative-compile probe (deferred). Until then, the verified moon version (0.1.20260409) is documented.

---

## Out of scope

- **Moving `MemoData` to `internal/pull/`.** Blocked by `CycleError` living in `cells/`. Requires a follow-up that either (a) redesigns `CycleError::format_path` to not take `Runtime`, or (b) moves `CycleError`'s data payload to `types/` with a non-`Runtime` rendering pathway. Tracked as a new `docs/todo.md` item ("Complete pull-engine split: move MemoData once CycleError is untangled").
- **Moving `CycleError` into any other package.** Same blocker — it's a bundled data + public method on foreign type. Defer with MemoData.
- **Removing `incr/pipeline/` package.** Tracked in `docs/todo.md:292-294` ("Pipeline Traits — Deferred"). Out of scope.
- **Refactoring `CellLifecycle` to remove the `Runtime` parameter.** Could enable moving the trait into `internal/shared/`. Significant design work; defer until a feature pushes for it.
- **Splitting handles into per-engine packages.** Would force users to import multiple internal packages. Handles stay in `cells/` as the unified user-facing surface.
- **Splitting algorithms** (`verify.mbt`, `push_propagate.mbt`, `batch.mbt`, `datalog_fixpoint.mbt`) into engine packages. Algorithms cross engine boundaries via the `CellOps` dispatch. Splitting would require duplicating dispatch glue. Defer.
- **Removing the `pkg.generated.mbti` byte-stability requirement** in favor of semantic equivalence checking. The project's CI relies on byte-stability.

---

## Lessons captured

This spec exists because the prior Phase 2 PR 2 partition table was "validated" in `design.md` and memory but had never been tried against the compiler. Three rounds of Codex review on 2026-04-18 caught nine issues in sequence — three cycle-creating partition mistakes on round 1, three MoonBit-language-rule violations on round 2 (visibility readonly semantics, orphan public methods, file-split vs. file-delete for handle code), and three consistency / accuracy issues on round 3 (self-contradictory lifecycle-impl placement in Commit B, a nonexistent "Rule handle" referenced in the datalog commit, and a boundary script that didn't match the repo's actual `moon.pkg` syntax, including `//` comments and `for "test"` discriminators).

**Lessons:**
1. **"Validated" architecture-doc partition tables that haven't been compile-tested are not validated.** For any future partition refactor, the design step must include either a throwaway compile probe of the partition or explicit grep-based audits of (a) trait method signatures, (b) struct field types, (c) method visibility on types the plan moves.
2. **Partition tables must distinguish SoA (data) from handle (API).** Engine source files in this codebase mix both. A plan that says "move `push_reactive.mbt` to `internal/push/`" is ambiguous without the split; stating it as a move leads to deleting public handle code by accident.
3. **MoonBit's `pub` is read-only across packages.** Any plan that moves a struct and has other packages write to its fields must use `pub(all)`, not `pub`. This is distinct from Rust/Go `pub` semantics.
4. **Foreign-type methods in MoonBit can be added as local extensions only when private.** A public method must live in the type's home package. This constrains how error types with `Runtime`-aware rendering can be relocated.
5. **Three rounds of Codex review were necessary here** — round 1 caught partition-graph errors (cycles); round 2 caught MoonBit-language-rule errors that required reading the language docs (visibility, orphan methods, file-split); round 3 caught self-consistency slip-ups inside the corrections themselves (a contradictory lifecycle-impl placement, a misnamed handle, a boundary script that didn't match the repo's `moon.pkg` comment style). For any partition refactor that moves ≥5 types across ≥3 new packages, budget three review rounds and don't conflate the "architecture is correct" and "prose is accurate" questions. Each correction risks introducing its own drift.
6. **Fact-check everything you write into the spec.** The "keep Rule handle" line was a confident invention — there is no `Rule` handle type in this repo. A quick search in the codebase would have caught it before Codex did. Next time: grep for every named entity referenced in the spec text, verify it exists, verify its shape. A spec claim is not licensed by intent; it is licensed by a grep hit.
