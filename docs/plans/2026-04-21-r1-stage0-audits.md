# R1 Stage 0 — Audit Findings

**Date:** 2026-04-24
**Basis:** [R1 plan](2026-04-21-r1-engine-package-split.md) Stage 0 checklist items 3–5
**Purpose:** Verify the coupling assumptions that Stage 2 (SlotSnapshot trait) and Stage 4 (`dispose_cell` coordinator) depend on. Any surprise here would reshape Stage 2 or 4.

## 1. `dispose_cell` flow — accumulator coupling location

**Claim to verify (plan Stage 0):** `Runtime::dispose_cell` itself does not touch `accumulator_*` fields. Cleanup lives in `pull_memo_lifecycle.mbt` via `CellLifecycle` dispatch.

### Current call chain

`cells/runtime.mbt:739-749` — `Runtime::dispose_cell`:

```
validate runtime ownership
guard against double-dispose
call guard_dispose (hook for cell-specific pre-dispose checks)
remove gc_root_counts[cell_id]           ← touches core state only
dispatch: cell_lifecycle[cell_id.id].dispose_cell(self, cell_id)
```

No reference to `accumulator_slots`, `accumulator_contributions`, or `next_accumulator_id` in the coordinator body.

### Where accumulator cleanup actually lives

`cells/pull_memo_lifecycle.mbt:8-41` (`MemoData::dispose_cell`):

- Iterates `rt.accumulator_contributions.get(cell_id)` → for each slot, calls `(slot.dispose_memo)(cell_id)` if slot not disposed.
- `rt.accumulator_contributions.remove(cell_id)`
- `self.accumulator_reads.clear()` (on the MemoData itself)

This is the only cell-kind lifecycle impl that references accumulator fields. `pull_lifecycle.mbt`, `push_lifecycle.mbt`, `datalog_lifecycle.mbt` do not.

### Conclusion

**Plan claim verified.** The Stage 4 move of `dispose_cell` coordinator to `kernel/dispose.mbt` as `dispose_cell(core, cell_id, cell_lifecycle : Array[&CellLifecycle])` works exactly as specified — the kernel coordinator never sees accumulator state. Per-kind `CellLifecycle` impls stay in `cells/*_lifecycle.mbt` and continue to read Runtime's accumulator fields directly.

**No new coupling discovered.** Two Stage 4 follow-ups that Codex review (2026-04-24) resolved:

1. **`guard_dispose` is pure coordinator** over `phase` + `tracking.stack` (`cells/runtime.mbt:713`). Moves to `kernel/dispose.mbt` as `check_dispose_guard(core)`.
2. **The real Stage 4 blocker is the `CellLifecycle(Runtime, ...)` signature**, not accumulator cleanup. `CellLifecycle::dispose_cell(self, rt : Runtime, cell_id)` lives in `cells/cell_ops.mbt:52` and takes a full `Runtime`; impls in `cells/*_lifecycle.mbt` read runtime helpers directly. Kernel cannot own the coordinator as originally written without retyping the trait across 4 lifecycle files. **Resolution adopted in plan v3 (2026-04-24):** dispose coordinator stays in `cells/runtime.mbt`; only pure-state bits (`validate_cell_for_dispose`, `drop_gc_root`, `check_dispose_guard`) move to kernel. Trait retype is deferred — revisit in a future R-track if needed.

## 2. `ActiveQuery` field set — accumulator types

**Claim to verify (plan Stage 0):** `touched_accumulator_slots : HashSet[AccumulatorId]` is the only accumulator-typed field on `ActiveQuery`. `AccumulatorId` lives in `types/` so kernel can carry it opaquely.

### ActiveQuery fields (from `cells/tracking.mbt:10-27`)

```
priv struct ActiveQuery {
  cell_id : CellId
  dependencies : Array[CellId]
  seen : @hashset.HashSet[CellId]
  accumulator_reads : @hashmap.HashMap[
    (@incr_types.AccumulatorId, CellId),
    @incr_types.Revision,
  ]
  touched_accumulator_slots : @hashset.HashSet[@incr_types.AccumulatorId]
}
```

### Audit result

**The plan undercounts.** Two accumulator-typed fields, not one:

1. `accumulator_reads : HashMap[(AccumulatorId, CellId), Revision]` — synthetic reads staged during compute; keyed on `(slot, producer_memo)` pairs.
2. `touched_accumulator_slots : HashSet[AccumulatorId]` — slots this frame pushed to.

Both use `@incr_types.AccumulatorId` (defined at `types/accumulator_id.mbt:9`), which is `pub(all)` with `Hash`, `Eq`, and `Show` impls already in `types/`. Kernel can carry both fields opaquely without importing `cells/accumulator.mbt`.

### Consequence for Stage 2

