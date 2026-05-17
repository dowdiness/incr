# ADR: `Runtime::on_memo_event` — Public Commit-Phase Event Observation

**Date:** 2026-05-17 (amended same-day after Codex review of T1b plan)
**Status:** Accepted — implementation gated on T1b landing first
**Anchors:** [T1b (`MemoCommitPhase`)](2026-05-17-t1b-memo-commit-phase.md), [Async-at-the-edges](2026-05-17-async-at-the-edges.md)

**Amendments (2026-05-17, post-Codex):**
- §"Internal implementation": confirmed `backdated` detection via `cell.meta.changed_at < cell.verified_at` works correctly because T1b ADR was amended same-day to fire `after_success` *after* the cell-level epilogue. Without that timing fix, backdating would not have been detectable from the hook.
- §"Internal implementation": **buffer-and-flush** rather than inline listener dispatch. Per T1b's hook contract amendment, hooks must not call user code inline (typed memo cache not yet written, nested-recompute dep pollution, `recompute_inner.changed` decision depends on epilogue state). The `EventBroadcastPhaseHook` appends to an internal `pending_events` queue inside each hook method and drains at a safe point. See §"Drain protocol" below.
- §"Context" and §"Internal implementation": file placement is `cells/`, **not** `cells/internal/kernel/`. Same engine-isolation rule as T1b (kernel cannot import `cells/`, and `MemoCommitPhase` takes `rt : Runtime`).

## Context

T1b (2026-05-17, amended same-day) introduces a `priv` `MemoCommitPhase` trait inside `cells/` (not `cells/internal/kernel/` — engine isolation forbids the trait there because it takes `rt : Runtime`). The trait has three hooks: `before_recompute` / `after_success` (post-epilogue) / `after_abort`. T1b's PR scope is internal — it refactors the accumulator's three named calls into a trait impl. No public API change.

This ADR specifies the **driver-facing** half of the visualization story: a public callback API that drivers register against to observe pull-memo commit-phase events. The implementation is an in-tree `MemoCommitPhase` impl that bridges trait dispatch into user-supplied closures.

This ADR is independent of T1b in scope but **depends on T1b shipping first** — the public API uses T1b's hook dispatch as its substrate. If T1b is rejected or substantially reshaped, this ADR reopens.

## What this enables

A driver can render a dependency-graph visualization that animates commit-phase activity, without coupling to incr internals:

```moonbit
let viewer = GraphViewer::new()
rt.on_memo_event(fn(evt) {
  match evt {
    EnteringCompute(id) => viewer.flash_cell(id, color=Yellow)
    Completed(id, _ns, backdated=true) => viewer.dim_cell(id)
    Completed(id, ns, _) => viewer.flash_cell(id, color=Green, ms=ns / 1_000_000)
    Aborted(id, _ns, err) => viewer.flash_cell(id, color=Red, tooltip=err)
  }
})
```

Same callback shape powers a CLI profiler (`top`-style rate of recomputes per memo), a test diagnostics tap ("which memos recomputed during this test?"), or an aqueue-bridged async event log per the async ADR's effect-side pattern.

## Public API

```moonbit
// cells/observer.mbt or cells/introspection.mbt (placement TBD at commissioning)

pub(all) enum MemoEvent {
  EnteringCompute(CellId)
  Completed(CellId, elapsed_ns : Int64, backdated : Bool)
  Aborted(CellId, elapsed_ns : Int64, error : String)
} derive(Debug)

pub fn Runtime::on_memo_event(
  self : Runtime,
  f : (MemoEvent) -> Unit,
) -> Unit

pub fn Runtime::clear_memo_event_listener(
  self : Runtime,
) -> Unit
```

Three deliberate shapes:

- **Single listener per runtime**, replaces previous if any. Mirrors `Signal::on_change` / `Memo::on_change` exactly. Multi-listener support is deferred until a driver names two simultaneous consumers (rare; usually a fan-out happens inside the listener via a queue).
- **`pub(all) enum`** so drivers can pattern-match all variants. `derive(Debug)` for log-friendly output.
- **`(MemoEvent) -> Unit`** — sync, per the async ADR's coloring contract. Drivers who want async handling enqueue inside the sync callback (`@aqueue.Queue::put_nowait`).

The exact field shape (positional vs. labelled, struct-per-variant vs. inline) is left to the implementation plan. The *semantic content* is fixed:

