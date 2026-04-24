# R1 Stage 2 — Execution Notes

**Date:** 2026-04-24
**Basis:** [R1 plan v3](2026-04-21-r1-engine-package-split.md) Stage 2 checklist + Codex pre-implementation review (2026-04-24)
**Purpose:** Fold Codex's seven corrections into a concrete Stage 2 spec. The plan's Stage 2 section stays authoritative for intent; this doc supersedes it for **mechanics** where they differ.

## Verdict from Codex pre-review

**IMPLEMENT WITH CHANGES.** Trait shape and boundary intent are correct; mechanical specifics need adjustment.

## Corrections folded in

### 1. SlotSnapshot impl — closure-field access syntax

In `SlotSnapshot for SlotMeta`, the trait method `push_revised_at_for` name-collides with the existing closure field on SlotMeta. Inside the impl body, use parens:

```moonbit
pub impl SlotSnapshot for SlotMeta with disposed(self) -> Bool {
  self.disposed
}
pub impl SlotSnapshot for SlotMeta with push_revised_at_for(self, cell_id) -> Revision {
  (self.push_revised_at_for)(cell_id)  // parens — not a recursive trait call
}
```

Without the parens, MoonBit reads `self.push_revised_at_for(cell_id)` as a recursive trait-method call and infinite-loops at runtime.

### 2. `slot_snapshots()` is NOT zero-copy — cache a parallel array

Plan v3 said "verify `Array[&SlotSnapshot]` construction does not allocate per call." Codex verified the assumption is wrong: MoonBit's trait-object arrays are built element-wise at insertion, with no array-wide variance coercion. Per-call materialization allocates.

**Resolution:** Runtime gains a cached field `accumulator_snapshots : Array[&SlotSnapshot]` maintained in parallel with `accumulator_slots : Array[SlotMeta]`. Updated wherever `accumulator_slots` is pushed into (only at `Accumulator::new` registration — append-only, same index). `Runtime::slot_snapshots()` returns the cached field directly.

Dispose doesn't remove the snapshot entry (slots keep their index; `disposed: true` propagates through the trait).

### 3. `RuntimeCore` needs a field split — `cell_lifecycle` stays on `Runtime`

`RuntimeCore.cell_lifecycle : Array[&CellLifecycle]` blocks moving RuntimeCore to kernel because `CellLifecycle` is defined in top-level `cells/cell_ops.mbt:52` and its trait signature references `Runtime` directly (dispose semantics — see Stage 4 correction in plan v3).

**Resolution — Option (c) per Codex:** lift `cell_lifecycle` out of `RuntimeCore` onto `Runtime` itself.

```moonbit
// In kernel/state.mbt
pub(all) struct RuntimeCore {
  runtime_id : Int
  revision : RevisionState
  mut next_cell_id : Int
  tracking : TrackingState
  batch : BatchState
  mut on_change : (() -> Unit)?
  cell_index : Array[CellRef]
  cell_ops : Array[&CellOps]
  mut phase : PropagationPhase
  gc_root_counts : @hashmap.HashMap[CellId, Int]
  // NOTE: cell_lifecycle moved out to Runtime.
}

// In cells/runtime.mbt
pub(all) struct Runtime {
  priv core : RuntimeCore
  priv pull : PullState
  priv push : PushState
  priv datalog : DatalogState
  priv cell_lifecycle : Array[&CellLifecycle]  // was on core
  priv accumulator_slots : Array[SlotMeta]
  priv accumulator_snapshots : Array[&SlotSnapshot]  // NEW — cached view
  priv mut next_accumulator_id : Int
  priv accumulator_contributions : @hashmap.HashMap[CellId, @hashset.HashSet[AccumulatorId]]
  ...
}
```

All `self.core.cell_lifecycle` reads in `cells/*.mbt` become `self.cell_lifecycle` — a mechanical sweep.

### 4. `BatchFrame` + `BatchUndo` must move with `BatchState`

Plan v3's Stage 2 checklist names `BatchState` but not `BatchFrame` (defined in `cells/batch.mbt:3-23`) or `BatchUndo` (same file). `BatchState.frames : Array[BatchFrame]` makes them transitive dependencies.

**Resolution:** move `BatchUndo`, `BatchFrame`, `BatchFrame::new`, `BatchFrame::has_undo_for` to `kernel/state.mbt` alongside `BatchState`. Delete from `cells/batch.mbt`; that file retains only the `commit_batch` algorithm (which stays in cells/ until Stage 4 per plan).

### 5. `phase_wbtest.mbt` moves with `PropagationPhase`

Plan v3 Stage 2 names only `cells/soa_wbtest.mbt` → `kernel/soa_wbtest.mbt`. But `phase_wbtest.mbt` tests `PropagationPhase` + `enter_phase`/`leave_phase` — it also moves.

### 6. Add `moonbitlang/core/debug` to kernel imports

`Show for PropagationPhase` uses `@debug.to_string` (`cells/runtime.mbt:57-59`). kernel/moon.pkg must import it.

### 7. Additional `Ref[Int]` call sites beyond the plan's list

Plan mentioned memo's forgiving-repair path (`cells/memo.mbt:222`). Codex also found writes at `cells/tracking.mbt:93, 115, 184, 220` and a clear at `cells/runtime.mbt:797` (`gc()`). All must be migrated to use the new kernel getters/setters.

## Updated Stage 2 checklist (supersedes plan v3 § Stage 2)

### Kernel side — new code