Plan task "Move to `kernel/state.mbt`: … `ActiveQuery`" is fine as written — both fields type-check inside kernel because `AccumulatorId` and `Revision` live in `types/`. No additional trait or re-export needed.

### Drive-by observations

- `@incr_types.CellId` in `accumulator_reads`' key tuple also lives in `types/`. No issue.
- `accumulator_reads` is consumed by memo commit (`memo_snapshot_accumulator_contributions` / `memo_commit_accumulator_phase` per earlier memory). Those code paths stay in `cells/memo.mbt` per D4; they read the field on the ActiveQuery that kernel pops — this is fine because kernel's `pop_tracking_full` returns the ActiveQuery struct and pub(all) field access works across packages.

**Plan text to update:** Stage 0 bullet should read *"Confirm `touched_accumulator_slots` and `accumulator_reads` are the only accumulator-typed fields on ActiveQuery; both use `AccumulatorId` / `Revision` from `types/`."* — same conclusion, more accurate framing.

## 3. `check-engine-isolation.sh` extensibility — allow-list diff plan

**Claim to verify (plan Stage 0):** the script can be extended to enforce "`kernel/` may import `pull/`, `push/`, `datalog/`, `shared/`; nothing may import `kernel/` except `cells/` (top-level)."

### Current script structure (`scripts/check-engine-isolation.sh`)

Three invariants enforced today:

1. **Cross-engine sibling isolation** — none of `{pull, push, datalog}` imports any other.
2. **`internal/shared` is a leaf** — it imports no engine siblings.
3. **No back-edges** — no `cells/internal/*` imports anything under `cells/` that isn't under `cells/internal/`.

All three iterate over a fixed `engines=(pull push datalog)` array. Import extraction (`extract_imports`) is robust — strips `//` and `#` comments, quotes, and the `"test"` discriminator, wrapped in `{ ... } || true` to survive `pipefail` + empty match.

### Stage 5 diff plan (exact)

The plan says Stage 5 updates this script. Specifying the exact changes now so Stage 5 doesn't re-derive them.

**Change 1 — add kernel to the isolation universe, but as a one-way importer.**

Today `engines=(pull push datalog)` is used for both sibling-isolation (invariant 1) and back-edge check (invariant 3). Kernel needs to appear in invariant 3 (no back-edges to `cells/` top-level) but NOT in invariant 1 (kernel importing pull/push/datalog is allowed).

Cleanest split: introduce a second array.

```bash
engines=(pull push datalog)        # existing — sibling isolation rule applies
internals=(pull push datalog shared kernel)   # all internal packages — back-edge rule applies
```

Replace `for engine in shared "${engines[@]}"` (invariant 3) with `for engine in "${internals[@]}"`.

**Change 2 — assert kernel imports are allowed only in `cells/*.mbt` (top level), not siblings.**

New invariant 4:

```bash
# Invariant 4: only cells/*.mbt (top-level) may import kernel.
# Sibling internals importing kernel would create a cycle with invariant 3.
for engine in "${engines[@]}" shared; do
  pkg="cells/internal/$engine/moon.pkg"
  [ -f "$pkg" ] || continue
  imports=$(extract_imports "$pkg")
  if echo "$imports" | grep -Fxq 'dowdiness/incr/cells/internal/kernel'; then
    echo "FAIL: cells/internal/$engine imports cells/internal/kernel (must be cells/*.mbt only)"
    fail=1
  fi
done
```

This catches the scenario in D6: pull/push/datalog must not import kernel (would create a cycle). Shared must also not import kernel (shared is the leaf under invariant 2).

**Change 3 — assert kernel can import pull/push/datalog/shared, but nothing else under cells/.**

Kernel's own moon.pkg is subject to invariant 3 via the `internals` array extension — no back-edges to `cells/` top-level. That's sufficient; no additional rule needed.

### Residual question

Invariant 2 today reads: *"internal/shared is a leaf — no engine imports."* With kernel added, the statement generalizes to: *"shared imports no other internal packages."* Stage 5 should update the comment above invariant 2 even though the code doesn't need to change (shared is still not importing anything).

### Conclusion

**Extension is straightforward.** Three changes, all localized:
1. Add `internals` array; swap invariant 3's loop variable.
2. Add invariant 4 (no sibling imports of kernel).
3. Update invariant 2's comment.

Stage 5 remains a single-PR job.

## Summary — Stage 1 readiness

| Audit | Result | Blocks Stage? |
|---|---|---|
| dispose_cell flow | Plan claim verified. One drive-by flag about `guard_dispose` classification for Stage 4. | No |
| ActiveQuery fields | Plan undercounts (two accumulator-typed fields, not one). Both types live in `types/`. No structural blocker. | No — update plan bullet text only |
| isolation script | Three-change extension plan specified. All three changes are localized. | No |

**Ready for Codex design review** as the final Stage 0 gate.