| Variant | Always carries | Optional / TBD |
|---|---|---|
| `EnteringCompute` | `CellId` | (none) |
| `Completed` | `CellId`, `elapsed_ns`, `backdated` flag | possibly `revision : Revision` |
| `Aborted` | `CellId`, `elapsed_ns`, error stringification | possibly `revision : Revision` |

Including `revision` in event payloads is a convenience for drivers that want to group events into transactions; it's available from `rt.cell_info(id)` anyway. Decide at commissioning.

## Internal implementation

One new in-tree implementor of T1b's trait, plus a runtime-side drain protocol. Both live in `cells/`, not in `cells/internal/kernel/`.

Per T1b's hook contract, the hook **must not** call the user listener inline (typed memo cache not yet written; nested-recompute dep frame pollution; `recompute_inner.changed` decision can be perturbed). Instead, the hook **buffers** events into an internal queue and the runtime **drains** the queue at a safe point.

```moonbit
// cells/event_broadcast_hook.mbt
priv struct EventBroadcastPhaseHook {
  mut listener : ((MemoEvent) -> Unit)?
  timers : @hashmap.HashMap[CellId, Int64]
  pending : Array[MemoEvent]
}

priv impl MemoCommitPhase for EventBroadcastPhaseHook with before_recompute(
  self, _rt, cell_id,
) {
  guard self.listener is Some(_) else { return }  // no listener, no buffering
  self.timers[cell_id] = monotonic_now_ns()
  self.pending.push(EnteringCompute(cell_id))
}

priv impl MemoCommitPhase for EventBroadcastPhaseHook with after_success(
  self, rt, cell_id,
) {
  guard self.listener is Some(_) else { return }
  // `@hashmap.HashMap::remove` returns Unit; read then remove.
  let start = self.timers.get(cell_id).unwrap_or(0)
  self.timers.remove(cell_id)
  let elapsed = monotonic_now_ns() - start
  let backdated = was_backdated(rt, cell_id)  // changed_at < verified_at
  self.pending.push(Completed(cell_id, elapsed, backdated))
}

priv impl MemoCommitPhase for EventBroadcastPhaseHook with after_abort(
  self, _rt, cell_id,
) {
  guard self.listener is Some(_) else { return }
  // `@hashmap.HashMap::remove` returns Unit; read then remove.
  let start = self.timers.get(cell_id).unwrap_or(0)
  self.timers.remove(cell_id)
  let elapsed = monotonic_now_ns() - start
  self.pending.push(Aborted(cell_id, elapsed, last_recompute_error_string()))
}

// Called by the runtime drain protocol below.
// Reentrant safety: if a listener triggers another framework operation
// that would normally drain (e.g., Signal::set, Memo::get), the inner
// drain call sees `draining == true` and returns immediately. The
// outer drain loops on pending after its current pass to flush any
// tail events buffered by listener-triggered recomputes.
priv fn EventBroadcastPhaseHook::drain(self : EventBroadcastPhaseHook) -> Unit {
  if self.draining { return }  // inner drain — outer will pick up tail
  guard self.listener is Some(f) else { self.pending.clear(); return }
  self.draining = true
  while !self.pending.is_empty() {
    let events = self.pending
    self.pending = []
    for evt in events { f(evt) }
  }
  self.draining = false
}
```

(The `draining : Bool` field is added to `EventBroadcastPhaseHook` — not shown in the impls above. Initialized to `false`.)

The hook is **always registered** at `Runtime::new`. `Runtime::on_memo_event` flips `listener` to `Some(f)`; `clear_memo_event_listener` flips it back to `None`. When the listener is `None`, hook methods short-circuit immediately — no allocation, no buffer growth.

### Drain protocol

The drain runs when **both** of these are true:

1. `tracking_stack.is_empty()` — no memo is currently being recomputed (so user callbacks can safely call `Memo::get` without polluting an outer frame, and any recursive recompute is itself a top-level operation)
2. Every typed cache touched by the current operation has been written (the hook fires after the epilogue, but the typed `Memo::force_recompute` writes `self.value` *after* the kernel epilogue returns — so the safe point is *after* `force_recompute` returns, not at the end of `memo_force_recompute`)

The drain fires at the **completion of every framework operation that could synchronously trigger a memo recompute**, when the operation is about to return control to user code. Concretely, the drain helper `Runtime::drain_pending_events_if_idle()` is called from:

