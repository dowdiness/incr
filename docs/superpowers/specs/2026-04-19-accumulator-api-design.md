# Accumulator API Design (local-only MVP)

**Status:** Approved design (Path 1 — local-only; transitive reconsidered post-MVP)

**Date:** 2026-04-19

**Driver:** Lambda type-checker diagnostics (`examples/lambda/src/typecheck/`) — replaces the manually-threaded `TypeResult.diagnostics : Array[TypeDiagnostic]` field + `merge_diagnostics` helper with a side-channel that collects per-memo push values.

**Prerequisites:**
- Boundary 3 type-checker merged (loom#81 + incr#34) — provides the concrete driver
- PR #41 merged (`MemoMap::get_tracked`) — establishes misuse-guardrail pattern for MemoMap
- Runtime Modularization Stage 5 merged — stable internal package boundaries

**Supersedes:** nothing. This is the first accumulator design in `incr/`.

**Open design questions resolved:** All four questions in `docs/todo.md:220-226` are answered in [§Open Questions Resolved](#open-questions-resolved).

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
pub fn[T] Accumulator::push(self : Accumulator[T], value : T) -> Unit raise
// fails on: outside tracked frame, non-Memo frame (MVP), disposed accumulator
// aborts on: cross-runtime (via existing check_cross_runtime helper)
```

### Read (Memo methods)

```moonbit
// Tracked read: records synthetic dep on current compute frame
pub fn[T, A] Memo::accumulated(
  self : Memo[T],
  acc : Accumulator[A],
) -> Array[A] raise
// raises CycleError if target verification detects a cycle
// returns [] if accumulator or target memo is disposed

// Untracked read: no synthetic dep; for outside-runtime consumers (UI, tests)
pub fn[T, A] Memo::accumulated_peek(
  self : Memo[T],
  acc : Accumulator[A],
) -> Array[A]
// no CycleError path (no verify triggered)
// returns [] if accumulator or target memo is disposed

// Result-style variant for graceful cycle handling (mirrors Memo::get_result)
pub fn[T, A] Memo::accumulated_result(
  self : Memo[T],
  acc : Accumulator[A],
) -> Result[Array[A], CycleError]
```

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

Scope-owned accumulators disposed automatically via `CellLifecycle` integration.

### Why no trait

Accumulator is a concrete type. Operations (push, accumulated, diff, dispose) don't vary by implementation. Consumes existing incr traits (`CellOps`, `CellLifecycle`) for integration; introduces no new trait. Type erasure for runtime-side bookkeeping uses captured closures (matches incr's existing `on_change` / `commit_pending` closure pattern), not trait dispatch.

### Why `T : Eq` only on factories

Push needs no Eq — it just appends. Invalidation diffing (`per_memo[M] != prev_push_sets[M]`) needs Eq, but the diff closure is constructed at `Accumulator::new` with `T : Eq` in scope. The handle itself stores the type-erased diff closure. This matches incr's design principle "constraints only where needed" (`docs/api-design-guidelines.md:29-37`).

---

## Architecture

### Handle-local typed storage

Typed buffers live on the `Accumulator[T]` handle. Runtime stores only slot-id metadata and a reverse index.

```text
Accumulator[T]                              Runtime additions
──────────────                              ─────────────────
  rt : Runtime                               accumulator_slots :
  slot_id : AccumulatorId                      Array[Option[SlotMeta]]
  per_memo : HashMap[CellId, Array[T]]       next_accumulator_id : Int   -- monotonic, NO REUSE
  prev_push_sets :                           accumulator_contributions :
    HashMap[CellId, Array[T]]                  HashMap[CellId, HashSet[AccumulatorId]]
  push_revised_at :                        -- reverse index: slots each memo pushed to
    HashMap[CellId, Revision]             -- populated on successful recompute commit
  label : String?

SlotMeta (in Runtime, keyed by AccumulatorId.id)
────────
  label : String?
  mut disposed : Bool
  -- type-erased closures that capture the typed Accumulator[T] handle
  -- (created at Accumulator construction with T : Eq in scope)
  snapshot_and_clear : (CellId) -> Unit
  restore_buffer : (CellId) -> Unit
  diff_memo : (CellId) -> Bool
  dispose_memo : (CellId) -> Unit

ActiveQuery additions
─────────────────────
  accumulator_reads : HashMap[(AccumulatorId, CellId), Revision]
  touched_accumulator_slots : HashSet[AccumulatorId]
  -- both committed to memo's persisted state on success; discarded on failure

Memo[T] additions (persisted, post-commit)
───────────────────────────────────────────
  accumulator_reads : HashMap[(AccumulatorId, CellId), Revision]
  -- "at last recompute, I read slot S's values from target T, saw revision R"
```

The type-erased closures live on `SlotMeta` (not the Accumulator handle). They are constructed at `Accumulator::new` with `T : Eq` in scope and capture references to the handle's typed buffers. Runtime-side code dispatches through `SlotMeta.snapshot_and_clear(M)` etc. without ever seeing `T`.

### Key properties

1. **No type erasure in typed storage.** `Accumulator[T]` holds `Array[T]` buffers directly. Type parameter `T` is preserved from push through read.

2. **Monotonic `AccumulatorId`, no reuse.** Disposed slots become `None` in `rt.accumulator_slots`. Fresh `Accumulator::new` gets a fresh id. Stale `accumulator_reads` entries on live memos resolve to "slot disposed → invalidate R" at verify time (fixes slot-aliasing bug identified in Codex review 1).

3. **Synthetic read key is `(AccumulatorId, CellId)`.** Distinct from ordinary deps. A compute frame can read accumulator state from multiple targets without entries colliding.

4. **No second dep graph.** The runtime's existing ordinary-dep graph carries the causality. Accumulator synthetic deps ride alongside, keyed by target memo's `CellId`, compared against per-target `push_revised_at`.

5. **Transactional staging on `ActiveQuery`.** Synthetic reads and contribution sets live on `ActiveQuery` during compute; committed to persisted state only on success. Discarded on failure. Mirrors the ordinary-dep commit discipline at `cells/memo.mbt:401`.

---

## Data Flow

### Push flow — `acc.push(v)`

```text
1. Guard: rt.tracking_stack empty
      → fail("Accumulator::push called outside a tracked compute")
2. Cross-runtime check via Runtime::check_cross_runtime("Accumulator")
      → aborts on runtime_id mismatch (existing pattern)
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
1. all_slots := prev_contributions ∪ frame.touched_accumulator_slots
2. For each slot_id in all_slots:
   if slot.diff_memo(M):                       -- closure internally compares
     slot.push_revised_at[M] := rt.current_revision   -- prev_push_sets[M] vs per_memo[M]
3. For each slot_id in prev_contributions but NOT in touched:
   slot.per_memo.remove(M)   -- contributor stopped; buffer gc'd
4. For each touched slot:
   slot.prev_push_sets.remove(M)   -- snapshot no longer needed
5. Commit frame.accumulator_reads → M.accumulator_reads (persisted)
6. Update rt.accumulator_contributions[M] from frame.touched_accumulator_slots
```

The `slot.diff_memo(M)` closure internally reads `prev_push_sets.get(M).or([])` and `per_memo.get(M).or([])` from the captured handle and returns `true` iff they differ. First-push-to-fresh-memo (missing prev) correctly bumps because `[] != [v, ...]`. Stopped-pushing (missing current) correctly bumps because `[prev, ...] != []`.

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
1. Cross-runtime check on acc
2. If slot.disposed → return []
3. pull_verify(M.cell_id)
   -- NOT Memo::get; that would record M as ordinary dep. We want
   -- M's verification without making it an ordinary dep of reader R.
4. current_rev := slot.push_revised_at.get(M.cell_id).or(0)
5. If frame R exists:
     frame.accumulator_reads[(slot_id, M.cell_id)] := current_rev   -- staged
6. Return slot.per_memo.get(M.cell_id).or([]).copy()   -- defensive copy
```

### Peek flow — `memo.accumulated_peek(acc)`

Same as tracked read, but:
- Skip step 5 (no synthetic dep recording)
- Step 3 returns current buffer without forcing verification (matches `Signal::peek` semantics)
- No CycleError path

### Verify flow — integrated into `pull_verify(R)`

```text
Fast-path guard (NEW):
  If R.accumulator_reads is non-empty, DISABLE the durability shortcut
  at cells/verify.mbt:95 for this run.
  [MVP: bypass the shortcut entirely. Future optimization: fold target
   durabilities into R's durability. See Deferred Work.]

(existing) Walk R's ordinary deps; compare each dep.changed_at to R.verified_at.

Synthetic dep check (NEW, after existing dep walk):
  For each (slot_id, target_id) → stored_rev in R.accumulator_reads:
    slot := rt.accumulator_slots[slot_id.id]
    if slot is None OR slot.disposed OR rt.is_cell_disposed(target_id):
       invalidate R
       continue
    current_rev := slot.push_revised_at.get(target_id).or(0)
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

### Memo disposal — `CellLifecycle` hook

```text
When memo M disposed:
  If M in rt.accumulator_contributions:
    For each slot_id in rt.accumulator_contributions[M]:
      slot.dispose_memo(M):
        per_memo.remove(M)
        prev_push_sets.remove(M)
        push_revised_at.remove(M)
    rt.accumulator_contributions.remove(M)
```

Stale `R.accumulator_reads` entries referencing disposed M correctly invalidate R at R's next verify — the explicit `is_cell_disposed(target_id)` check in the verify flow handles this (fixes memo-disposal bug identified in Codex review 2).

### Batch interaction

Pushes during `rt.batch(...)` use post-commit revision (same as signal commits). **No batch-specific rollback closure.** The recompute transaction boundary (ActiveQuery commit/discard) is the correct rollback unit. Batch's signal-rollback system (`cells/batch.mbt:216`) handles raised errors on explicit signal writes, not `abort()` (`cells/batch.mbt:64`), and isn't the right abstraction for per-compute accumulator state.

---

## Error Handling

| Condition | Fault class | Mechanism |
|---|---|---|
| Push outside tracked frame | Defect (user misuse) | `fail("Accumulator::push called outside a tracked compute")` |
| Push in non-Memo frame (MVP) | Defect | `fail("Accumulator::push only valid inside Memo compute")` |
| Cross-runtime push/read | Defect | Existing `check_cross_runtime` (aborts — pre-existing pattern, not new) |
| Push to disposed accumulator | Defect | `fail("push to disposed Accumulator")` |
| Read from disposed accumulator | Not an error | Return `[]` (permissive) |
| Read from disposed target memo | Not an error | Return `[]` (permissive) |
| Cycle in target's verify | Expected failure | Raises existing `CycleError` |

**Abort discipline:** no new abort sites are introduced. Cross-runtime checks reuse `Runtime::check_cross_runtime` which aborts (pre-existing tech debt; not in scope for this spec). All accumulator-specific caller misuse uses `fail` (catchable at FFI boundaries with source location).

**Value-semantic T requirement (documented, not enforced):**

> `T` must be value-semantic — do not mutate pushed values in place. Structural `Array` equality drives the `diff_memo` check; mutable elements may produce false equality and miss push-set bumps. If `T` contains mutable state, construct new instances for each push.

**Future escape hatch:** `Accumulator::new_always_bump()` — skips diff, bumps on every push. Removes `T : Eq` and value-semantic requirements at the cost of conservative invalidation. Deferred until a driver needs it.

---

## Testing Plan

### Whitebox tests — `cells/accumulator_wbtest.mbt`

| Test | Verifies |
|---|---|
| `accumulator: slot_id monotonic across dispose/new` | No id reuse |
| `accumulator: per_memo buffer cleared on force_recompute start` | BEFORE_CLOSURE move-and-replace |
| `accumulator: prev_push_sets snapshot is a deep copy, not alias` | Clearing per_memo doesn't destroy snapshot |
| `accumulator: push_revised_at bumps only on diff_memo == true` | Core invalidation mechanic |
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
- `panic` tests for cross-runtime push/read (existing `check_cross_runtime` abort)
- Cycle in target's verify: `accumulated` raises CycleError; `accumulated_result` returns `Err`

**Permissive cases:**
- Read from disposed accumulator → `[]`
- Read from disposed target memo → `[]`
- Zero pushes → `[]` (no error)

**Transactional discipline:**
- User closure `fail` mid-recompute → accumulator state restored; next recompute starts from correct snapshot
- Cycle during sub-memo read from within parent's closure → parent's partial accumulator_reads discarded
- Partial push to new slot + error → new-run-only slot cleared

**Lifecycle:**
- `Scope::accumulator` disposed with scope → reads return `[]`
- Memo dispose clears its entries from all accumulators
- Stale `accumulator_reads` on readers after target dispose → verify correctly invalidates (Codex P1.3)

**Diamond / nested:**
- Reader reads `sub.accumulated(acc)` twice in same compute → single synthetic dep, consistent
- Nested recompute: parent's closure triggers sub.get() which triggers force_recompute(sub); sub's BEFORE_CLOSURE doesn't corrupt parent's accumulator state

**Introspection:** standard `id`, `label`, `is_disposed`, `debug` coverage.

### Driver integration — `examples/lambda/src/typecheck/` (separate PR after MVP lands)

- Replace `TypeResult.diagnostics : Array[TypeDiagnostic]` field with `diags.push(d)` calls inside `infer`/`check`.
- Remove `merge_diagnostics` helper.
- Replace `ModuleTypeResult.all_diagnostics` aggregation with `type_memos.map(m => m.accumulated_peek(diags)).flatten()` + `body_memo.accumulated_peek(diags)`.
- Existing typecheck tests pass unchanged (behavioral equivalence).
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

**1. Type erasure (Runtime is not generic).** Resolved by **handle-local typed storage**. `Accumulator[T]` owns typed `per_memo: HashMap[CellId, Array[T]]`. Runtime stores `Option[SlotMeta]` with type-erased closures; never sees `T`.

**2. Transitive collection from sub-calls.** **Not solved in MVP** — Path 1 is local-only. Transitive is the wrong default for the lambda driver (env-chain causes over-collection per Codex review 1). Reconsider post-MVP; see Deferred Work.

**3. Array[T] equality backdating; insertion order stability.** Resolved by **structural `Array` Eq over `T : Eq`** at end-of-recompute. Push order within a compute is stable (`Array.push` is append). `T : Eq` bound on factories only. Documented value-semantic requirement for mutable `T`.

**4. Invalidation when only accumulated values change.** Resolved by **per-memo `push_revised_at : Revision`** bumped at end-of-recompute when `diff_memo(M)` detects a difference. Reader records `(slot_id, target_cell_id) → stored_rev` on its `accumulator_reads`; verify compares stored vs current. Durability shortcut disabled for memos with accumulator reads (MVP) — future optimization folds target durabilities into reader durability.

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

~300-400 lines of new code across:
- `types/accumulator_id.mbt` (~30 lines)
- `cells/accumulator.mbt` (~150 lines: handle type + methods + closures)
- `cells/accumulator_lifecycle.mbt` (~30 lines: CellLifecycle impl for scope integration)
- Integration into `cells/memo.mbt` / `cells/verify.mbt` / `cells/tracking.mbt` (~60 lines: BEFORE/AFTER/ON_ABORT phases, verify-side check, ActiveQuery extension)
- `cells/accumulator_wbtest.mbt` (~200 lines)
- `tests/accumulator_test.mbt` (~350 lines)
- Driver migration in `examples/lambda/` (~50 line delta: field removal, push call additions)

Breakdown includes both implementation and tests. No breaking changes to existing API surface.
