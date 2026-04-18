# Runtime Modularization Stage 5: Internal Package Split

**Status:** Approved design

**Date:** 2026-04-18

**Prerequisites:**
- Phase 2 PR #36 merged (coordinator routing via `propagate_changes`)
- MoonBit `internal` package feature available (verified on moon 0.1.20260409 — see [Phase 2 design](2026-04-16-runtime-modularization-phase2-design.md))

**Supersedes:** PR 2 section of [`2026-04-16-runtime-modularization-phase2-design.md`](2026-04-16-runtime-modularization-phase2-design.md). That section's partition table contained three cycle-creating mistakes (`CellLifecycle` in shared, `MemoData` moving with `CycleError` in cells, `PushEntry` moving while `CellRef` stays in cells). Codex review on 2026-04-18 caught all three. This spec is the corrected design.

---

## Goal

Complete the Runtime god-object decomposition by partitioning the `cells/` package into a thin coordinator plus four engine sub-packages under `cells/internal/`. Establish compile-time and lint-time boundaries that prevent engines from coupling to each other and prevent external consumers from reaching engine internals.

**Hard constraints:**
- Zero public API change (`pkg.generated.mbti` for `incr/` and `incr/tests/` byte-identical before/after)
- Zero algorithm change (all of `verify.mbt`, `push_propagate.mbt`, `batch.mbt`, `datalog_fixpoint.mbt` stay in `cells/` unchanged)
- Zero handle relocation (`Signal[T]`, `Memo[T]`, `HybridMemo[T]`, `TrackedCell[T]` all stay in `cells/`)
- All 506 existing tests pass after every commit

---

## Architecture

### Target package graph

```
types/                           (pure values: CellId, Revision, Durability)
  ↑
cells/internal/shared/           (traits + shared types, pub(open) for traits)
  ↑           ↑           ↑
internal/pull/  internal/push/  internal/datalog/   (engine SoA + pure trait impls)
  ↑           ↑           ↑
cells/                           (coordinator: Runtime, handles, algorithms,
                                  CellLifecycle trait + impls, all tests)
```

**No back-edges:** internal packages never import `dowdiness/incr/cells`.

**No cross-engine imports:** `internal/pull/` does not import `internal/push/` or `internal/datalog/`, and symmetrically for the other two.