- **End of every public read API** that goes through `force_recompute` — `Memo::get`, `Memo::get_result`, `Memo::get_or`, `Memo::get_or_else`, `HybridMemo::get`, `HybridMemo::get_result`, plus `MemoMap` variants, **plus `Memo::accumulated` and `Memo::accumulated_result`** (which call `ensure_computed_untracked`, which calls `force_recompute`). Specifically: after the typed cache assignment, when `tracking_stack.is_empty()`.

  *Why this and not just "end of `recompute_inner`":* per Codex review round 3, `force_recompute` is also called from `get_result_inner` directly on first-compute paths that don't pass through `recompute_inner` (`cells/memo.mbt:246`, `:338`). Drain placement must cover all callers, not assume a single path.
- **End of `Observer::get`** and any `Runtime::read*` helpers (Database trait readers) — same reason as above; these are user-facing read entry points.
- **End of `Signal::set` outside a batch** — calls `propagate_changes` synchronously, which can trigger push-reactive recomputes; effect closures inside those recomputes can read memos, which buffer events. Drain at the bottom of `Signal::set` catches those.
- **End of `commit_batch`** after `propagate_changes` returns. Ordering matters: drain fires **after** existing `on_change` callbacks complete, so on_change handlers' synchronously-triggered recomputes flush in the same drain pass. (The `draining : Bool` reentry guard ensures any drain attempt nested inside an on_change handler returns immediately; the outer drain's while-loop picks up the tail.)
- **End of `Runtime::gc`** — defensive. gc can dispose memos, which is a recompute-adjacent operation; even though gc doesn't itself fire memo events today, future hook additions might.

