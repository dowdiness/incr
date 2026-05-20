# ADR: T3 (`RuntimeRegistry`) — Designed, Gated on Driver

**Date:** 2026-05-17
**Status:** Accepted — design recorded; commission on driver, not before
**Anchors:** [Async-at-the-edges](2026-05-17-async-at-the-edges.md), [R2 deferred](2026-04-26-r2-runtime-decomposition-deferred.md), [2026-04-20 architecture assessment](../design/specs/2026-04-20-architecture-assessment.md) (AP4, §4 T3)

## Context

Cross-runtime identity in incr today relies on two file-scope mutable refs:

```moonbit
// cells/internal/kernel/state.mbt:17
let next_runtime_id : Ref[Int] = { val: 0 }

// cells/internal/kernel/state.mbt:28
let current_computing_runtime_id : Ref[Int] = { val: -1 }
```

These power three concrete behaviors:

1. **Runtime-id allocation** (`alloc_runtime_id()` at `state.mbt:32`) — monotonic counter, never decreases.
2. **Strict cross-runtime guard** — `check_cross_runtime(cell_runtime_id, kind)` at `kernel/tracking.mbt:92`. Aborts if the cell's runtime_id differs from the active recompute's runtime_id. Called from 8+ sites: `Memo::get_result`, `HybridMemo`, `Reactive`, `Relation`, `FunctionalRelation`, `Accumulator` (4 read methods), and various memo-accumulated APIs.
3. **Forgiving repair** — `Memo::get_result_inner` at `cells/memo.mbt:215-240`. If this runtime's tracking stack is empty AND `current_computing_runtime_id` is non-negative, treat the global as stale-from-abort and reset it to `-1` rather than aborting. Required by `read_permissive` and `MemoMap::get_or_create_memo` call patterns that bypass the outer strict check.