**MoonBit `internal` semantics** (verified — see Phase 2 spec):
- Parent `cells/` can import `cells/internal/<child>/`. Allowed.
- External packages importing `cells/internal/<child>/` produce a compile error.
- Internal siblings can import each other — *not* blocked by `internal`. Must be enforced externally (see [Boundary verification](#boundary-verification)).
- Cross-package trait impls require `pub(open)` traits.
- Explicit `impl Trait for Type` is required even when defaults exist.

### Partition

| Destination                  | Symbols                                                                                                                                                                                  | Notes |
|------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------|
| `cells/internal/shared/`     | Traits: `CellOps`, `Committable`, `HasCellMeta`. Types: `CellMeta`, `CellRef`, `CycleError` (data + pure methods: `cell()`, `path()`, `from_path()`).                                    | Imports `types/` (which already owns `GcRole`) and `moonbitlang/core/hashset` (CellMeta carries `subscribers : HashSet[CellId]`). |
| `cells/internal/pull/`       | `PullSignalData`, `MemoData` + `CellOps`/`HasCellMeta`/`Committable` impls for `PullSignalData` and `MemoData`.                                                                          | SoA fields `pub` within package (parent `cells/` reads them in runtime/verify/introspection/wbtests). `PullVerifyFrame` stays in `cells/verify.mbt` (algorithm-local). |
| `cells/internal/push/`       | `PushReactiveData`, `PushEffectData`. `CellOps`/`HasCellMeta` impls.                                                                                                                     | SoA fields `pub` within package. |
| `cells/internal/datalog/`    | `RelationData`, `FunctionalRelationData`, `RuleData`. `CellOps`/`HasCellMeta` impls.                                                                                                     | SoA fields `pub` within package. |
| **Stays in `cells/`**        | `Runtime`, `RuntimeCore`, `RevisionState`, `TrackingState`, `BatchState`, `PullState`, `PushState`, `DatalogState`, `PropagationPhase`, `ActiveQuery`. **`CellLifecycle` trait + all engine impls** (extracted to `cells/{pull,push,datalog}_lifecycle.mbt`). **`PushEntry`** (algorithm-local, references `CellRef`). **`CycleError::format_path`** (uses `Runtime`). All handles (`Signal`, `Memo`, `HybridMemo`, `TrackedCell`, `Relation`, `FunctionalRelation`, `Reactive`, `Effect`, `Rule`). All algorithms (`verify.mbt`, `push_propagate.mbt`, `batch.mbt`, `datalog_fixpoint.mbt`, `tracking.mbt`, `runtime.mbt`, `scope.mbt`, `memo_map.mbt`, `introspection.mbt`). All `*_test.mbt` and `*_wbtest.mbt`. | |

### Why `CellLifecycle` does not move

`CellLifecycle` trait methods take `Runtime` (`cells/cell_ops.mbt:213-217`):

```moonbit
priv trait CellLifecycle {
  dispose_cell(Self, Runtime, CellId) -> Unit
  on_observe(Self, Runtime, CellId) -> Unit = _
  on_unobserve(Self, Runtime, CellId) -> Unit = _
}
```

The impls call back into `Runtime` helpers (`rt.remove_subscriber`, `rt.core.cell_index`, `rt.pull.free_memos.push`, etc., e.g. `cells/pull_memo.mbt:43-60`). Moving the trait to `internal/shared/` would force engines to import `Runtime`, creating `cells/ → internal/* → cells/` cycles.

**Resolution:** Trait stays in `cells/`, all impls stay in `cells/` (extracted to dedicated `{pull,push,datalog}_lifecycle.mbt` files for readability). MoonBit's orphan rule permits `impl LocalTrait for ForeignType`. The impls reach into `internal/*/` SoA fields via the package-level `pub` exposure described above.

A future stage could refactor `CellLifecycle` into a smaller capability trait that takes a thin `LifecycleCtx` (only the helpers it needs) instead of the full `Runtime`. That refactor is out of scope here — see [Out of scope](#out-of-scope).

### Why `CycleError` splits

`MemoData.compute : () -> Result[Bool, CycleError]` (`cells/pull_memo.mbt:9`) requires `CycleError` to be visible from `internal/pull/`. But `CycleError::format_path` (`cells/cycle.mbt:81`) takes `rt : Runtime` and would create a back-edge.

**Resolution:**
- Move `pub suberror CycleError`, `cell()`, `path()`, `from_path()` to `internal/shared/`.
- Keep `format_path` (and the private `format_cell` helper) in `cells/cycle.mbt`. They become a free function or extension method that imports `CycleError` from `shared/`.
- `cells/cycle.mbt` (or `cells/cell.mbt`) adds `pub using @shared { type CycleError }` so that the root facade's `pub using @internal { type CycleError }` in `incr.mbt` (line 27) continues to resolve. This preserves the public re-export path without a source-level edit in `incr.mbt`.

### Why `PushEntry` does not move

`PushEntry` (`cells/push_propagate.mbt:7`) stores a `CellRef`. `CellRef` could move to `internal/shared/` (it stores indexes, not engine types), but `PushEntry` is purely algorithm-local — used only inside `push_propagate.mbt`'s priority queue. Splitting the algorithm from its work-item type buys nothing and adds an import for one type.

**Resolution:** `PushEntry` and its `Eq`/`Compare` impls stay in `cells/push_propagate.mbt`. `CellRef` moves to `internal/shared/` (so engines can match on `cell_index` entries during their lifecycle impls — verified that none of the engines need this today, but the type is shared-natured and belongs in shared).

### Visibility changes summary

| Symbol                    | Old (in `cells/`) | New                                              | Reason                                                       |
|---------------------------|-------------------|--------------------------------------------------|--------------------------------------------------------------|
| `CellOps`                 | `priv`            | `pub(open)` in `internal/shared/`                | Engine packages implement it from a different package.       |
| `HasCellMeta`             | `priv`            | `pub(open)` in `internal/shared/`                | Same.                                                        |
| `Committable`             | `priv`            | `pub(open)` in `internal/shared/`                | `PullSignalData` (in `internal/pull/`) implements it.        |
| `CellMeta`                | `priv`            | `pub` in `internal/shared/`                      | All engines embed it.                                        |
| `CellRef`                 | `priv`            | `pub` in `internal/shared/`                      | Coordinator + lifecycle impls match on it.                   |
| `CycleError` (data)       | `pub`             | `pub` in `internal/shared/`                      | Re-exported from root facade for users; canonical name moves but root `.mbti` is `pub type` alias and stays stable. |
| Engine SoA structs        | `priv`            | `pub` in their `internal/*/`                     | Coordinator + algorithms + lifecycle impls + wbtests access fields. |
| Engine SoA fields         | (struct-private)  | `pub` within their `internal/*/`                 | Same.                                                        |
| `CellLifecycle`           | `priv`            | `priv` (unchanged) in `cells/`                   | Stays — see above.                                           |

All visibility expansions are bounded by the `internal/` keyword: nothing leaks to external consumers.

---

## Invariants

### Behavioral invariants (preserved by existing 506 tests — the safety net)

These are the contracts users and downstream code rely on. The existing test suite covers each. No new behavioral tests required.

1. **Push propagation is level-sorted.** Higher-level cells never compute before their lower-level inputs in a single propagation wave. Covered by `cells/push_reactive_wbtest.mbt`, `cells/push_reachable_wbtest.mbt`.
2. **Callback snapshot before propagation.** In `commit_batch` and `signal.set_unconditional`, per-cell `on_change` callbacks are snapshotted *before* `propagate_changes` runs. A callback registered or cleared during propagation does not fire (or skip) in the current wave. Covered by `cells/callback_test.mbt` and `cells/batch_wbtest.mbt`.
3. **Phase mutual exclusion.** `PropagationPhase` transitions never overlap (`Idle`/`PushPropagating`/`InFixpoint`/`GarbageCollecting`). Re-entry panics. Covered by `cells/cycle_test.mbt`.
4. **Pull-verify cycle detection returns `CycleError`.** A self-referential or mutually recursive memo returns `Err(CycleDetected(...))`, never aborts. Covered by `cells/cycle_path_test.mbt`, `cells/cycle_test.mbt`.
5. **Dispose/GC reference-count semantics.** `add_gc_root`/`remove_gc_root` increments/decrements counts; `on_unobserve` fires only on `1→0` transitions. Covered by `cells/gc_test.mbt`, `cells/dispose_test.mbt`, `cells/observer_test.mbt`.
6. **Batch rollback preserves revision integrity.** A raised exception inside `Runtime::batch` rolls back pending writes; revision counter does not regress. Covered by `cells/batch_wbtest.mbt`, `tests/integration_test.mbt`.

### Structural invariants (new — verified by added boundary checks)

1. **Engine packages are pairwise-disjoint.** `cells/internal/pull/moon.pkg` does not import `cells/internal/push/` or `cells/internal/datalog/`. Symmetric for the other two engines.
2. **No back-edges.** No `cells/internal/*/moon.pkg` imports `dowdiness/incr/cells`.
3. **External-import guard.** External consumers cannot import `cells/internal/*` (MoonBit `internal` enforces; covered by negative compile probe — see [Boundary verification](#boundary-verification)).
4. **`.mbti` stability.** `pkg.generated.mbti` for the root `incr/` package and for `incr/tests/` is byte-identical before vs. after the refactor.

---

## Boundary verification

Three layers, ordered from fastest to most thorough:

### Layer 1: `scripts/check-engine-isolation.sh`

A shell script run in CI and locally before each commit. Asserts invariants 1 and 2.

```bash
#!/bin/bash
set -e
fail=0
engines="pull push datalog"

# Invariant 1: no cross-engine sibling imports
for engine in $engines; do
  pkg="cells/internal/$engine/moon.pkg"
  [ -f "$pkg" ] || { echo "MISSING: $pkg"; fail=1; continue; }
  for other in $engines; do
    [ "$engine" = "$other" ] && continue
    if grep -q "internal/$other" "$pkg"; then
      echo "FAIL: cells/internal/$engine imports cells/internal/$other"
      fail=1
    fi
  done
done

# Invariant 2: no back-edges from internal/* to cells/
for engine in shared $engines; do
  pkg="cells/internal/$engine/moon.pkg"
  [ -f "$pkg" ] || continue
  if grep -E '"dowdiness/incr/cells"|"dowdiness/incr/cells/[^i]' "$pkg"; then
    echo "FAIL: cells/internal/$engine imports cells/ (back-edge)"
    fail=1
  fi
done

exit $fail
```

The regex `"dowdiness/incr/cells/[^i]` allows `cells/internal/...` while blocking other `cells/...` paths. (Brittle; Layer 2 is the safety net.)

### Layer 2: `.mbti` diff check

Run after each commit:

```bash
moon info
git diff --exit-code pkg.generated.mbti tests/pkg.generated.mbti
```

A non-empty diff means a moved type leaked into the public API surface. Investigate and fix before committing.

### Layer 3: Negative compile probe (optional, deferred)

Codex suggested a tiny throwaway package outside `cells/` that imports `dowdiness/incr/cells/internal/pull` and asserts `moon check` rejects it. This validates MoonBit's `internal` enforcement on the *current* moon version (the Phase 2 spec verified it on moon 0.1.20260409, but a build-time probe future-proofs against regressions in moon itself).

**Recommendation:** Add as a follow-up after Stage 5 lands. Not required for Stage 5 acceptance because it tests moon's behavior, not our code.

---

## Execution sequence

Six commits, staged shared-first, each independently green. All commits run inside the worktree at `loom/incr/.worktrees/refactor-incr-structure` on branch `refactor/incr-structure`.

### Commit A: extract `cells/internal/shared/`

**Files added:**
- `cells/internal/shared/moon.pkg` — imports `dowdiness/incr/types`, `moonbitlang/core/hashset`
- `cells/internal/shared/cell_meta.mbt` — `pub struct CellMeta`
- `cells/internal/shared/cell_ref.mbt` — `pub enum CellRef`
- `cells/internal/shared/cell_ops.mbt` — `pub(open) trait CellOps`, `pub(open) trait HasCellMeta`, `pub(open) trait Committable`, default impls (`GcRole` continues to come from `types/`)
- `cells/internal/shared/cycle.mbt` — `pub suberror CycleError`, `cell()`, `path()`, `from_path()`

**Files modified:**
- `cells/cycle.mbt` — keep only `format_path` and `format_cell`; `pub using @shared { type CycleError }` to preserve the root facade's re-export path
- `cells/cell_ops.mbt` — keep only `priv trait CellLifecycle` + its default impls; `using @shared { trait CellOps, trait HasCellMeta, trait Committable, type CellMeta }`
- `cells/cell.mbt` — add `using @shared { type CellRef }` so existing sites referencing `CellRef` unqualified keep compiling
- `cells/cell_ref.mbt` — delete (content moved to `internal/shared/cell_ref.mbt`; unqualified `CellRef` comes via the `cells/cell.mbt` re-export above)
- `cells/moon.pkg` — add `import "dowdiness/incr/cells/internal/shared" @shared`

**Verification:**
- `moon check` passes
- `moon test` passes (506 tests)
- `moon info && moon fmt`
- `git diff pkg.generated.mbti tests/pkg.generated.mbti` empty

**Commit message:**
```
refactor: extract cells/internal/shared trait+type package

Move CellOps, HasCellMeta, Committable, CellMeta, CellRef, GcRole,
and CycleError (data + pure methods) into cells/internal/shared/.
Trait visibility flipped to pub(open); type visibility to pub.
Bounded by MoonBit `internal` — no external visibility change.

CycleError::format_path stays in cells/ because it depends on Runtime.
CellLifecycle stays in cells/ because its method signatures take Runtime.
```

### Commit B: move pull engine to `cells/internal/pull/`

**Files added:**
- `cells/internal/pull/moon.pkg` — imports `types`, `internal/shared`, `moonbitlang/core/hashset`, `moonbitlang/core/hashmap`
- `cells/internal/pull/pull_signal.mbt` — `pub struct PullSignalData` (fields `pub`); `CellOps`, `HasCellMeta`, `Committable` impls
- `cells/internal/pull/pull_memo.mbt` — `pub struct MemoData` (fields `pub`); `CellOps`, `HasCellMeta` impls
- `cells/internal/pull/pull_signal.mbt` and `cells/internal/pull/pull_memo.mbt` are the only new source files. **`PullVerifyFrame` stays in `cells/verify.mbt`** — it is algorithm-local to the iterative verifier, has no external consumer, and follows the same rule that kept `PushEntry` in `cells/push_propagate.mbt`.

**Files added in `cells/`:**
- `cells/pull_lifecycle.mbt` — `impl CellLifecycle for PullSignalData`, `impl CellLifecycle for MemoData`. Imports types from `internal/pull`.

**Files modified:**
- `cells/pull_signal.mbt` — delete (content moved)
- `cells/pull_memo.mbt` — keep only the lifecycle impl (now in pull_lifecycle.mbt) — actually delete
- `cells/runtime.mbt`, `cells/verify.mbt`, `cells/batch.mbt`, `cells/signal.mbt`, `cells/memo.mbt`, `cells/hybrid_memo.mbt`, `cells/introspection.mbt` — update imports
- `cells/moon.pkg` — add `import "dowdiness/incr/cells/internal/pull" @pull`
- `cells/*_wbtest.mbt` files that touch pull SoA — update imports (fields are now `pub` in `internal/pull`, parent `cells/` can read)

**Verification:** same as Commit A.

**Commit message:**
```
refactor: move pull engine to cells/internal/pull

PullSignalData and MemoData moved to internal/pull with public
field visibility (within the package). CellOps, HasCellMeta, and
Committable impls move with their types. PullVerifyFrame stays in
cells/verify.mbt (algorithm-local). CellLifecycle impls stay in
cells/pull_lifecycle.mbt because they call back into Runtime helpers.

Algorithm code (verify.mbt, batch.mbt) and handles (Signal, Memo,
HybridMemo) unchanged in behavior — only imports updated.
```

### Commit C: move push engine to `cells/internal/push/`

**Files added:**
- `cells/internal/push/moon.pkg` — imports `types`, `internal/shared`, `moonbitlang/core/hashset`
- `cells/internal/push/push_reactive.mbt` — `pub struct PushReactiveData`; `CellOps`, `HasCellMeta` impls
- `cells/internal/push/push_effect.mbt` — `pub struct PushEffectData`; `CellOps`, `HasCellMeta` impls

**Files added in `cells/`:**
- `cells/push_lifecycle.mbt` — `impl CellLifecycle for PushReactiveData`, `impl CellLifecycle for PushEffectData`

**Files modified:**
- `cells/push_reactive.mbt`, `cells/push_effect.mbt` — delete (content moved)
- `cells/push_propagate.mbt` — keep `PushEntry` here; update imports
- `cells/runtime.mbt`, `cells/introspection.mbt`, `cells/scope.mbt` — update imports
- `cells/moon.pkg` — add `import "dowdiness/incr/cells/internal/push" @push`
- `cells/*_wbtest.mbt` for push — update imports

**Verification:** same.

**Commit message:**
```
refactor: move push engine to cells/internal/push

PushReactiveData, PushEffectData moved to internal/push with public
field visibility. PushEntry stays in cells/push_propagate.mbt because
it stores CellRef and is purely algorithm-local. CellLifecycle impls
in cells/push_lifecycle.mbt.
```

### Commit D: move datalog engine to `cells/internal/datalog/`

**Files added:**
- `cells/internal/datalog/moon.pkg` — imports `types`, `internal/shared`, `moonbitlang/core/hashset`
- `cells/internal/datalog/relation.mbt` — `pub struct RelationData`
- `cells/internal/datalog/functional_relation.mbt` — `pub struct FunctionalRelationData`
- `cells/internal/datalog/rule.mbt` — `pub struct RuleData`
- Trait impls (`CellOps`, `HasCellMeta`)

**Files added in `cells/`:**
- `cells/datalog_lifecycle.mbt` — `impl CellLifecycle for RelationData`, `impl CellLifecycle for FunctionalRelationData`, `impl CellLifecycle for RuleData`

**Files modified:**
- `cells/datalog_relation.mbt`, `cells/datalog_functional_relation.mbt`, `cells/datalog_rule.mbt` — delete
- `cells/datalog_fixpoint.mbt` — update imports
- `cells/runtime.mbt`, `cells/introspection.mbt` — update imports
- `cells/moon.pkg` — add `import "dowdiness/incr/cells/internal/datalog" @datalog`
- `cells/*_wbtest.mbt` for datalog — update imports

**Verification:** same.

**Commit message:**
```
refactor: move datalog engine to cells/internal/datalog

RelationData, FunctionalRelationData, RuleData moved to
internal/datalog with public field visibility. CellLifecycle
impls in cells/datalog_lifecycle.mbt. Datalog fixpoint algorithm
stays in cells/datalog_fixpoint.mbt.
```

### Commit E: add boundary checks

**Files added:**
- `scripts/check-engine-isolation.sh` (content above)
- Make executable: `chmod +x scripts/check-engine-isolation.sh`

**Verification:**
- Run the script — must exit 0.
- Manually corrupt one engine's `moon.pkg` to import another, run the script, confirm exit 1, revert.

**Commit message:**
```
test: add engine-isolation + back-edge boundary checks

Shell script asserts no cross-engine sibling imports and no
back-edges from cells/internal/* to cells/. Run in CI and locally
before each commit affecting moon.pkg files.
```

### Commit F: documentation

**Files modified:**
- `CLAUDE.md` — replace the package map's `cells/` section with the new `cells/` + `cells/internal/{shared,pull,push,datalog}/` layout. Note that handles, algorithms, and tests stay in `cells/`.
- `docs/todo.md` — check off both items under "Runtime Modularization (Phase 4 — Remaining)":
  - `[x] Internal package split — Move engine types to cells/internal/{pull,push,datalog}/`
  - `[x] Verify engine packages do not import each other`
- `docs/design.md` — update the Architecture section to reference `cells/internal/` layout. Per project doc rules, architecture docs reference principles only — link to the spec for details.
- `docs/README.md` — link to this spec.

**Verification:**
- `bash check-docs.sh` passes (project's docs hierarchy validator)

**Commit message:**
```
docs: update CLAUDE.md + todo + design.md for internal split

Refresh the package map to reflect cells/internal/{shared,pull,
push,datalog}/ layout. Check off Runtime Modularization Stage 5
items in todo.md. Architecture section in design.md updated to
mention the new boundary; details live in this spec.
```

---

## Risks

### R1: `CellLifecycle` orphan-rule confusion (low)
**Risk:** `impl CellLifecycle for PullSignalData` placed in `cells/` while `PullSignalData` lives in `internal/pull/` could be misread as an orphan-rule violation.
**Mitigation:** MoonBit's rule is "*at least one* of (trait, type) must be local." The trait is local to `cells/`; the impl is in the trait's home crate. This is permitted and used elsewhere in MoonBit core. Caught immediately by `moon check` if wrong.

### R2: SoA field visibility audit miss (medium)
**Risk:** A field accessed by `cells/runtime.mbt` or `cells/introspection.mbt` is left struct-private during the move; `moon check` errors.
**Mitigation:** Per-commit `moon check` is the safety net. Fix-forward by flipping the field to `pub`. Acceptable cost. The exposure is bounded by `internal/` so no public API impact.

### R3: `CycleError` canonical-name leakage in `.mbti` (medium)
**Risk:** `CycleError` is re-exported from the root facade. After moving the type to `internal/shared/`, the root `pkg.generated.mbti` may show `@incr_internal_shared.CycleError` instead of `@incr_cells.CycleError` in re-export lines, which is a public API change even if functionally equivalent.
**Mitigation:** Root facade uses `pub type` transparent aliases (per `incr.mbt` convention). Verify by diffing `pkg.generated.mbti` after Commit A. If a diff appears, restructure the alias chain (re-export through `cells/cycle.mbt` instead of directly). Caught at Commit A — earliest possible point.

### R4: Whitebox tests breaking on field renames or move (medium)
**Risk:** Several whitebox tests (`cells/cell_ref_wbtest.mbt`, `cells/verify_wbtest.mbt`, `cells/memo_map_wbtest.mbt`, `cells/batch_wbtest.mbt`, `cells/push_reactive_wbtest.mbt`, `cells/datalog_wbtest.mbt`) directly construct or mutate engine SoA fields. They stay in `cells/` and reach into `internal/*/` `pub` fields.
**Mitigation:** Per-commit `moon test` (506 tests). Failures expected to be missing imports or `pub` qualifiers; mechanical to fix.

### R5: Behavioral regression hidden by mechanical-looking edits (medium)
**Risk:** Re-routing through new package boundaries could subtly change initialization order, default trait dispatch, or `pub(open)` impl resolution.
**Mitigation:**
- Existing 506 tests cover the behavioral invariants enumerated above.
- Run `moon bench --release` before Commit A and after Commit F. Compare hot-path numbers; investigate any >5% regression.

### R6: `internal` package feature regression in future moon versions (low)
**Risk:** A future `moon` version changes `internal` semantics, allowing external imports.
**Mitigation:** Layer 3 negative-compile probe (deferred). Until then, the verified moon version (0.1.20260409) is documented in this spec.

---

## Out of scope

- **Removing `incr/pipeline/` package.** Tracked in `docs/todo.md:292-294` ("Pipeline Traits — Deferred"). Out of scope; would belong in a separate small commit.
- **Refactoring `CellLifecycle` to remove the `Runtime` parameter.** Could enable moving the trait into `internal/shared/` and breaking the `cells/` lifecycle bottleneck. Significant design work; defer until a feature actually pushes for it (e.g., parallel computation, persistent caching from Phase 5 roadmap).
- **Splitting handles into per-engine packages** (`Signal` → `internal/pull/`, etc.). Would force users to import multiple internal packages. Handles stay in `cells/` as the unified user-facing surface.
- **Splitting algorithms** (`verify.mbt`, `push_propagate.mbt`, `batch.mbt`, `datalog_fixpoint.mbt`) into engine packages. Algorithms cross engine boundaries (verify reads pull data, push_propagate reads push data, but both go through the dispatch trait `CellOps` which lives in shared). Splitting would require duplicating dispatch glue. Defer.
- **Removing the `pkg.generated.mbti` byte-stability requirement** in favor of semantic-equivalence checking. The project's CI relies on byte-stability; loosening would require new tooling.

---

## Lessons captured

This spec exists because the prior Phase 2 PR 2 partition table was "validated" in design.md and memory but never actually compiled. Codex review on 2026-04-18 caught three cycle-creating mistakes that reading-only review missed (`CellLifecycle` referencing `Runtime`; `MemoData.compute` referencing `CycleError`; `PushEntry` referencing `CellRef`).

**Lesson:** "Validated" architecture-doc partition tables that haven't been tried against the compiler are not validated. For any future partition refactor, the design step must include either (a) a throwaway compile probe of the partition, or (b) explicit grep-based audits of trait method signatures and struct field types against the proposed package boundaries. This spec includes the audits inline; add the probe (R6 mitigation) when the boundary check infrastructure lands.