The helper checks `tracking_stack.is_empty()` before invoking `event_broadcast_hook.drain()`. If the stack is non-empty (we're nested inside another framework operation), it returns without draining; the outer operation's drain call will pick up the events.

Equivalent invariant the drain protocol upholds: **drain whenever `tracking_stack.is_empty()` is about to be observed by user code**.

### Reentry and raise safety

`drain()` uses the `draining : Bool` guard for the case where a listener callback re-enters incr (calls `Signal::set`, `Memo::get`, etc.). Without the guard, the recursive read could see `tracking_stack.is_empty()` and try to drain again mid-iteration. The outer drain's `while !pending.is_empty()` loop ensures tail events buffered by reentrant operations are still flushed before returning.

**The `draining` flag must be reset even if a listener raises.** Otherwise the flag stays `true` permanently and the hook stops draining forever. Use a try/catch (or equivalent) inside `drain()`:

```moonbit
priv fn EventBroadcastPhaseHook::drain(self : EventBroadcastPhaseHook) -> Unit {
  if self.draining { return }
  guard self.listener is Some(f) else { self.pending.clear(); return }
  self.draining = true
  try {
    while !self.pending.is_empty() {
      let events = self.pending
      self.pending = []
      for evt in events { f(evt) }
    }
  } catch {
    e => {
      self.draining = false   // reset before re-raising
      raise e
    }
  }
  self.draining = false
}
```

Document in the public API that listener callbacks should handle their own errors; if they raise, the raise propagates out of the drain (and onward out of whatever framework operation triggered the drain), but pending events buffered AFTER the raise point will be picked up by the next drain attempt.

### What user callbacks may and may not do

Drained-event listeners run **outside** any memo recompute. They may:
- Call `Signal::get`, `Memo::get_result`, `Runtime::cell_info` — reads land outside any tracking frame, recorded as top-level operations
- Enqueue events into an `@aqueue.Queue` for async handling per the async-at-the-edges ADR
- Call `Signal::set` — but be aware that this immediately bumps the revision and may trigger another recompute cycle while still inside the outer call's stack. Document as "supported but expensive."

They **must not**:
- Call `abort()` — uncatchable; aborts the drain mid-event
- `raise` — propagates out of the drain; the rest of the queued events are lost. Document as "callbacks must handle their own errors"

Three implementation details deferred to the plan:

1. **Monotonic clock source.** `@time` stdlib, conditional compilation per target, or a runtime-injected clock function. Pick the smallest viable surface; `Int64` nanoseconds with "best-effort on platforms without monotonic time" is acceptable.
2. **Error stringification on abort.** The current `Memo::get_result_inner` catches and reabort-translates errors at line 207–209; the hook needs access to the raised error before that translation. Either thread the error through the trait method (changes T1b's signature) or capture via runtime state. Decide with Codex review.
3. **`was_backdated` detection.** A backdated recompute is one where `verified_at` advanced to `current_revision` but `changed_at` did not. Because T1b's amended timing fires `after_success` **after** the cell-level epilogue, the helper is a pure read of cell state: `cell.meta.changed_at < cell.verified_at`. Trivial.

## Event ordering and guarantees

Documented contract drivers can rely on:

1. **Lifecycle bracketing.** Every `EnteringCompute(c)` is followed by exactly one `Completed(c, ...)` or `Aborted(c, ...)`. Never both, never neither.
2. **Same-revision ordering.** Within a single revision bump (e.g., one `Signal::set` outside a batch, or one `commit_batch`), events fire in pull-verification traversal order — dependency-first, then dependent. Drivers can use the order to reconstruct the recompute tree.
3. **Atomicity vs. await.** Because callbacks are sync (per the async ADR), the entire `EnteringCompute → Completed/Aborted` window for one cell is uninterruptible by another task.
4. **HybridMemo coverage.** Events fire for both `Memo` and `HybridMemo` recomputes — they share the same commit path. Drivers cannot distinguish from the event alone; they can call `rt.cell_info(id)` if they need to know the cell kind.
5. **No events for green-path verification.** When `pull_verify` short-circuits via the root-durability shortcut or per-dep durability shortcut, no compute closure runs and no events fire. This is intentional — events are about recompute activity, not verification activity. A future ADR could add a separate `VerifyEvent` stream if drivers ask for it.
6. **No nesting.** A memo's recompute can read other memos, which may trigger their own recomputes inside the same enclosing `EnteringCompute`. Events for the inner recomputes interleave with the outer `EnteringCompute`/`Completed` pair. Drivers reconstructing the call tree must track the implicit stack (each `EnteringCompute` pushes; each `Completed`/`Aborted` pops).

## Migration plan (when commissioned)

Single PR after T1b's PR has merged. Codex pre-implementation review of the event enum shape and the timing-capture approach.

### Phase 1 — Internal hook + zero-listener wiring + drain sites

- Add `cells/event_broadcast_hook.mbt` with `EventBroadcastPhaseHook` struct (including `draining : Bool` reentry guard) + `MemoCommitPhase` impl (buffer-only, no inline listener call). Drain helper with `while !pending.is_empty()` loop for tail flush AND raise-safe try/catch that resets `draining` before propagating the listener's raise.
- Register at `Runtime::new` with `listener: None`. Add typed field `priv event_broadcast_hook : EventBroadcastPhaseHook` on `Runtime`, mirroring the `accumulator_commit_hook` pattern from T1b. Register the same object in `commit_hooks`.
- Add `priv fn Runtime::drain_pending_events_if_idle()` helper that checks `tracking_stack.is_empty()` and then calls `event_broadcast_hook.drain()`.
- Add drain calls at the full set of safe points enumerated in §"Drain protocol": all public read APIs (`Memo::get*`, `HybridMemo::get*`, `MemoMap::get*`, `Memo::accumulated*`, `Observer::get`, `Runtime::read*`), end of `Signal::set` when outside a batch, end of `commit_batch` (after on_change firing per §"Drain protocol"), end of `Runtime::gc`. Audit `cells/memo.mbt:246`, `:338` (both `force_recompute` callers) for coverage.
- Verify no behavior change with zero listener attached.

Verification: all existing tests green; bench gate ±2% on commit-path benches with no listener (one extra hook iteration that early-returns).

### Phase 2 — Public API

- Add `pub(all) enum MemoEvent` (placement: `cells/memo_event.mbt`, in `cells/`).
- Add `pub fn Runtime::on_memo_event` and `pub fn Runtime::clear_memo_event_listener`.
- Wire to `EventBroadcastPhaseHook.listener`.
- Add `Runtime::on_memo_event` and `Runtime::clear_memo_event_listener` accessors to `.mbti`.

Verification: `moon info && moon fmt` produces only the expected `.mbti` additions. No existing API removed.

### Phase 3 — Tests + docs

- Whitebox tests: insertion-order guarantee with accumulator + event hook coexisting; lifecycle bracketing under success/abort; HybridMemo coverage; no events for green-path verification.
- Drain-protocol tests: events buffer during nested recomputes and drain only when the outermost tracking stack becomes empty; a listener that calls `Memo::get` does not pollute a parent dep frame (because no parent frame exists at drain time); a listener that calls `Signal::set` works and the recursive recompute's events drain after the outer drain completes.
- Driver-facing test: register a listener, run a small graph, assert event sequence.
- Update `docs/api-reference.md` with `MemoEvent` + `Runtime::on_memo_event`.
- Update `docs/cookbook.md` with one recipe ("animated graph visualization") and one recipe ("async event logging").
- Brief addition to `docs/getting-started.md` only if it fits naturally; not load-bearing.

## Verification

| Check | Requirement |
|---|---|
| `moon test` | All existing tests + new event-hook tests green |
| `moon info && moon fmt` | New public API surfaces in `.mbti`; no unintended diff |
| `moon bench --release` on `tests/bench_test.mbt` | Commit-path benches with no listener within ±2%; with listener (single trivial callback) within ±5% |
| `scripts/check-engine-isolation.sh` | Green |
| Codex pre-implementation | Event shape + timing capture |
| Codex post-implementation | The hook impl + error stringification path |
| Whitebox test: lifecycle bracketing | Every `EnteringCompute` paired with `Completed` or `Aborted`; no orphans |
| Whitebox test: hook ordering | Accumulator hook runs before event hook (insertion order at `Runtime::new`) |
| Driver test | End-to-end event-sequence assertion |

## Risks

| Risk | Mitigation |
|---|---|
| Listener callback throws / aborts | Document: "callbacks must not abort or raise. Abort behavior is `abort()` semantics — uncatchable. Raise behavior may corrupt commit-phase state. Drivers must handle their own errors inside the callback." Add whitebox test that an abort inside the callback is the user's problem, not the framework's |
| Listener callback is slow | Documented as user-owned concern. Drivers wanting cheap callbacks enqueue events into an `@aqueue.Queue` and drain async per the async ADR |
| Clock unavailable on some target | `elapsed_ns` falls back to 0; document as "best-effort." Drivers can supplement with their own clock |
| Error stringification leaks internals | Pick a stable representation at commissioning (probably `error.to_string()`); document as informational, not contract |
| `revision` field decision changes later | Keep variant shape extensible. If using positional fields, prefer struct variants from the start. Document at commissioning |
| Backdating detection changes if `verified_at` semantics ever shift | Helper is a pure function over `MemoData` state; pinned by whitebox test |

## Trade-offs accepted

- **Single listener, not multi-listener.** Simpler API, matches existing `on_change` pattern. Drivers wanting fan-out enqueue inside the callback. Reopen if a real two-consumer case arrives.
- **Pull-memo events only.** No push-reactive, no effect, no signal-set, no fixpoint, no batch-commit events in this ADR. Each would be a separate hook surface; commission only when a driver names the need.
- **Sync callbacks.** Async drivers bridge via aqueue. Same trade as `Effect`-side async per the async ADR. Function-coloring contract preserved.
- **Hook always registered, even with no listener.** Costs one `is Some` check per recompute. Bench gate enforces the budget. Trade-off vs. conditional registration: simpler internal state, no insertion-order recompute.
- **Best-effort timing.** Drivers wanting guaranteed timing precision inject their own clock; the default uses whatever stdlib provides.

## Scope

**In scope of this ADR's PR (post T1b merge):**
- `MemoEvent` enum
- `Runtime::on_memo_event` / `Runtime::clear_memo_event_listener` public API
- `EventBroadcastPhaseHook` internal impl
- Monotonic timing capture (best-effort)
- Backdating detection helper
- Tests + docs as listed in phase 3

**Out of scope (deferred to future ADRs or owned by drivers):**
- Multi-listener support
- Push-reactive recompute events
- Signal-change events (already exist via `Signal::on_change`)
- Effect-fire events
- Fixpoint iteration events
- Batch-commit boundary events
- Snapshot API (point-in-time graph state capture)
- State restoration / replay API
- CRDT / event-graph-walker integration
- The visualization tool itself (canopy-side concern)
- Persistent caching using these events

## What this ADR retires

- The implicit assumption from the T1b ADR that the public observability API would be specified inside T1b. It is not — T1b is internal scaffolding, this ADR is the driver-facing API.
- Any future proposal to expose `MemoCommitPhase` as a `pub` trait. Drivers register callbacks, not trait impls.

## What this ADR explicitly does not retire

- The driver-gate principle for *other* event surfaces (signal / push / effect / fixpoint / batch). Adding those is each its own ADR with its own driver.
- The T3 gate. Event observation does not require runtime-registry changes.
- The snapshot/restore / CRDT time-travel deferral. Those remain open questions for when event-graph-walker integration arrives.