1. Create `cells/internal/kernel/state.mbt` containing:
   - `RevisionState`, `TrackingState`, `BatchState`, `BatchUndo`, `BatchFrame` + methods, `PullState`, `PushState`, `DatalogState`, `PropagationPhase` + `Show` impl, `ActiveQuery` + methods, `RuntimeCore` (without `cell_lifecycle`).
   - File-scope `Ref[Int]`s: `next_runtime_id` (init 0), `current_computing_runtime_id` (init -1).
   - Getter/setter/alloc helpers: `get_current_computing_runtime_id() -> Int`, `set_current_computing_runtime_id(Int)`, `alloc_runtime_id() -> Int`.
   - `enter_phase(core : RuntimeCore, next : PropagationPhase)` and `leave_phase(core : RuntimeCore)` as free functions taking `RuntimeCore` explicitly.
   - All types `pub(all)`.
2. Update `cells/internal/kernel/moon.pkg` imports: `types`, `internal/shared`, `internal/pull`, `internal/push`, `internal/datalog`, `moonbitlang/core/hashmap`, `moonbitlang/core/hashset`, `moonbitlang/core/debug`. **NOT `priority_queue` yet** — that's Stage 3.
3. Delete `cells/internal/kernel/kernel.mbt` (the placeholder).

### Shared side — trait

4. Add `cells/internal/shared/slot_snapshot.mbt` with:
   ```moonbit
   pub trait SlotSnapshot {
     disposed(Self) -> Bool
     push_revised_at_for(Self, @incr_types.CellId) -> @incr_types.Revision
   }
   ```

### Cells side — adjustments

5. Remove state struct definitions from `cells/runtime.mbt`; replace with `@kernel.*` references.
6. Remove `ActiveQuery` from `cells/tracking.mbt`; replace with `@kernel.ActiveQuery`.
7. Remove `BatchUndo`, `BatchFrame`, `BatchFrame::new`, `BatchFrame::has_undo_for` from `cells/batch.mbt`.
8. Remove file-scope `next_runtime_id`, `current_computing_runtime_id` from `cells/runtime.mbt`.
9. Lift `cell_lifecycle : Array[&CellLifecycle]` from `RuntimeCore` onto `Runtime`. Sweep `cells/*.mbt` call-sites: `self.core.cell_lifecycle.*` → `self.cell_lifecycle.*`.
10. Add `accumulator_snapshots : Array[&SlotSnapshot]` field to `Runtime`. Initialise in `Runtime::new`. Push alongside `accumulator_slots` in `register_accumulator_slot()` (or wherever SlotMeta is appended — find via grep on `accumulator_slots.push`).
11. Add `pub fn Runtime::slot_snapshots(self) -> Array[&SlotSnapshot] { self.accumulator_snapshots }`.
12. Add `pub impl SlotSnapshot for SlotMeta` impls in `cells/accumulator.mbt` (with the parens-wrap on the closure call per §1 above).
13. Remove `warnings = "-1-7-29"` → restore to `"-1-7"` in `cells/moon.pkg` (the `@kernel` import is now actually used).
14. Replace `current_computing_runtime_id.val` reads/writes in `cells/memo.mbt:222`, `cells/tracking.mbt:93,115,184,220`, `cells/runtime.mbt:797` with `@kernel.get_current_computing_runtime_id()` / `@kernel.set_current_computing_runtime_id(...)`.
15. Replace `next_runtime_id.val` writes in `Runtime::new` with `@kernel.alloc_runtime_id()`.

### Test migration

16. Move `cells/soa_wbtest.mbt` → `cells/internal/kernel/soa_wbtest.mbt`. Adjust imports.
17. Move `cells/phase_wbtest.mbt` → `cells/internal/kernel/phase_wbtest.mbt`. Adjust imports.
18. Re-run both under kernel package; fix visibility issues if any (`pub(all)` on moved types should cover them).

### Doc updates

19. Update `CLAUDE.md` package map: kernel description changes from "R1 skeleton — empty; Stage 2 moves state sub-structs in, Stage 3 moves algorithms" to "state sub-structs + phase machine; Stage 3 moves algorithms." List what kernel/state.mbt contains.
20. Update `docs/design/internals.md:504-506`: adjust the kernel paragraph from "in progress" to reflect Stage 2 content.

## Verification gate

Acceptance criteria (required for Stage 2 to land):

- `moon check && moon test`: all tests green, zero warnings.
- `moon info && moon fmt`: no `.mbti` diff except additive kernel surface + new `SlotSnapshot` trait + removed `-29` comment on cells/moon.pkg.
- `moon bench --release -p dowdiness/incr/tests -f bench_test.mbt` + `-p dowdiness/incr/cells -f push_efficiency_bench_test.mbt` on wasm-gc — every tracked-path row stays within noise (≈±2%) of [pre-R1 baseline](../performance/2026-04-21-pre-r1-baseline.md). Stage 2 is a pure file move; no algorithmic change.
- `scripts/check-engine-isolation.sh`: OK. (Script doesn't yet enforce kernel's direction — Stage 5.)

Observed on the landed PR (#46, commit efdea11 + fixups):

- `moon test`: 559/559 (baseline 556 + 3 new wbtests pinning SlotSnapshot trait dispatch, the cache alignment invariant, and multi-registration invariant).
- Benchmarks: two rows drifted 1–2% within σ of baseline (`memo: wide fanout`, `hybrid: get stale`); rest flat. No row outside measurement noise.

## Out of scope for Stage 2 (explicit)

- `CellLifecycle` trait retype to take `RuntimeCore` instead of `Runtime` — kept deferred; Stage 4 keeps `dispose_cell` coordinator in `cells/runtime.mbt`.
- Any algorithm moves (verify, push_propagate, fixpoint, propagate, batch commit body). All Stage 3 and later.
- Any public API signature change.
- Any `.mbti` churn beyond the additive kernel surface.
