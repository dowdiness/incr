# Accumulator API Design (local-only MVP)

**Status:** Complete (shipped 2026-04-20 via [PR #42](https://github.com/dowdiness/incr/pull/42) + fix `1715981`; driver adoption via [loom PR #94](https://github.com/dowdiness/loom/pull/94)). Decision record: [../../decisions/2026-04-20-accumulator-api.md](../../decisions/2026-04-20-accumulator-api.md).

**Original status:** Approved design (Path 1 — local-only; transitive reconsidered post-MVP)

**Date:** 2026-04-19

**Driver:** Lambda type-checker diagnostics (`examples/lambda/src/typecheck/`) — replaces the manually-threaded `TypeResult.diagnostics : Array[TypeDiagnostic]` field + `merge_diagnostics` helper with a side-channel that collects per-memo push values.

**Prerequisites:**
- Boundary 3 type-checker merged (loom#81 + incr#34) — provides the concrete driver
- PR #41 merged (`MemoMap::get_tracked`) — establishes misuse-guardrail pattern for MemoMap
- Runtime Modularization Stage 5 merged — stable internal package boundaries
- Error-model verification complete — see [§Prerequisite Verification: resolved](#prerequisite-verification-resolved).

**Supersedes:** nothing. This is the first accumulator design in `incr/`.

**Open design questions resolved:** All four questions in `docs/todo.md:220-226` are answered in [§Open Questions Resolved](#open-questions-resolved).

## Prerequisite Verification: resolved

Empirical testing (2026-04-19, incr working tree, `moon test`) on the error-model shape:

- **`raise?` polymorphism in struct fields:** **NOT supported.** `struct Cell[T] { compute : () -> T raise? }` fails to compile with error `[4168]: Error polymorphism is not supported here.`
- **Concrete `raise Failure` in struct fields:** **supported.** `struct Cell[T] { compute : () -> T raise Failure }` compiles; non-raising closures (`() => 42`) **auto-promote** to the raising type without caller annotation.
- **Implication for this spec:** adopt the concrete-error-type path. Memo compute closures become `() -> T raise Failure`; existing non-raising `Memo::new(() => ...)` call sites compile unchanged. The B2 (pure-abort) fallback discussed during design is **not needed** — auto-promotion preserves the backwards-compat goal that B1 was designed around.

**Record of record_dependency reuse:** static review of `cells/` confirms that `record_dependency` is called only by handle `.get()` methods (`signal.mbt:96`, `memo.mbt:238`/`:247`/`:255`, `datalog_relation.mbt:128`, `hybrid_memo.mbt:104`/`:112`/`:117`, `push_reactive.mbt:98`) and by `Memo::get_result_inner`. Neither `force_recompute` nor `pull_verify` invokes it directly. `Runtime::ensure_computed_untracked` can therefore reuse those routines without leaking an ordinary dep onto the caller's frame.

This spec now commits to a single linear error model; all references to B1/B2 branches have been removed in this revision.

---

## Goal

Provide an accumulator primitive that lets tracked computations push values (e.g., diagnostics) into a side channel, and lets other memos read those values with correct incremental invalidation — without threading the values through return types.

**Hard constraints:**
- Zero breaking API changes to existing `incr` types
- No generic `Runtime` parameter (preserves non-generic Runtime invariant)
- No new second dep graph; accumulator invalidation reuses existing `changed_at`-style machinery
- `check_cross_runtime` and `CellLifecycle` integration patterns reused — no new lifecycle concepts
- No new `abort` sites in FFI-reachable code (uses `fail` for caller misuse per MoonBit error-handling conventions)

---

## Scope: Local-only MVP (Path 1)

`memo.accumulated(acc)` returns **only** values pushed directly during memo's own compute. No transitive dep-graph walk. Module-level aggregation stays in user code (the lambda driver's `collect_results` pattern — `type_memos.map(m => m.accumulated_peek(diags)).flatten()`).

**Why not transitive (Salsa-style):** During design review, Codex traced the lambda pipeline: `type_memo[i]` transitively depends on `type_memo[i-1]` through `env_memo[i]` (`examples/lambda/src/typecheck/typecheck.mbt:173`). A transitive `accumulated()` on `type_memo[i]` would pick up diagnostics from every earlier def — not just this def's. That contradicts the driver's current per-def semantics. The manual union at module level is the right boundary.

**Transitive reconsidered post-MVP:** if a future driver wants cross-memo transitive semantics (e.g., a layer that genuinely aggregates across sub-queries), we add `accumulated_transitive(acc)` as a separate method. The local-only core from this spec stays unchanged. See [§Deferred Work](#deferred-work).

---

## API Surface

### Types

```moonbit
// types/accumulator_id.mbt — pure value type, opaque monotonic identity
pub struct AccumulatorId {
  id : Int           // monotonic, never reused across dispose/re-create
  runtime_id : Int   // cross-runtime guard

  fn new(id : Int, runtime_id : Int) -> AccumulatorId
} derive(Eq, Hash, Compare, Debug)

// cells/accumulator.mbt
pub struct Accumulator[T] {                       // NO Eq bound on struct
  // internals private — users hold an opaque handle
  // ...
  fn[T : Eq] new(rt~ : Runtime, label? : String) -> Accumulator[T]
}
```

### Factories

```moonbit
// Free-floating
pub fn[T : Eq] Accumulator::new(rt~ : Runtime, label? : String) -> Accumulator[T]

// Scope-owned (auto-disposed on scope dispose)
pub fn[T : Eq] Scope::accumulator(self : Scope, label? : String) -> Accumulator[T]

// Database helper — mirrors create_signal / create_memo
pub fn[T : Eq, Db : Database] create_accumulator(
  db : Db,
  label? : String,
) -> Accumulator[T]
```

Construction syntax: `Accumulator(rt=rt, label="diags")` works via custom constructor (matches `Signal(rt, ...)` / `Memo(rt, ...)` patterns in incr).

### Push (handle method)

```moonbit
pub fn[T] Accumulator::push(self : Accumulator[T], value : T) -> Unit raise Failure
// raises Failure via fail() on: outside tracked frame, non-Memo frame (MVP), disposed accumulator
// aborts (via existing check_cross_runtime helper) on: cross-runtime
// Memo compute closures are typed `() -> T raise Failure`; non-raising user closures
// auto-promote (verified empirically in §Prerequisite Verification: resolved).
```

### Read (Memo methods)

```moonbit
// Tracked read: records synthetic dep on current compute frame
pub fn[T, A] Memo::accumulated(
  self : Memo[T],
  acc : Accumulator[A],
) -> Array[A] raise
// Unified raise channel: may raise CycleError (target in cycle) or Failure
// (disposed accumulator / disposed target — matches Signal::get / Memo::get
// convention: tracked reads of disposed cells are defects).

// Untracked read: no synthetic dep; for outside-runtime consumers (UI, tests)
pub fn[T, A] Memo::accumulated_peek(
  self : Memo[T],
  acc : Accumulator[A],
) -> Array[A]
// no CycleError path (no verify triggered)
// returns [] if accumulator or target memo is disposed — peek is permissive
// by design (matches Signal::peek; outside-runtime callers can safely poll
// post-dispose without guarding)

// Result-style variant for graceful cycle handling (mirrors Memo::get_result)
pub fn[T, A] Memo::accumulated_result(
  self : Memo[T],
  acc : Accumulator[A],
) -> Result[Array[A], CycleError]
// Disposed-target / disposed-accumulator still surface as raise Failure
// (not collapsed into the Result). Result-style is strictly for cycle handling.
```

**Note on `raise` without an explicit error type:** the tracked read may raise **either** `CycleError` or `Failure`. MoonBit widens to the generic `Error` type at that point, losing exhaustiveness matching for callers who want to handle both. That's an accepted trade-off: most callers either propagate (fine either way) or care only about cycles (use `accumulated_result`). If a future caller needs exhaustive matching across both, we add a dedicated sum error type.

### Consequences for `Memo::new`

`Memo::new`'s closure parameter widens from `() -> T` to `() -> T raise Failure`. Empirical verification (see §Prerequisite Verification: resolved) confirms non-raising closures like `() => 42` auto-promote to this type without caller annotation changes. The same widening applies to `Scope::memo`, `create_memo`, and `MemoMap::new`'s compute parameter. `memo_force_recompute` wraps closure invocation in `try/catch` to run the ON_ABORT phase on any raised `Failure` (including accumulator misuse surfaced via `fail`), then re-raises. Existing `Memo::new(() => ...)`, `Scope::memo(fn() { ... })`, etc. call sites compile unchanged. This is documented in [§Data Flow](#data-flow).

### Introspection

```moonbit
pub fn[T] Accumulator::id(self) -> AccumulatorId
pub fn[T] Accumulator::label(self) -> String?
pub fn[T] Accumulator::is_disposed(self) -> Bool
pub fn[T] Accumulator::debug(self) -> String
```

### Lifecycle

```moonbit
pub fn[T] Accumulator::dispose(self) -> Unit  // idempotent
```

Scope-owned accumulators disposed automatically via `Scope.dispose_hooks` (`scope.mbt:79`). See [§Accumulator ownership & Scope integration](#accumulator-ownership--scope-integration) for the mechanism.

### Why no trait

Accumulator is a concrete type. Operations (push, accumulated, diff, dispose) don't vary by implementation. Accumulator **does not implement** `CellOps` or `CellLifecycle` — it is not a `CellId`-indexed runtime cell. Lifecycle integration goes through `Scope.dispose_hooks` for scope ownership and an extension to the existing `MemoData::dispose_cell` hook for per-memo cleanup (see [§Memo disposal](#memo-disposal--extension-to-existing-memo-lifecycle)). Type erasure for runtime-side bookkeeping uses captured closures (matches incr's existing `on_change` / `commit_pending` closure pattern), not trait dispatch.

### Why `T : Eq` only on factories

Push needs no Eq — it just appends. Invalidation diffing (`per_memo[M] != prev_push_sets[M]`) needs Eq, but the diff closure is constructed at `Accumulator::new` with `T : Eq` in scope. The handle itself stores the type-erased diff closure. This matches incr's design principle "constraints only where needed" (`docs/api-design-guidelines.md:29-37`).

---

## Architecture

### Handle-local typed storage

Typed buffers live on the `Accumulator[T]` handle. Runtime stores only slot-id metadata and a reverse index.

```text
Accumulator[T]                              Runtime additions
──────────────                              ─────────────────
  rt : Runtime                               accumulator_slots : Array[SlotMeta]
  slot_id : AccumulatorId                    next_accumulator_id : Int   -- monotonic, NO REUSE
  per_memo : HashMap[CellId, Array[T]]       accumulator_contributions :
  prev_push_sets :                             HashMap[CellId, HashSet[AccumulatorId]]
    HashMap[CellId, Array[T]]             -- reverse index: slots each memo pushed to
  push_revised_at :                       -- populated on successful recompute commit
    HashMap[CellId, Revision]
  label : String?

SlotMeta (in Runtime, indexed by AccumulatorId.id; array grows monotonically)
────────
  label : String?
  mut disposed : Bool
  -- type-erased closures that capture the typed Accumulator[T] handle
  -- (created at Accumulator construction with T : Eq in scope)
  snapshot_and_clear : (CellId) -> Unit             -- phase: BEFORE_CLOSURE
  restore_buffer : (CellId) -> Unit                 -- phase: ON_ABORT
  diff_and_maybe_bump : (CellId, Revision) -> Unit  -- phase: AFTER_CLOSURE;
                                                    -- atomically compares
                                                    -- prev_push_sets[M] vs per_memo[M]
                                                    -- and bumps push_revised_at[M]
                                                    -- to the given Revision if they differ
  dispose_memo : (CellId) -> Unit                   -- phase: memo disposal
  -- type-erased getter for verify-side data access
  push_revised_at_for : (CellId) -> Revision        -- reads handle's push_revised_at[M]

ActiveQuery additions
─────────────────────
  accumulator_reads : HashMap[(AccumulatorId, CellId), Revision]
  touched_accumulator_slots : HashSet[AccumulatorId]
  -- both committed to MemoData's persisted state on success; discarded on failure

MemoData additions (internal/pull/memo_data.mbt — SoA, NOT on Memo[T] handle)
──────────────────────────────────────────────────────────────────────────────
  accumulator_reads : HashMap[(AccumulatorId, CellId), Revision]
  -- "at last recompute, I read slot S's values from target T, saw revision R"
  -- Lives on MemoData because pull_verify sees SoA state, not typed handles
  -- (per cells/internal/pull/memo_data.mbt; handles don't participate in verify)
```

**Key architectural notes:**

1. **Typed storage on handle; type-erased access from runtime.** `Accumulator[T]` owns `per_memo`, `prev_push_sets`, `push_revised_at` with typed `T`. `SlotMeta` exposes these through type-erased closures (getters + mutators). Runtime-side code (`pull_verify`, recompute phases, disposal) dispatches through `SlotMeta` closures without seeing `T`.

2. **Read-side bypass of `SlotMeta`.** `Memo::accumulated` / `accumulated_peek` are called with an `Accumulator[A]` handle in scope, so they read `acc.per_memo[M]` and `acc.push_revised_at[M]` directly from the typed handle. No runtime-side type-erased buffer getter is needed. Only verify-side code (which walks `MemoData.accumulator_reads` without handle access) uses `SlotMeta.push_revised_at_for`.

3. **Persisted `accumulator_reads` on MemoData, not `Memo[T]`.** `pull_verify` operates on SoA state in `cells/internal/pull/memo_data.mbt`. Synthetic-read state must live alongside ordinary-dep state there, or verify can't see it.

4. **`Array[SlotMeta]`, not `Array[Option[SlotMeta]]`.** Monotonic allocation from `next_accumulator_id`. Disposed state lives on the `disposed : Bool` field. No "unallocated slot" state — the array grows only when `new_accumulator` is called.

5. **No second dep graph.** The runtime's existing ordinary-dep graph carries the causality. Accumulator synthetic deps ride alongside, keyed by target memo's `CellId`, compared against per-target `push_revised_at`.

### Additional properties

1. **Monotonic `AccumulatorId`, no reuse.** Fresh `Accumulator::new` gets a fresh id. Stale `accumulator_reads` entries on live memos resolve to "slot disposed → invalidate R" at verify time (fixes slot-aliasing bug identified in Codex review 1).

2. **Synthetic read key is `(AccumulatorId, CellId)`.** Distinct from ordinary deps. A compute frame can read accumulator state from multiple targets without entries colliding.

3. **Transactional staging on `ActiveQuery`.** Synthetic reads and contribution sets live on `ActiveQuery` during compute; committed to persisted state only on success. Discarded on failure. Mirrors the ordinary-dep commit discipline at `cells/memo.mbt:401`.

---

## Data Flow

### Push flow — `acc.push(v)`

```text
1. Guard: rt.tracking_stack empty
      → fail("Accumulator::push called outside a tracked compute")
2. Cross-runtime check via Runtime::check_cross_runtime("Accumulator")
      → aborts on runtime_id mismatch (existing pattern — unchanged)
3. Guard: slot.disposed
      → fail("push to disposed Accumulator")
4. M := top frame's cell_id
5. Guard: top frame cell kind ≠ Memo
      → fail("Accumulator::push only valid inside Memo compute")
6. slot.per_memo[M].push(v)
7. frame.touched_accumulator_slots.insert(slot_id)   -- staged on ActiveQuery
```

Note: `rt.accumulator_contributions` is NOT updated in step 7. It's populated only on successful recompute commit (see AFTER_CLOSURE below).

### Recompute flow — `Memo::force_recompute(M)` — three new phases

**BEFORE_CLOSURE** (runs before the user's closure):
```text
1. prev_contributions := rt.accumulator_contributions[M].copy()   -- CLONE, not alias
2. For each slot_id in prev_contributions:
   slot.snapshot_and_clear(M):
     prev_push_sets[M] := per_memo[M]   -- move ownership to prev
     per_memo[M] := []                  -- fresh array, not clear() on aliased ref
```

**RUN CLOSURE** — user code. Pushes write to `slot.per_memo[M]` and `frame.touched_accumulator_slots`.

**AFTER_CLOSURE (on success):**
```text
1. For each slot_id in (prev_contributions ∪ frame.touched_accumulator_slots):
   slot.finalize_memo(M, rt.current_revision)
   -- type-erased closure atomically does all of:
   --   a. if per_memo[M] != prev_push_sets[M]:
   --        push_revised_at[M] := current_revision
   --   b. prev_push_sets.remove(M)   -- snapshot no longer needed
   --   c. if per_memo[M].is_empty():
   --        per_memo.remove(M)   -- gc empty buffer (stopped-pushing case)
2. Commit frame.accumulator_reads → MemoData(M).accumulator_reads (persisted)
3. Update rt.accumulator_contributions[M] from frame.touched_accumulator_slots
```

The `finalize_memo` closure internally reads `prev_push_sets.get(M).or([])` and `per_memo.get(M).or([])` from the captured handle (with `T : Eq` in scope from construction time) and performs the atomic check-and-bump plus post-recompute cleanup. First-push-to-fresh-memo (missing prev) correctly bumps because `[] != [v, ...]`. Stopped-pushing (missing current) correctly bumps because `[prev, ...] != []` and the empty buffer is garbage-collected.

**ON_ABORT (cycle error or raised user error):**
```text
1. For each slot_id in prev_contributions:
   slot.restore_buffer(M):
     per_memo[M] := prev_push_sets[M]
     prev_push_sets.remove(M)
2. For each slot_id in frame.touched_accumulator_slots but NOT in prev_contributions:
   slot.per_memo.remove(M)   -- clear new-run-only slots (fixes Codex #9)
3. DO NOT commit frame.accumulator_reads
4. DO NOT bump push_revised_at
5. rt.accumulator_contributions[M] unchanged from pre-closure state
```

### Read flow — `memo.accumulated(acc)` (tracked)

```text
1. Cross-runtime check on acc (existing helper, aborts on mismatch)
2. If slot.disposed
      → fail("Memo::accumulated called on disposed Accumulator")
3. If rt.is_cell_disposed(M.cell_id)
      → fail("Memo::accumulated called on disposed target memo")

4. ensure_computed_untracked(M.cell_id)
   -- NEW internal helper (see below). Guarantees M has been computed at
   -- least once and is currently up-to-date, WITHOUT recording M as an
   -- ordinary dep of the reader.
   -- Raises CycleError if M is in a cycle.

5. current_rev := slot.push_revised_at.get(M.cell_id).or(0)
6. If frame R exists:
     frame.accumulator_reads[(slot_id, M.cell_id)] := current_rev   -- staged
7. Return slot.per_memo.get(M.cell_id).or([]).copy()   -- defensive copy
```

**Rationale for abort-on-dispose (tracked path).** `accumulated` participates
in verify; a caller holding a disposed accumulator or querying a disposed
target is a lifetime bug, not a recoverable condition. Matching `Memo::get`
and `Signal::get` (which abort on disposed cells) keeps the tracked-read
surface uniformly strict. The permissive branch lives on `accumulated_peek`,
which is the designated outside-runtime entry point.

### New internal helper: `Runtime::ensure_computed_untracked`

```moonbit
fn Runtime::ensure_computed_untracked(
  self : Runtime,
  cell_id : CellId,
) -> Unit raise CycleError
```

**Semantics:**
1. Pre-check: if `self.is_cell_disposed(cell_id)` → return (caller handles disposed). (The read flow's step 3 handles this before even calling this helper, but the helper is defensive for other call sites.)
2. Look up MemoData for cell_id.
3. If `memo_data.value == None` (never computed): call `memo_force_recompute` directly. Per convention, the caller's `ActiveQuery::record_dependency` is invoked from `Memo::get_result_inner` (`cells/memo.mbt:236`, `:253`) — *not* from `memo_force_recompute` itself. So calling `memo_force_recompute` directly inherently skips the ordinary-dep record.
4. Otherwise: run `pull_verify(cell_id)` walk, forcing recompute if stale. Same principle — `pull_verify` does not call `record_dependency`; only `Memo::get_result_inner` does. So calling `pull_verify` directly skips the record too.

The helper is effectively `Memo::get_result_inner` minus the final `record_dependency` call. "Bypassing the tracking-record path" means we re-use the verify/recompute machinery but do not take the code path that would stage an ordinary dep on the caller's frame — the synthetic-dep recording (step 6 of the read flow) replaces it.

**Implementation sketch:** could be implemented as a local variant of `Memo::get_result_inner` (`cells/memo.mbt:231`) that skips the `record_dependency` call at the end. Plan phase decides between (a) extracting a shared helper or (b) a lightweight duplicate.

**Why needed:** (a) plain `pull_verify` aborts on disposed cells (`cells/verify.mbt:89`), (b) `Memo::get_result_inner` records an ordinary dep (`cells/memo.mbt:236`, `:253`) which would conflate synthetic reads with ordinary deps, (c) neither handles the `value == None` case correctly for accumulator reads — a never-read target at revision 0 would look "fresh" via the durability fast path (`cells/verify.mbt:92`).

### Peek flow — `memo.accumulated_peek(acc)`

Same as tracked read, but:
- **Disposal checks (steps 2-3) return `[]` instead of raising** — peek is the permissive / untracked entry point (matches `Signal::peek` semantics)
- Skip step 4 (`ensure_computed_untracked`) — peek returns whatever is in the buffer without forcing verification
- Skip step 6 (no synthetic dep recording)
- No CycleError path

### Verify flow — integrated into `pull_verify(R)`

```text
Fast-path guards (NEW — BOTH shortcuts must be bypassed):
  If R.memo_data.accumulator_reads is non-empty:
    1. DISABLE the root durability shortcut at cells/verify.mbt:95
       (would short-circuit verification before any dep walk).
    2. DISABLE the nested stale-memo durability shortcut at cells/verify.mbt:148
       (would skip sub-memo verification inside the dep walk).
  Without BOTH disabled, a low-durability accumulator push can still be
  missed: root shortcut could skip the entire verify, or nested shortcut
  could skip a contributor's verify that would have bumped push_revised_at.
  [MVP: bypass both shortcuts entirely when accumulator_reads is non-empty.
   Future optimization: fold target durabilities into R's durability so
   the shortcuts can stay enabled. See Deferred Work.]

(existing) Walk R's ordinary deps; compare each dep.changed_at to R.verified_at.

Synthetic dep check (NEW, after existing dep walk):
  For each (slot_id, target_id) → stored_rev in R.memo_data.accumulator_reads:
    slot := rt.accumulator_slots[slot_id.id]
    if slot.disposed OR rt.is_cell_disposed(target_id):
       invalidate R
       continue
    current_rev := slot.push_revised_at_for(target_id)   -- via closure; default 0
    if current_rev > stored_rev:
       invalidate R
```

### Disposal — `Accumulator::dispose`

```text
1. If already disposed: return (idempotent)
2. For each (M, _) in slot.per_memo:
   rt.accumulator_contributions[M].remove(slot_id)
3. Clear per_memo, prev_push_sets, push_revised_at
4. slot.disposed := true
5. slot_id stays allocated — monotonic, never reused
```

### Memo disposal — extension to existing memo lifecycle

**Mechanism:** extend `cells/pull_memo_lifecycle.mbt::dispose_cell` for `MemoData` (the existing `CellLifecycle` impl), NOT a new `CellLifecycle for AccumulatorSlot` impl. `CellLifecycle` is specifically for `CellId`-indexed runtime cells (`cell_ops.mbt:41`); accumulators aren't cells.

```text
When memo M disposed (inside existing dispose_cell for MemoData):
  -- existing: standard memo cleanup
  -- NEW addition:
  If M in rt.accumulator_contributions:
    For each slot_id in rt.accumulator_contributions[M]:
      slot.dispose_memo(M):
        per_memo.remove(M)
        prev_push_sets.remove(M)
        push_revised_at.remove(M)
    rt.accumulator_contributions.remove(M)
```

Stale `R.memo_data.accumulator_reads` entries referencing disposed M correctly invalidate R at R's next verify — the explicit `is_cell_disposed(target_id)` check in the verify flow handles this (fixes memo-disposal bug identified in Codex review 2).

### Accumulator ownership & Scope integration

**Mechanism:** `Scope.dispose_hooks` (`scope.mbt:79`), NOT `CellLifecycle`. Accumulators are non-cell resources; `Scope` disposes non-cell resources through `dispose_hooks`.

```text
Scope::accumulator[T : Eq](self, label?) -> Accumulator[T]:
  1. acc := Accumulator::new(rt=self.runtime, label=label)
  2. self.dispose_hooks.push(() => acc.dispose())
  3. return acc
```

Scope dispose invokes the hook, which calls `Accumulator::dispose` (idempotent).

### Batch interaction

Pushes during `rt.batch(...)` use post-commit revision (same as signal commits). **No batch-specific rollback closure.** The recompute transaction boundary (ActiveQuery commit/discard) is the correct rollback unit. Batch's signal-rollback system (`cells/batch.mbt:216`) handles raised errors on explicit signal writes, not `abort()` (`cells/batch.mbt:64`), and isn't the right abstraction for per-compute accumulator state.

---

## Error Handling

| Condition | Fault class | Mechanism |
|---|---|---|
| Push outside tracked frame | Defect (user misuse) | `fail("Accumulator::push called outside a tracked compute")` → `raise Failure` |
| Push in non-Memo frame (MVP) | Defect | `fail("Accumulator::push only valid inside Memo compute")` → `raise Failure` |
| Cross-runtime push/read | Defect | Existing `check_cross_runtime` (aborts — pre-existing tech debt, not new) |
| Push to disposed accumulator | Defect | `fail("push to disposed Accumulator")` → `raise Failure` |
| `accumulated` (tracked) on disposed accumulator | Defect | `fail("Memo::accumulated called on disposed Accumulator")` → `raise Failure` |
| `accumulated` (tracked) on disposed target memo | Defect | `fail("Memo::accumulated called on disposed target memo")` → `raise Failure` |
| `accumulated_peek` on disposed accumulator | Not an error | Return `[]` (permissive) |
| `accumulated_peek` on disposed target memo | Not an error | Return `[]` (permissive) |
| Cycle in target's verify | Expected failure | Raises existing `CycleError` |

**Abort discipline:** no new abort sites. Cross-runtime reuses `Runtime::check_cross_runtime` which aborts (pre-existing tech debt, not introduced by this spec). Accumulator-specific caller misuse uses `fail` → `raise Failure`, catchable at FFI boundaries via `try? { ... }` → `Err(Failure(msg))`.

**Value-semantic T requirement (documented, not enforced):**

> `T` must be value-semantic — do not mutate pushed values in place. Structural `Array` equality drives the `finalize_memo` diff check; mutable elements may produce false equality and miss push-set bumps. If `T` contains mutable state, construct new instances for each push.

**Future escape hatch:** `Accumulator::new_always_bump()` — skips diff, bumps on every push. Removes `T : Eq` and value-semantic requirements at the cost of conservative invalidation. Deferred until a driver needs it.

---

## Testing Plan

### Whitebox tests — `cells/accumulator_wbtest.mbt`

| Test | Verifies |
|---|---|
| `accumulator: slot_id monotonic across dispose/new` | No id reuse |
| `accumulator: per_memo buffer cleared on force_recompute start` | BEFORE_CLOSURE move-and-replace |
| `accumulator: prev_push_sets snapshot is a deep copy, not alias` | Clearing per_memo doesn't destroy snapshot |
| `accumulator: push_revised_at bumps only when finalize_memo detects a diff` | Core invalidation mechanic |
| `accumulator: push_revised_at bumps when prior contributor stops pushing` | Empty ≠ prev |
| `accumulator: push_revised_at bumps on first push to fresh memo` | Missing prev defaults to `[]` |
| `accumulator: ActiveQuery.accumulator_reads committed to memo state on success` | Transactional staging — frame's reads become memo's persisted `accumulator_reads` |
| `accumulator: ActiveQuery.accumulator_reads discarded on recompute failure` | ON_ABORT integrity — partial reads from aborted runs don't leak into memo state |
| `accumulator: slots touched only during a failed recompute are cleared on ON_ABORT` | New slot (not in prev_contributions) pushed to during closure, then closure aborts → `per_memo[M]` for that slot must be empty, not left with partial pushes |
| `accumulator: rt.accumulator_contributions[M] cleaned on memo dispose` | CellLifecycle hook |

### Integration tests — `tests/accumulator_test.mbt`

**Basic push/read:**
- Push in memo → `memo.accumulated(acc)` returns values in push order
- `accumulated_peek` returns same values without recording dep
- Multiple memos push to same accumulator, each keyed independently
- `accumulated_result` returns `Ok` on success, `Err(CycleError)` on cycle

**Invalidation model:**
- Same push-set on recompute → reader backdates (caches old result)
- Different push-set on recompute → reader invalidates and recomputes
- **Accumulated-only change**: contributor's return backdates but push-set changes → reader invalidates
- **Durability interaction**: low-durability accumulator push + all-high-durability ordinary deps → reader invalidates (fixes Codex P0.1)
- Contributor stopped pushing → reader sees empty, invalidates

**Error paths (fail-based, testable via `try?`):**
- Push outside tracked context → `Err(Failure(...))`
- Push in non-Memo frame → `Err(Failure(...))`
- Push to disposed accumulator → `Err(Failure(...))`
- `accumulated` (tracked) on disposed accumulator → `Err(Failure(...))`
- `accumulated` (tracked) on disposed target memo → `Err(Failure(...))`
- `panic` tests for cross-runtime push/read (existing `check_cross_runtime` abort)
- Cycle in target's verify: `accumulated` raises CycleError; `accumulated_result` returns `Err`

**Permissive cases (peek only):**
- `accumulated_peek` on disposed accumulator → `[]`
- `accumulated_peek` on disposed target memo → `[]`
- Zero pushes → `[]` (no error)

**Transactional discipline:**
- User closure `fail` mid-recompute → accumulator state restored; next recompute starts from correct snapshot
- Cycle during sub-memo read from within parent's closure → parent's partial accumulator_reads discarded
- Partial push to new slot + error → new-run-only slot cleared

**Lifecycle:**
- `Scope::accumulator` disposed with scope → `accumulated_peek` returns `[]`; `accumulated` raises `Failure`
- Memo dispose clears its entries from all accumulators
- Stale `accumulator_reads` on readers after target dispose → verify correctly invalidates (Codex P1.3)

**Diamond / nested:**
- Reader reads `sub.accumulated(acc)` twice in same compute → single synthetic dep, consistent
- Nested recompute: parent's closure triggers sub.get() which triggers force_recompute(sub); sub's BEFORE_CLOSURE doesn't corrupt parent's accumulator state

**Introspection:** standard `id`, `label`, `is_disposed`, `debug` coverage.

### Driver integration — `examples/lambda/src/typecheck/` (separate PR after MVP lands)

- Replace `TypeResult.diagnostics : Array[TypeDiagnostic]` field with `diags.push(d)` calls inside `infer`/`check`.
- Remove `merge_diagnostics` helper.
- **`def_name` tagging**: current driver adds `def_name` during module aggregation (`typecheck.mbt:269`), and tests assert on tagged messages (`typecheck_test.mbt:440`). Under the accumulator API, push happens inside each def's `type_memo[i]` closure — `def_name` must be threaded into the push site so `TypeDiagnostic { message, def_name }` is constructed correctly at push time. Two options:
  - **(a) Per-def push helper.** The `rebuild_chain` / `update_terms` flow creates a per-def scope that receives `def_name`. Use a closure-wrapping helper: `def_diags_push = d => diags.push({ ..d, def_name: Some(name) })`. Call `def_diags_push` from inside `infer`/`check` via a threaded parameter, OR have `infer`/`check` push untagged diagnostics that are wrapped at the type_memo boundary (requires a transform step at the memo closure's return path — slightly awkward).
  - **(b) Push tagged diagnostics directly.** Thread `def_name : String?` as a parameter through `infer`/`check`. Each push constructs `TypeDiagnostic { message, def_name: current_def_name }` inline.
  - Plan phase picks between (a) and (b). (b) is simpler but touches more call sites.
- Replace `ModuleTypeResult.all_diagnostics` aggregation with `type_memos.map(m => m.accumulated_peek(diags)).flatten()` + `body_memo.accumulated_peek(diags)`.
- **Tests will need edits.** The existing typecheck test suite (`typecheck_test.mbt`) asserts on `TypeResult.diagnostics`. Since that field is removed, tests must migrate to read diagnostics via the accumulator. Behavior should match (same diagnostics, same tagging), but the assertion path changes. Plan the test migration as part of this PR; "existing tests pass unchanged" is NOT a claim this spec makes anymore.
- Incremental scenario: edit one def's body → only that `type_memo[i]` recomputes, only that def's diagnostics change in aggregation.

### Out of scope for initial PR

- Benchmarks — no microbenchmark until a second driver or measurable concern exists (per CLAUDE.md incr-specific performance rule)
- Property tests via `@qc` — deferred until drivers validate the shape
- Proof verification — none of the new code uses `proof_ensure`

### Target test density

~25-30 new tests across whitebox + integration, plus driver-migration PR.

---

## Open Questions Resolved

From `docs/todo.md:220-226`:

**1. Type erasure (Runtime is not generic).** Resolved by **handle-local typed storage**. `Accumulator[T]` owns typed `per_memo: HashMap[CellId, Array[T]]`. Runtime stores `Array[SlotMeta]` with type-erased closures (getters + mutators); never sees `T`.

**2. Transitive collection from sub-calls.** **Not solved in MVP** — Path 1 is local-only. Transitive is the wrong default for the lambda driver (env-chain causes over-collection per Codex review 1). Reconsider post-MVP; see Deferred Work.

**3. Array[T] equality backdating; insertion order stability.** Resolved by **structural `Array` Eq over `T : Eq`** at end-of-recompute. Push order within a compute is stable (`Array.push` is append). `T : Eq` bound on factories only. Documented value-semantic requirement for mutable `T`.

**4. Invalidation when only accumulated values change.** Resolved by **per-memo `push_revised_at : Revision`** bumped inside `finalize_memo(M, rev)` at end-of-recompute when the diff between `prev_push_sets[M]` and `per_memo[M]` is non-empty. Reader records `(slot_id, target_cell_id) → stored_rev` on its `accumulator_reads`; verify compares stored vs current. Durability shortcut disabled for memos with accumulator reads (MVP) — future optimization folds target durabilities into reader durability.

---

## Deferred Work

- **Transitive variant `accumulated_transitive(acc)`** — reconsider when a driver genuinely wants cross-memo transitive semantics. Additive (does not change local-only MVP). Likely implementation: dep-graph walk + target-side synthetic epochs (per Codex review 1 recommendation 2).
- **`Accumulator::new_always_bump()`** — conservative-invalidation variant for non-Eq / mutable T. Add on demand.
- **`HybridMemo::accumulated(acc)`** — straightforward extension; duplicate the method when a driver wants it.
- **Push from `Reactive` / `Effect` contexts** — currently aborts. Revisit if a push-mode driver appears.
- **Durability folding into reader** — replace "disable shortcut" MVP with durability propagation from targets into reader's effective durability.
- **Multi-key bucketing** — if a future `KeyedMemo[K, V]` primitive reuses `CellId` across keys, upgrade bucket key from `CellId` to `(CellId, KeyHash)` (~50 lines, mechanical). Not needed while `MemoMap` continues to allocate fresh `CellId` per key.
- **`Accumulator::clear(memo)` manual reset** — ripple has this. Our automatic per-recompute clearing makes it unnecessary unless a driver wants selective resets.

---

## References

- Driver: `examples/lambda/src/typecheck/types.mbt:53-57` (`TypeResult.diagnostics`), `infer.mbt:36` (`merge_diagnostics`), `typecheck.mbt:263` (`collect_results`)
- Related work surveyed during design:
  - Salsa's `#[salsa::accumulator]` (Rust) — type-keyed transitive, inspiration for API shape
  - [`mizchi/ripple`](https://github.com/mizchi/ripple) — MoonBit incremental library with `Accumulator[V]` (naive per-invocation; no transitive, no invalidation). Validates storage shape; its omissions show what Approach 2's machinery contributes. See `src/accumulator.mbt`.
  - [`Yoorkin/any.mbt`](https://github.com/Yoorkin/any.mbt) — examined to confirm MoonBit has no compile-time `TypeId` (user-supplied tokens only), ruling out Salsa-style type-as-key in MoonBit.
- Codex reviews:
  - Review 1 (architecture): rejected transitive MVP; flagged slot_id reuse, under-keyed synthetic reads, HashSet structural check, contributor-snapshot quadratic cost, memo-disposal semantic hole. All fixed in this spec.
  - Review 2 (data flow): flagged durability shortcut bypass (P0.1), transactional staging on `ActiveQuery` (P0.2), memo disposal claim (P1.3), alias bugs in BEFORE_CLOSURE (P1.4), `Memo::get` piggybacking (P2.5), Array Eq semantics (P2.6), ON_ABORT leaving garbage in new slots (#9). All fixed.
- Existing incr patterns reused:
  - `Runtime::check_cross_runtime` (`cells/tracking.mbt:149`)
  - `CellLifecycle` trait and engine impls (`cells/pull_memo_lifecycle.mbt` etc.)
  - `ActiveQuery` transactional dep commit discipline (`cells/memo.mbt:401`)
  - `pull_verify` dep walk (`cells/verify.mbt`)
  - Scope-owned handle lifecycle (`cells/scope.mbt`)
  - Custom constructor pattern for `pub struct` types (per CLAUDE.md MoonBit conventions)

---

## Estimated Scope

**~1100-1200 lines** of new code across:

| Area | Lines | Notes |
|---|---|---|
| `types/accumulator_id.mbt` | ~30 | struct + custom constructor + derives |
| `cells/accumulator.mbt` | ~200 | handle type + methods + typed closures |
| `cells/runtime.mbt` additions | ~40 | `ensure_computed_untracked` helper; `accumulator_slots` + `accumulator_contributions` fields + accessor methods |
| `cells/internal/pull/memo_data.mbt` | ~10 | `accumulator_reads` field |
| `cells/memo.mbt` integration | ~80 | BEFORE_CLOSURE, AFTER_CLOSURE, ON_ABORT phases around compute; closure type migration to `raise Failure` |
| `cells/verify.mbt` integration | ~30 | bypass both durability shortcuts + synthetic dep check |
| `cells/tracking.mbt` additions | ~20 | `ActiveQuery.accumulator_reads` + `touched_accumulator_slots` fields |
| `cells/pull_memo_lifecycle.mbt` addition | ~15 | accumulator cleanup in `dispose_cell` for `MemoData` |
| `cells/scope.mbt` addition | ~10 | `Scope::accumulator` factory registering dispose hook |
| `incr.mbt` re-export | ~5 | public API surface |
| `cells/accumulator_wbtest.mbt` | ~250 | whitebox test coverage |
| `tests/accumulator_test.mbt` | ~350 | integration + edge cases |
| Driver migration in `examples/lambda/` | ~100 | field removal, push call additions, `def_name` threading, test migration |
| **Total** | **~1140** | implementation + tests + driver |

Breakdown includes both implementation and tests. The memo closure type migration from `() -> T` to `() -> T raise Failure` adds ~20-40 lines of signature changes; empirical verification confirms non-raising callers auto-promote, so no caller-site churn.

**Public API compatibility:** no breaking changes to the incr public API surface — existing non-raising memo closures compile unchanged (empirically verified; see §Prerequisite Verification: resolved). **Driver-side:** the lambda type-checker migration is a breaking change to that package's public API (`TypeResult.diagnostics` field removal; aggregate-collection semantics shift from "always all defs" to "read via accumulator"). This is a coordinated change — lambda is the only consumer and ships in the same PR series.