The forgiving-repair path is **load-bearing for panic-test isolation**. The 2026-04-19 refactor audit (Target #1) attempted to unify it with the strict helper and broke 5 tests — the comment at `memo.mbt:221-226` documents why: "stale-global" vs "legitimate cross-runtime" cannot be distinguished locally without a global registry that can answer "is runtime N still alive?"

The 2026-04-20 architecture assessment names this as **AP4** and proposes **T3 (`RuntimeRegistry`)** as the resolution, gated on a parallelism driver. The async-at-the-edges ADR (2026-05-17) reaffirms the gate with a more concrete trigger: "build when the first multi-runtime async driver lands."

This ADR exists to (1) record the design at sufficient detail that future commissioning is a small step, and (2) make the gate explicit so opportunistic refactors do not lift it.

## Why this is gated, not killed

The current Refs **work** under MoonBit's single-threaded synchronous model. Concretely:

- Between any two synchronous incr API calls, no other task can run (cooperative scheduling, no preemption).
- `current_computing_runtime_id` is set in `push_tracking` (`kernel/tracking.mbt:9`) and cleared in `pop_tracking` / `pop_tracking_full` (lines 21, 36). Both endpoints are inside sync code; no `await` can occur between them.
- All recompute closures are typed `() -> T` (not `async () -> T`), enforced by MoonBit's function-coloring (see the async ADR).

So the global is correct-by-sync-bracketing-discipline. T3 makes it correct-by-data-structure instead.

The cost is non-trivial:

- **Highest-judgment change in the codebase.** The forgiving-repair path is referenced as load-bearing in three places (`memo.mbt:221-226`, audit doc, prior memory entries). Touching it without a regression net is a correctness risk.
- **Test scaffolding has to come first.** An interleaving test suite (two-runtime alternating tasks, panic recovery, mid-task switches) must exist before any code change, so the refactor has something to verify against.
- **No driver-visible benefit today.** Drivers cannot observe the difference between Ref-based and registry-based identity.

The right time to spend that cost is when a driver creates a regression-net necessity.

## Proposed design

### Data structure

A registry living alongside the existing module-state in `cells/internal/kernel/`. Single struct, two queries, monotonic allocation, no slot reuse.

```moonbit
// cells/internal/kernel/runtime_registry.mbt (new file)
priv struct RuntimeRegistry {
  // Bitmap or sparse set indexed by runtime_id. true == alive.
  mut alive : Array[Bool]
  // Currently-active recompute owner. -1 sentinel for "none".
  // Replaces the file-scope `current_computing_runtime_id` Ref.
  mut active : Int
  // Replaces the file-scope `next_runtime_id` Ref.
  mut next_id : Int
}

let runtime_registry : Ref[RuntimeRegistry] = { val: { alive: [], active: -1, next_id: 0 } }

pub fn alloc_runtime_id() -> Int { ... }     // allocates, sets alive[id] = true
pub fn dispose_runtime(id : Int) -> Unit { ... }  // alive[id] = false
pub fn is_runtime_alive(id : Int) -> Bool { ... }
pub fn get_active_runtime() -> Int { ... }   // replaces get_current_computing_runtime_id
pub fn set_active_runtime(id : Int) -> Unit { ... }  // replaces set_*
```

**Why these primitives:**
- `alloc_runtime_id` keeps the monotonic-counter contract (CellId comparisons across runtimes stay sound).
- `dispose_runtime(id)` is the new primitive — flips a runtime from alive to disposed. Called from `Runtime`'s drop path (which today does not exist as an explicit API — Runtimes are implicitly released when no handles reference them; the registry forces this to become explicit, see migration below).
- `is_runtime_alive(id) -> Bool` is the principled answer to "is this id stale?" Replaces the heuristic in `Memo::get_result_inner`.
- `get_active_runtime` / `set_active_runtime` are renames of the existing accessors, kept symmetric so the call sites only change in semantics, not in shape.

**Why module-level Ref to a registry struct rather than a per-Runtime field:**
- Cross-runtime checks happen at the boundary *between* runtimes; placing the registry on one Runtime arbitrarily would invert the dependency.
- A module-level registry is logically equivalent to today's pair of Refs but encapsulates the state in one struct, so future audits have one place to look.
- Under cooperative single-threaded async, no synchronization is needed — same threading model as today's Refs.
- Under any future preemptive model, the registry becomes the single place to add atomic ops; today's two Refs would each need separate treatment.

### Strict guard rewrite

`check_cross_runtime` keeps its signature; body becomes:

```moonbit
pub fn check_cross_runtime(cell_runtime_id : Int, kind : String) -> Unit {
  let active = get_active_runtime()
  guard active >= 0 && active != cell_runtime_id else { return }
  set_active_runtime(-1)
  abort(<cross-runtime message>)
}
```

No behavior change for current call sites.

### Forgiving repair rewrite

`Memo::get_result_inner`'s heuristic (`memo.mbt:221-240`) is replaced with a principled query:

```moonbit
let active = @kernel.get_active_runtime()
if active >= 0 && !@kernel.is_runtime_alive(active) {
  // Active runtime was disposed mid-computation; the global is stale.
  @kernel.set_active_runtime(-1)
} else if active >= 0 && active != self.rt.core.runtime_id {
  @kernel.set_active_runtime(-1)
  abort(<cross-runtime message>)
}
```

**The new contract is sharper:** "stale" means "the runtime whose id is in `active` is no longer alive." "Cross-runtime" means "the runtime whose id is in `active` is alive AND is not this runtime." The two cases are now distinguishable without relying on "this runtime's tracking stack is empty" as a proxy.

This sharpening is the point of the refactor — the existing proxy works today but is invisible to readers and brittle to future call-pattern changes (e.g., a new helper that pushes a frame before reading).

### Runtime disposal

Today, Runtimes have no explicit `dispose` API. They're released when no handles reference them. T3 introduces an explicit lifecycle:

- `Runtime::dispose(self) -> Unit` flips the registry entry to `alive[id] = false`.
- Existing test patterns that abandon a Runtime mid-computation (panic-test isolation) gain a clean repair path: the next `Memo::get_result_inner` sees the registry says "not alive" and resets `active` cleanly.

**Open design question** (deliberately deferred to commissioning): whether `Runtime::dispose` is `pub` (driver-callable) or only invoked from teardown code. The forgiving-repair path's existing trigger is an *unhandled abort* inside a recompute — the test fixture never explicitly disposes the runtime. Two viable answers:

1. **Implicit disposal via abort recovery.** A new `cells/internal/kernel/abort_repair.mbt` helper detects "current active_runtime aborted while computing" and marks the runtime disposed. Matches current behavior.
2. **Explicit `Runtime::dispose` in panic-test setup.** Cleaner contract; requires test fixture changes.

Pick during commissioning when the driver constraints are concrete.

## Gate conditions

T3 is commissioned when **any one** of the following is true:

1. **A multi-runtime async driver lands** (per the async ADR). A driver creating two or more Runtimes inside one `with_task_group` makes the sync-bracketing discipline harder to audit. The registry replaces audit with type-level guarantee.

2. **MoonBit's execution model gains preemption or shared-memory parallelism.** Today's Refs become unsafe without atomic ops. The registry is the natural place to add them; the call-site refactor is the same regardless.

3. **An observable test failure attributable to the heuristic.** If a future call-pattern change (e.g., a new helper that pushes a tracking frame before reading) breaks the "tracking stack empty" proxy, the registry's principled liveness check is the resolution.

**Explicit non-triggers** (do not commission on these):

- Cosmetic cleanup ("the two Refs are ugly")
- Audit reviewer preference without a concrete failure
- Adjacent refactors touching nearby code (do them, leave the Refs alone)
- The async-at-the-edges ADR being accepted *without* a driver adopting it — the ADR documents compatibility, it is not itself a driver

## Migration plan (when commissioned)

Single PR, four phases, each verifiable independently. Codex pre-implementation review of the registry shape **before** phase 1.

### Phase 1 — Interleaving test suite (additions only, no refactor)

Add tests *before* touching any production code. Each test must pass against the **current** Refs-based implementation, then be re-verified after the refactor.

- Two-runtime alternating reads: task A reads memo on RtA, task B reads memo on RtB, repeat — `current_computing_runtime_id` discipline must hold.
- Panic recovery: abort inside Runtime A's recompute, then Runtime B reads its own memo — must not falsely flag cross-runtime.
- `MemoMap::get_or_create_memo` after panic: known forgiving-repair trigger; must still work.
- `read_permissive` after panic: same.
- Sync-only (no `moonbitlang/async`) and async-driven (if dependency available on the test target) variants.

Land as a standalone PR if the volume warrants. Tests in `tests/cross_runtime_interleaving_test.mbt`.

### Phase 2 — Registry skeleton (no behavior change)

Add `cells/internal/kernel/runtime_registry.mbt` with the struct + accessors above. Wire `alloc_runtime_id` / `get_active_runtime` / `set_active_runtime` to delegate to the registry while keeping the same public names. The two Refs become private inside the registry struct; no caller change.

All 508+ existing tests + phase-1 tests must remain green. Bench gate ±5% on `tests/bench_test.mbt`.

### Phase 3 — Forgiving-repair principled rewrite

Replace `Memo::get_result_inner:221-240` with the `is_runtime_alive`-based check. Add the disposal hook (option (1) or (2) from §"Runtime disposal" above, decided during commissioning).

All phase-1 interleaving tests must remain green. All panic-isolation tests must remain green. Codex review on the rewritten block specifically.

### Phase 4 — Audit and document

- Grep for any remaining direct use of `current_computing_runtime_id` outside the registry module. Should be zero.
- Update `cells/internal/kernel/state.mbt` to remove the two Refs (they now live in `runtime_registry.mbt`).
- Update `docs/design/internals.md` cycle-detection / cross-runtime section.
- Add a memory entry retiring the "Verify code not memory" caveat for the cross-runtime mechanism.

## Verification

Same gates as any structural PR, plus T3-specific items:

| Check | Requirement |
|---|---|
| Phase-1 interleaving suite | All green before phase 2 starts |
| `moon test` | 508+ → 508+ + new interleaving tests, all green |
| `scripts/check-engine-isolation.sh` | Green (no new cross-engine imports) |
| `moon bench --release` on `tests/bench_test.mbt` | Within ±5% of pre-T3 baseline |
| `moon info && moon fmt` | No unintended `.mbti` diffs (registry is `priv`; no public API change expected) |
| Codex review | Pre-implementation on registry shape + post-implementation on the rewritten `get_result_inner` block |
| Manual audit | Zero direct uses of `current_computing_runtime_id` outside `runtime_registry.mbt` |

## Risks and how the migration plan addresses them

| Risk | Mitigation |
|---|---|
| Breaking the forgiving-repair path's panic-test isolation | Phase 1 interleaving suite captures the exact patterns; phase 3 must pass them |
| Introducing a regression in cross-runtime abort semantics | Codex review on `Memo::get_result_inner` rewrite; manual diff comparison against the heuristic block |
| Registry adds allocation overhead | Bench gate; the registry is one struct allocated once per runtime, so the impact is bounded by `alloc_runtime_id` cost |
| Disposal contract ambiguity | Resolved at commissioning, not in this ADR |
| Future MoonBit preemption invalidates the design | Reopen this ADR; the registry struct is the place to add atomic ops, but the call sites would also need re-audit |

## Trade-offs accepted

- **Accept correct-by-discipline today.** The two Refs work under sync-bracketing. Documenting the discipline (this ADR + the audit's existing notes at `memo.mbt:221-226`) is cheaper than rewriting until a driver makes the rewrite valuable.
- **Accept the highest-judgment-change cost when commissioning.** Phase 1 interleaving tests are mandatory, not optional. Skipping them would be the failure mode the 2026-04-19 audit warned about.
- **Accept that this ADR is largely documentation.** A future commissioning agent will not need to re-discover the design space — but they will need to make two concrete decisions (disposal hook shape, sync-vs-async variant of the interleaving tests) that this ADR deliberately leaves open.

## Scope

**In scope:**
- The two file-scope Refs in `cells/internal/kernel/state.mbt:17,28`.
- The forgiving-repair block in `cells/memo.mbt:215-240`.
- The 8+ `check_cross_runtime` call sites (no behavior change required — they call `get_active_runtime` internally).
- The disposal hook on `Runtime`.

**Out of scope:**
- The `Runtime` struct's overall shape (covered by R2 ADR; deferred).
- Any other architectural restructuring of `cells/internal/kernel/`.
- Public-API changes to `Signal`/`Memo`/`Reactive`/`Effect`/`Relation`/`Rule`.
- Drivers' use of `Runtime::dispose` (driver-side concern).
- Compute parallelism (no help here; orthogonal).

## What this ADR retires

- The implicit framing that AP4 / T3 is "deferred until parallelism" exclusively. The async-at-the-edges ADR establishes that multi-runtime async is also a valid trigger.
- The expectation that a future agent will need to re-derive the registry design from scratch. The shape, the migration order, and the verification gates are recorded here; commissioning is a small step from this document.
