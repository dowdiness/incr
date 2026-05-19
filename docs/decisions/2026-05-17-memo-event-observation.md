# ADR: `Runtime::on_memo_event` — Public Commit-Phase Event Observation

**Date:** 2026-05-17 (amended same-day after Codex review of T1b plan)
**Status:** Accepted — implementation gated on T1b landing first
**Anchors:** [T1b (`MemoCommitPhase`)](2026-05-17-t1b-memo-commit-phase.md), [Async-at-the-edges](2026-05-17-async-at-the-edges.md)

**Amendments (2026-05-17, post-Codex):**
- §"Internal implementation": confirmed `backdated` detection via `cell.meta.changed_at < cell.verified_at` works correctly because T1b ADR was amended same-day to fire `after_success` *after* the cell-level epilogue. Without that timing fix, backdating would not have been detectable from the hook.
- §"Internal implementation": **buffer-and-flush** rather than inline listener dispatch. Per T1b's hook contract amendment, hooks must not call user code inline (typed memo cache not yet written, nested-recompute dep pollution, `recompute_inner.changed` decision depends on epilogue state). The `EventBroadcastPhaseHook` appends to an internal `pending_events` queue inside each hook method and drains at a safe point. See §"Drain protocol" below.
- §"Context" and §"Internal implementation": file placement is `cells/`, **not** `cells/internal/kernel/`. Same engine-isolation rule as T1b (kernel cannot import `cells/`, and `MemoCommitPhase` takes `rt : Runtime`).

**Amendments (2026-05-19, post-Codex commissioning review):** The three "deferred to plan" items at §"Three implementation details deferred to the plan" are resolved by this amendment block. Affected sections updated below in-place; this block records the deltas with rationale.

- §"Public API" — variant shape: switch from labelled-positional enum constructors to **struct-per-variant** (`MemoEnteringEvent` / `MemoCompletedEvent` / `MemoAbortedEvent` carried by enum variants). Forward-compatible field additions don't break driver match exhaustiveness. The semantic content table is updated to match.
- §"Public API" — error payload: change `Aborted.error` from `String` to `Error`. Three reasons: (1) `Error` is already in incr's public surface via `Runtime::batch_result -> Result[Unit, Error]`; the enum doesn't grow the public footprint. (2) Drivers get the typed value for pattern-matched error handling; stringification moves to the listener side. (3) Avoids running `to_string` in commit-path context. MoonBit's `Error::to_string` is the `%error.to_string` primitive (not arbitrary user-`Show` dispatch), so the original concern was overstated — but deferring to the listener still side-steps it entirely with no cost.
- §"Public API" — revision payload: split into `started_revision : Revision` on **all** terminal events (captured in `before_recompute`, stored with the timer, reused on the matched Completed/Aborted), plus `verified_at : Revision` and `changed_at : Revision` on `Completed`. Reasoning: (1) `rt.cell_info(id)` does NOT expose `current_revision` (verified against `cells/introspection.mbt:15` — only `changed_at` / `verified_at` are surfaced); the prior "available from cell_info anyway" claim was wrong and is removed. (2) `EnteringCompute.revision == Completed.revision` is NOT structurally guaranteed — `Signal::set_unconditional` advances revision via propagation (`cells/signal.mbt:222`) and is not currently guarded against an active tracking stack, so revision *can* advance during a compute closure. Capturing once at hook entry and threading it through is the only honest way to keep events bracketed. **Transaction grouping** (driver wanting "events from one batch") is explicitly NOT exposed via these fields — deferred to a future ADR for `BatchStart`/`BatchEnd` variants or batched delivery, when a driver names the need.
- §"Internal implementation" — clock source: `moonbitlang/core/bench.monotonic_clock_start / monotonic_clock_end` (added to `cells/moon.pkg` main import block; currently test/wbtest only). Wrap with private `capture_now() -> @bench.Timestamp` / `elapsed_ns_from(ts) -> Int64` to localize the awkward name. **No public clock-injection API** (`Runtime::new(clock~ : () -> Int64)` was considered and rejected — running user code on the commit path violates T1b's hook contract for the same reason inline listener dispatch does).
- §"Internal implementation" — `elapsed_ns` field documented as **best-effort monotonic elapsed nanoseconds; backend-resolution dependent**. Underlying clocks vary by target (native: timespec, exposed as µs precision; wasm: secs-f64 → µs; JS: `performance.now()` → µs). The `Int64` ns type is for consumer convenience, not a precision promise.
- §"Internal implementation" — **listener-mutation guard**: `Runtime::on_memo_event` and `Runtime::clear_memo_event_listener` `raise Failure` unless a **composite "no operation in flight" predicate** holds:

  ```
  phase is Idle
  && tracking.stack.is_empty()
  && batch.depth == 0
  && event_broadcast_hook.pending.is_empty()
  && !event_broadcast_hook.draining
  ```

  Three earlier attempts at the boundary were insufficient and rejected:
  - `tracking.stack.is_empty()` alone (too narrow): post-propagation on_change callbacks run with empty stack but buffered events.
  - `phase == Idle` alone (still too narrow per third-pass Codex review): `PropagationPhase` is `Idle | PushPropagating | InFixpoint | GarbageCollecting` (verified at `cells/internal/kernel/state.mbt:54`). Memo compute, `commit_batch` post-propagation, `commit_batch`'s on_change firing, and post-`run_fixpoint` publish all run with `phase == Idle` — the guard would fail open.
  - Combining `phase` and `tracking.stack` (still misses on_change windows).

  The composite predicate above covers all cases. The `pending.is_empty()` term is the key generalization: if events are buffered, an operation is in flight by definition, and listener mutation must wait. The `!draining` term forbids listener mutation from inside a listener callback itself (which would otherwise be the one user-code window where the predicate could simultaneously look idle yet have side effects). Mirrors the accumulator API's "called outside tracked context" defect class.
- §"Drain protocol" — drain-before-abort sites use a **direct** `event_broadcast_hook.drain()` call, **not** `drain_pending_events_if_idle()`. The idle-guarded helper returns early when `tracking.stack` is non-empty, which is exactly the case during nested aborts (`Memo::get_result` called from inside an outer memo's compute closure — outer frame remains, inner aborts). Stranding the event was the failure mode in the first-pass amendment. Justification for bypassing the idle guard at abort sites: control isn't returning to the outer frame — `abort()` is uncatchable — so the "listener shouldn't pollute an outer dep frame" rationale that normally requires `tracking.stack.is_empty()` doesn't apply. The listener observes events with `tracking.stack` non-empty in this one path; document the exception in §"What user callbacks may and may not do".
- §"Drain protocol" — abort-site coverage extended beyond `Memo::get_result` to all public catch-to-abort sites: `Memo::get_untracked` (`cells/memo.mbt:292-293`), `MemoMap::get_result` (`cells/memo_map.mbt:93-95`), `HybridMemo::get_untracked` (`cells/hybrid_memo.mbt:109-110, :126-127`). Phase 1 audits the codebase for further sites that match the pattern. **Uncatchable `abort()` paths from outside the compute** (cycle detection, disposed-cell access, cross-runtime guards) do not trigger `after_abort` because they bypass `memo_force_recompute`'s catch arm. **`abort()` called from inside the compute closure** fires `before_recompute` but does NOT fire `after_abort` — `abort` is uncatchable so the catch arm at `cells/memo.mbt:429-440` is bypassed. The buffered `EnteringCompute` is the last record for that cell; the lifecycle-bracketing guarantee is weakened accordingly (see §"Event ordering and guarantees" §1, §7).
- §"Internal implementation": T1b ADR amended same-day to extend `MemoCommitPhase::after_abort` with an `Error` parameter. The hook captures `Error` (not a string) into the event payload; stringification is the listener's responsibility.

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
    EnteringCompute(e) => viewer.flash_cell(e.cell_id, color=Yellow)
    Completed(e) if e.backdated => viewer.dim_cell(e.cell_id)
    Completed(e) =>
      viewer.flash_cell(e.cell_id, color=Green, ms=e.elapsed_ns / 1_000_000)
    Aborted(e) =>
      viewer.flash_cell(e.cell_id, color=Red, tooltip=e.error.to_string())
  }
})
```

Same callback shape powers a CLI profiler (`top`-style rate of recomputes per memo), a test diagnostics tap ("which memos recomputed during this test?"), or an aqueue-bridged async event log per the async ADR's effect-side pattern.

## Public API

```moonbit
// cells/memo_event.mbt (placement firmed up 2026-05-19)

pub(all) struct MemoEnteringEvent {
  cell_id : CellId
  started_revision : Revision
}

pub(all) struct MemoCompletedEvent {
  cell_id : CellId
  elapsed_ns : Int64
  started_revision : Revision
  verified_at : Revision
  changed_at : Revision
  backdated : Bool
}

pub(all) struct MemoAbortedEvent {
  cell_id : CellId
  elapsed_ns : Int64
  started_revision : Revision
  error : Error
}

pub(all) enum MemoEvent {
  EnteringCompute(MemoEnteringEvent)
  Completed(MemoCompletedEvent)
  Aborted(MemoAbortedEvent)
}

// Debug derivation: NOT applied. MoonBit's `@debug.Debug` deriver does not
// recognize the `Error` supertype as a Debug-able field, and the auto-derived
// output would either fail to compile or fall through to a no-op. Drivers
// stringify on demand via `e.error.to_string()` (`Error::to_string` is the
// `%error.to_string` primitive — safe to call at any time). A manual `Show`
// impl on each struct that formats fields explicitly is an option for the
// implementation plan; not load-bearing.

// Both APIs raise `Failure` unless the runtime is genuinely between
// operations — see §"Listener mutation guard" for the composite predicate
// (phase + tracking stack + batch depth + pending buffer + drain reentry).
pub fn Runtime::on_memo_event(
  self : Runtime,
  f : (MemoEvent) -> Unit,
) -> Unit raise Failure

pub fn Runtime::clear_memo_event_listener(
  self : Runtime,
) -> Unit raise Failure
```

Four deliberate shapes:

- **Single listener per runtime**, replaces previous if any. Mirrors `Signal::on_change` / `Memo::on_change` exactly. Multi-listener support is deferred until a driver names two simultaneous consumers (rare; usually a fan-out happens inside the listener via a queue).
- **`pub(all) enum` with struct-per-variant payloads** so drivers can pattern-match all variants and adding fields later (e.g., a future `accumulator_pushes : Array[AccumulatorId]` on `Completed`) doesn't break exhaustive matches on existing call sites.
- **`(MemoEvent) -> Unit`** — sync, per the async ADR's coloring contract. Drivers who want async handling enqueue inside the sync callback (`@aqueue.Queue::put_nowait`).
- **Listener-mutation rejected from inside compute.** `on_memo_event` and `clear_memo_event_listener` are top-level operations; called mid-recompute they raise `Failure`. Prevents the timer-leak / broken-bracketing failure mode where a compute closure clears the listener between `before_recompute` and the matched terminal event.

The *semantic content* is fixed at commissioning (post 2026-05-19 resolution):

| Variant | Carries |
|---|---|
| `EnteringCompute` | `cell_id`, `started_revision` |
| `Completed` | `cell_id`, `elapsed_ns`, `started_revision`, `verified_at`, `changed_at`, `backdated` |
| `Aborted` | `cell_id`, `elapsed_ns`, `started_revision`, `error : Error` |

`started_revision` is captured in `before_recompute` and reused on the matched terminal event — drain-time `rt.core.revision.current_revision` is unreliable because listener-triggered `Signal::set` can advance revision between the buffered event and delivery, and `Signal::set_unconditional` (`cells/signal.mbt:222`) is not currently guarded against an active tracking stack so revision can advance mid-recompute. `verified_at` and `changed_at` are read off `MemoData` after the cell-level epilogue settles them; `backdated = changed_at < verified_at` is kept as a convenience derivation (driver code is cleaner with the bool). Note: `rt.cell_info(id)` exposes `changed_at` and `verified_at` (`cells/introspection.mbt:15`) but **not** runtime-wide `current_revision` — driver-side reconstruction of `started_revision` without it on the event payload is impossible. Transaction grouping (driver use case for "events from one batch") is **not** exposed via these fields — deferred to a future ADR for `BatchStart`/`BatchEnd` variants or batched delivery, when a driver names the need.

## Internal implementation

One new in-tree implementor of T1b's trait, plus a runtime-side drain protocol. Both live in `cells/`, not in `cells/internal/kernel/`.

Per T1b's hook contract, the hook **must not** call the user listener inline (typed memo cache not yet written; nested-recompute dep frame pollution; `recompute_inner.changed` decision can be perturbed). Instead, the hook **buffers** events into an internal queue and the runtime **drains** the queue at a safe point.

```moonbit
// cells/event_broadcast_hook.mbt

// Per-cell state between before_recompute and the matched terminal event.
// Captures the timer + revision once, regardless of listener changes after.
priv struct RecomputeStart {
  timer : @bench.Timestamp
  started_revision : Revision
}

priv struct EventBroadcastPhaseHook {
  mut listener : ((MemoEvent) -> Unit)?
  mut draining : Bool          // reentry guard for drain()
  active : @hashmap.HashMap[CellId, RecomputeStart]
  pending : Array[MemoEvent]
}

// --- Internal clock wrappers (localize the bench package name) ---
priv fn capture_now() -> @bench.Timestamp {
  @bench.monotonic_clock_start()
}
priv fn elapsed_ns_from(ts : @bench.Timestamp) -> Int64 {
  (@bench.monotonic_clock_end(ts) * 1000.0).to_int64()
}

priv impl MemoCommitPhase for EventBroadcastPhaseHook with before_recompute(
  self, rt, cell_id,
) {
  guard self.listener is Some(_) else { return }
  let start : RecomputeStart = {
    timer: capture_now(),
    started_revision: rt.core.revision.current_revision,
  }
  self.active.set(cell_id, start)
  self.pending.push(EnteringCompute({ cell_id, started_revision: start.started_revision }))
}

priv impl MemoCommitPhase for EventBroadcastPhaseHook with after_success(
  self, rt, cell_id,
) {
  // No active entry → before_recompute short-circuited (listener was None).
  // Do nothing on the terminal-event side either, keeping bracketing intact.
  let start = match self.active.get(cell_id) {
    Some(s) => s
    None => return
  }
  self.active.remove(cell_id)
  let elapsed_ns = elapsed_ns_from(start.timer)
  let cell = rt.get_memo_data(cell_id)
  let changed_at = cell.meta.changed_at
  let verified_at = cell.verified_at
  let backdated = changed_at.value < verified_at.value
  self.pending.push(Completed({
    cell_id,
    elapsed_ns,
    started_revision: start.started_revision,
    verified_at,
    changed_at,
    backdated,
  }))
}

priv impl MemoCommitPhase for EventBroadcastPhaseHook with after_abort(
  self, _rt, cell_id, error,
) {
  let start = match self.active.get(cell_id) {
    Some(s) => s
    None => return
  }
  self.active.remove(cell_id)
  let elapsed_ns = elapsed_ns_from(start.timer)
  self.pending.push(Aborted({
    cell_id,
    elapsed_ns,
    started_revision: start.started_revision,
    error,
  }))
}

// Called by Runtime::drain_pending_events_if_idle (normal drain sites) or
// directly (catch-to-abort sites — see §"Drain protocol").
// Reentry: if a listener triggers another operation that would normally
// drain, the inner drain returns immediately and the outer loop picks up
// the tail. Listeners cannot raise by type (`(MemoEvent) -> Unit` is
// non-raising), so no try/catch is needed around the listener invocation.
priv fn EventBroadcastPhaseHook::drain(self : EventBroadcastPhaseHook) -> Unit {
  if self.draining { return }
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

The hook is **always registered** at `Runtime::new`. `Runtime::on_memo_event` flips `listener` to `Some(f)`; `clear_memo_event_listener` flips it back to `None`. Both raise `Failure` unless the runtime is between operations — see §"Listener mutation guard" below for the composite predicate. When the listener is `None`, `before_recompute` short-circuits before installing an `active` entry, and the matched `after_success`/`after_abort` skip equally (no entry to look up) — no allocation, no buffer growth, lifecycle stays bracketed.

### Listener mutation guard

`on_memo_event` and `clear_memo_event_listener` `raise Failure` unless the runtime is genuinely between operations. "Genuinely between operations" is a composite predicate, not a single field check — `PropagationPhase` alone is insufficient because the runtime never enters a phase for top-level memo compute, batch-commit, or post-propagation on_change callback firing (`PropagationPhase` is `Idle | PushPropagating | InFixpoint | GarbageCollecting` per `cells/internal/kernel/state.mbt:54`).

Concretely:

```moonbit
priv fn Runtime::is_listener_mutation_safe(self : Runtime) -> Bool {
  self.core.phase is Idle
  && self.core.tracking.stack.is_empty()
  && self.core.batch.depth == 0
  && self.event_broadcast_hook.pending.is_empty()
  && !self.event_broadcast_hook.draining
}

pub fn Runtime::on_memo_event(self : Runtime, f : (MemoEvent) -> Unit) -> Unit raise Failure {
  guard self.is_listener_mutation_safe() else {
    fail("Runtime::on_memo_event cannot be called while an operation is in flight: " +
         "drain in progress, events buffered, batch open, recompute active, " +
         "or non-Idle phase (PushPropagating/InFixpoint/GarbageCollecting)")
  }
  self.event_broadcast_hook.listener = Some(f)
}
```

Each conjunct catches a window the others miss:

| Conjunct | Window it catches |
|---|---|
| `phase is Idle` | Push propagation, fixpoint iteration, gc sweep |
| `tracking.stack.is_empty()` | Inside any compute closure (memo / hybrid_memo / push reactive / effect) |
| `batch.depth == 0` | Inside `commit_batch`, between propagation and final on_change firing |
| `pending.is_empty()` | The post-propagation / post-fixpoint on_change-callback window where all three above are satisfied but events were buffered by the just-completed operation. If events are queued, an operation is by definition still in flight |
| `!draining` | Inside a listener callback itself (would otherwise be the lone reentry hole) |

The guarantee to drivers: **a listener registered at time T receives every event buffered after T, until explicitly cleared; explicit clearing happens only when there are no in-flight events to lose.** The defect class mirrors `Accumulator::push`'s "called outside tracked context" — listener registration is a between-operations action, not a callback action.

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
- **End of `Runtime::fixpoint`** — after `run_fixpoint` returns and the datalog publish phase completes. Push reactives created during publish can read memos (which buffer events), and the publish phase runs with `phase` already back to `Idle` (`run_fixpoint` exits `InFixpoint` before publication — see `cells/datalog_fixpoint.mbt:113`), so the post-fixpoint window has the exact "looks idle but events pending" shape that motivates the composite listener-mutation guard.
- **Raising-API error-exit** — if a public read API `raise`s a catchable `Failure` (not abort), buffered events stay in `pending`. They flush at the next drain-eligible operation. This is documented behavior, not a missed drain: the caller has the typed `Failure` in hand and can choose to retry, log, or terminate. The known cases are `Memo::accumulated` and `Memo::accumulated_result` (which call `ensure_computed_untracked` → `force_recompute`, and re-raise on inner `raise`). If a driver wants guaranteed delivery in the face of catchable failures, it must follow the failing call with any drain-eligible operation (e.g., a no-op `Memo::get` on a known-stable cell, or a `commit_batch` of an empty batch). Future-work tracking: if a driver names this as a real pain point, add direct drain at the raise sites.
- **Direct drain at public catch-to-abort sites** — *not* via the idle-guarded helper. These are the points where a memo's compute `raise`s, the inner `memo_force_recompute` catch arm fires `after_abort` (buffering `Aborted`), and the public-API wrapper then translates the propagating raise into an uncatchable `abort()`. The buffered event would be stranded if drain were idle-guarded, because `tracking.stack` may still hold an *outer* compute frame (nested case: outer memo's compute closure called inner memo's get path; inner aborts; outer is still on the stack). The audit covers all such sites:
  - `Memo::get_result` catch arm at `cells/memo.mbt:207-209`
  - `Memo::get_untracked` at `cells/memo.mbt:292-293`
  - `MemoMap::get_result` at `cells/memo_map.mbt:93-95`
  - `HybridMemo::get_untracked` at `cells/hybrid_memo.mbt:109-110` and `:126-127`
  - Phase 1 audits the codebase for further sites matching the pattern `... catch { e => abort(...) }` at the public-API boundary.

  At each site, call `self.rt.event_broadcast_hook.drain()` directly, **immediately before** the `abort()` call. Justification for bypassing the idle guard: control isn't returning to the outer frame anyway — `abort()` is uncatchable, the program is dying. The listener-context-purity invariant ("listeners run outside any recompute") that motivates the idle guard for other drain sites doesn't apply here. The listener observes events with `tracking.stack` possibly non-empty in this one path; document the exception in §"What user callbacks may and may not do".

  **What `after_abort` does NOT cover**: uncatchable `abort()` from outside the compute (cycle detection, disposed-cell guards, cross-runtime guards) bypass `memo_force_recompute`'s catch arm and do not fire any hook; uncatchable `abort()` from *inside* the compute closure fires `before_recompute` (the EnteringCompute event is buffered) but does NOT fire `after_abort` (`abort` is uncatchable so the catch arm is bypassed). The first case leaves no record; the second produces an orphan EnteringCompute that the drain-before-abort site cannot rescue (no `Aborted` was ever buffered). Documented in §"Event ordering and guarantees" §1, §7.

The idle-guarded helper `Runtime::drain_pending_events_if_idle()` checks `tracking_stack.is_empty()` before invoking `event_broadcast_hook.drain()`. If the stack is non-empty (we're nested inside another framework operation), it returns without draining; the outer operation's drain call will pick up the events. This helper is used at **every drain site except the abort sites listed above**.

Equivalent invariant the drain protocol upholds: **drain whenever `tracking.stack.is_empty()` is about to be observed by user code, OR at a catch-to-abort site where the program is about to die anyway**.

### Reentry safety

`drain()` uses the `draining : Bool` guard for the case where a listener callback re-enters incr (calls `Signal::set`, `Memo::get`, etc.). Without the guard, the recursive read could see `tracking_stack.is_empty()` and try to drain again mid-iteration. The outer drain's `while !pending.is_empty()` loop ensures tail events buffered by reentrant operations are still flushed before returning.

**Listeners cannot raise by type.** The public API takes `(MemoEvent) -> Unit` — a non-raising function. MoonBit's type system rejects passing a raising function where a non-raising function is expected, so the listener-registered-then-raises scenario is impossible at the type boundary. `drain()` consequently does **not** need a try/catch around the listener invocation; the `draining` flag is set, the listener is invoked, and the flag is reset on the normal-return path:

```moonbit
priv fn EventBroadcastPhaseHook::drain(self : EventBroadcastPhaseHook) -> Unit {
  if self.draining { return }
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

The implementation plan should not add a try/catch under "defense in depth." If a future ADR widens the callback type to `(MemoEvent) -> Unit raise?` (polymorphic raise), revisit then with explicit raise-propagation semantics.

Note on `pending.clear()` when listener is `None`: by the listener-mutation guard, listener can only be set to `None` when `pending.is_empty()` already holds (the `pending.is_empty()` conjunct of `is_listener_mutation_safe()` enforces this). So the `pending.clear()` line inside `drain()` is effectively a no-op when entered through normal call paths — it's defensive only. The one path where it does something is: future hooks that haven't yet been added might fire `before_recompute` with the listener flipping to `None` mid-recompute... which can't happen under the current guard either. The line stays as a defense-in-depth marker; if a future refactor introduces a window where pending can accumulate post-clear, this branch ensures we don't replay stale events to a re-attached listener.

### What user callbacks may and may not do

Drained-event listeners run **outside** any memo recompute. They may:
- Call `Signal::get`, `Memo::get_result`, `Runtime::cell_info` — reads land outside any tracking frame, recorded as top-level operations
- Enqueue events into an `@aqueue.Queue` for async handling per the async-at-the-edges ADR
- Call `Signal::set` — but be aware that this immediately bumps the revision and may trigger another recompute cycle while still inside the outer call's stack. Document as "supported but expensive."

They **must not**:
- Call `abort()` — uncatchable; aborts the drain mid-event and the process dies. Listener must not call `abort` or anything that calls it (e.g., reading a disposed cell).
- `raise` — the public callback type `(MemoEvent) -> Unit` is non-raising. MoonBit's type system rejects raising functions at registration. Listeners must handle their own errors internally (e.g., with `try?` and logging).

### Exception: listeners invoked at catch-to-abort drain sites

The drain protocol's catch-to-abort drain sites (see §"Drain protocol") invoke the listener via a **direct** `drain()` call, not the idle-guarded helper. In this single case, the listener may observe an `Aborted` event with **`tracking.stack` non-empty** — there is an outer compute frame still on the stack (the one whose `Memo::get*` call is about to translate the inner raise into `abort()`). Additional restrictions apply only in this context:

- Listener reads of memos (`Memo::get`, `Signal::get`) record into the outer frame's dep set. This is normally a contract violation (listeners are supposed to run outside any recompute), but here the outer frame is about to die — its dependency record will never be consumed. **Trade-off accepted:** drivers receive the `Aborted` event before the abort; the corrupted-but-doomed outer dep record is invisible from outside.
- Listener-triggered `Signal::set` / runtime mutation: **post-abort runtime state and external side effects from such calls are user-owned and undefined.** Normal MoonBit code abort()s immediately after the drain, so the revision bump and any propagation triggered by it run, then die. But: FFI hosts, test harnesses, and integrations that catch the abort somehow may observe partially-mutated state (a half-committed revision, partially-fired on_change callbacks, etc.). Listeners that perform external I/O (logging, snapshot writes) on the abort path must assume the runtime is dying and not depend on subsequent reads working. Read-only fan-out and pure side effects are safe.
- Everything else (synchronous fan-out to an `@aqueue.Queue`, simple logging, viewer state updates) is fine.

The implementation plan must explicitly mark these drain sites in the source as "abort-context drain — listener may observe outer frame."

**Three implementation details — resolved 2026-05-19 (Codex commissioning review).** Summarized here for historical record; see the 2026-05-19 amendments block at the top of this ADR for the full rationale.

1. **Monotonic clock source.** Resolved: `moonbitlang/core/bench.monotonic_clock_start / monotonic_clock_end`, added to `cells/moon.pkg` main imports; wrapped via private `capture_now()` / `elapsed_ns_from(ts)`. No public clock-injection API. `elapsed_ns` documented as best-effort, backend-resolution dependent.
2. **Error capture on abort.** Resolved: T1b's `MemoCommitPhase::after_abort` extended with an `Error` parameter (2026-05-19 amendment to T1b ADR). Hook captures `Error` typed value into `MemoAbortedEvent.error`; stringification is the listener's responsibility. Drop-in change to `AccumulatorCommitHook::after_abort` (`_e : Error` ignored).
3. **`was_backdated` detection.** Resolved: a pure read of cell state — `cell.meta.changed_at < cell.verified_at` — captured into `MemoCompletedEvent` as both the typed `changed_at`/`verified_at` fields and the `backdated : Bool` convenience flag. T1b's amended timing already ensures both are settled when `after_success` fires.

## Event ordering and guarantees

Documented contract drivers can rely on:

1. **Lifecycle bracketing — best-effort.** Every `EnteringCompute(c)` is followed by *at most* one terminal event (`Completed(c, ...)` or `Aborted(c, ...)`). Drivers should not assume "exactly one." The exception is the uncatchable-abort case (§7): if a compute closure calls `abort()` directly, `before_recompute` has already buffered `EnteringCompute`, but `after_abort` is never called (`abort` is uncatchable, so `memo_force_recompute`'s catch arm is bypassed). The drain-before-abort sites cannot rescue these — no `Aborted` event was ever buffered. The buffered `EnteringCompute` is the last record for that cell. Drivers needing universal termination signals must instrument separately.
2. **Same-revision ordering.** Within a single revision bump (e.g., one `Signal::set` outside a batch, or one `commit_batch`), events fire in pull-verification traversal order — dependency-first, then dependent. Drivers can use the order to reconstruct the recompute tree.
3. **Atomicity vs. await.** Because callbacks are sync (per the async ADR), the entire `EnteringCompute → Completed/Aborted` window for one cell is uninterruptible by another task.
4. **HybridMemo coverage.** Events fire for both `Memo` and `HybridMemo` recomputes — they share the same commit path. Drivers cannot distinguish from the event alone; they can call `rt.cell_info(id)` if they need to know the cell kind.
5. **No events for green-path verification.** When `pull_verify` short-circuits via the root-durability shortcut or per-dep durability shortcut, no compute closure runs and no events fire. This is intentional — events are about recompute activity, not verification activity. A future ADR could add a separate `VerifyEvent` stream if drivers ask for it.
6. **No nesting.** A memo's recompute can read other memos, which may trigger their own recomputes inside the same enclosing `EnteringCompute`. Events for the inner recomputes interleave with the outer `EnteringCompute`/`Completed` pair. Drivers reconstructing the call tree must track the implicit stack (each `EnteringCompute` pushes; each `Completed`/`Aborted` pops).
7. **Only catchable raises produce `Aborted` events.** Uncatchable `abort()` paths — cycle detection, disposed-cell access, cross-runtime guards, `abort()` called inside a compute closure, the fatal-error abort at `Memo::get_result:208` itself — bypass `memo_force_recompute`'s catch arm and do not fire `after_abort`. The viz-tap covers compute-time `raise` (and the drain at `Memo::get_result:207-209` guarantees that `Aborted` reaches the listener before the surrounding `abort()` fires). Drivers needing universal failure observation must instrument separately (e.g., wrap their `Memo::get*` calls).
8. **Revision fields are independent, not redundant.** `EnteringCompute.started_revision` is captured at `before_recompute`; `Completed.verified_at` is read post-epilogue; `Completed.changed_at` reflects the actual last-changed timestamp (possibly older than `verified_at`). The three values can differ: a compute closure that calls `Signal::set_unconditional` advances `current_revision` mid-compute, so `started_revision < verified_at` is observable. Drivers reconstructing transaction boundaries should rely on `started_revision`, not `verified_at`.
9. **Nested `started_revision` may be non-monotonic relative to call-tree nesting.** When an outer compute closure advances revision (via `Signal::set_unconditional`) *before* reading an inner memo, the inner memo's `EnteringCompute.started_revision` is *larger* than the outer memo's `EnteringCompute.started_revision`. The relationship between outer and inner `started_revision` is "outer ≤ inner" rather than equality; drivers reconstructing a call tree via `started_revision` cannot use it as a tree-position indicator. The pairing structure (each `EnteringCompute` pushes onto the implicit driver-tracked stack; each terminal event pops) is the reliable way to recover nesting.

## Migration plan (when commissioned)

Single PR after T1b's PR has merged. Codex pre-implementation review of the event enum shape and the timing-capture approach.

### Phase 0 — T1b signature extension (in-PR prerequisite)

Before any viz-tap code lands, extend the `MemoCommitPhase` trait shipped by T1b (PR #52, commit `5788223`) to carry `Error` on `after_abort`. This is a 5-file mechanical change inside this PR (not a separate prior PR):

- `cells/memo_commit_phase.mbt`: change `after_abort(Self, Runtime, CellId) -> Unit` to `after_abort(Self, Runtime, CellId, Error) -> Unit`.
- `cells/accumulator_commit_hook.mbt`: update the existing `impl MemoCommitPhase for AccumulatorCommitHook with after_abort(self, rt, cell_id)` to `after_abort(self, rt, cell_id, _e)`; body unchanged (accumulator ignores the error).
- `cells/memo.mbt:432-434`: update the dispatch loop to pass `e` through (`hook.after_abort(self, cell_id, e)`).
- `cells/accumulator_commit_hook_wbtest.mbt:64`: whitebox-test impl that calls `after_abort` directly — update the call site to provide an `Error` argument.
- `cells/accumulator_restore_bench_wbtest.mbt:57`: benchmark that calls `after_abort` directly — same update.

Verification: all 566 existing tests green (no behavior change for the accumulator's `_e`-ignoring impl). T1b ADR amended same-day to record the signature change.

### Phase 1 — Internal hook + zero-listener wiring + drain sites

- Add `"moonbitlang/core/bench"` to `cells/moon.pkg`'s **main** import block (currently test/wbtest only). No downstream impact — bench is package-local.
- Add `cells/event_broadcast_hook.mbt` with `EventBroadcastPhaseHook` struct (per the §"Internal implementation" code block above): `active : @hashmap.HashMap[CellId, RecomputeStart]` for per-cell state, `pending : Array[MemoEvent]` buffer, `draining : Bool` reentry guard, and `mut listener` flipped by the public API. Private `capture_now()` / `elapsed_ns_from(ts)` clock wrappers. Drain helper with `while !pending.is_empty()` loop for tail flush. **No try/catch** — listener type `(MemoEvent) -> Unit` is non-raising; raising listeners cannot be registered (type-system rejection at `on_memo_event` call).
- Register at `Runtime::new` with `listener: None`. Add typed field `priv event_broadcast_hook : EventBroadcastPhaseHook` on `Runtime`, mirroring the `accumulator_commit_hook` pattern from T1b. Register the same object in `commit_hooks`.
- Add `priv fn Runtime::drain_pending_events_if_idle()` helper that checks `tracking_stack.is_empty()` and then calls `event_broadcast_hook.drain()`.
- Add **idle-guarded** drain calls at the safe points enumerated in §"Drain protocol": all public read APIs (`Memo::get*`, `HybridMemo::get*`, `MemoMap::get*`, `Memo::accumulated*`, `Observer::get`, `Runtime::read*`), end of `Signal::set` when outside a batch, end of `commit_batch` (after on_change firing per §"Drain protocol"), end of `Runtime::gc`. These call `Runtime::drain_pending_events_if_idle()`.
- Add **direct (non-idle-guarded)** drain calls at the public catch-to-abort sites listed in §"Drain protocol": `Memo::get_result:207-209`, `Memo::get_untracked:292-293`, `MemoMap::get_result:93-95`, `HybridMemo::get_untracked:109-110, 126-127`. These call `self.rt.event_broadcast_hook.drain()` directly, immediately before the `abort()` call. Phase 1 audits the codebase for further catch-to-abort sites at public-API boundaries and adds drain calls symmetrically.
- Verify no behavior change with zero listener attached.

Verification: all existing tests green; bench gate ±2% on commit-path benches with no listener (one extra hook iteration that short-circuits when listener is `None` and no `active` entry exists).

### Phase 2 — Public API

- Add `cells/memo_event.mbt` with `pub(all) struct MemoEnteringEvent`, `pub(all) struct MemoCompletedEvent`, `pub(all) struct MemoAbortedEvent` (per §"Public API" code block), and `pub(all) enum MemoEvent` wrapping them.
- **Do not** apply `derive(Debug)` on the event structs or wrapping enum. MoonBit's `@debug.Debug` deriver does not recognize the `Error` supertype, so deriving would either fail to compile or produce unhelpful fall-through output. Drivers stringify on demand via `e.error.to_string()` (the `%error.to_string` primitive — safe to call, non-fallible). A manual `Show` impl that formats fields explicitly is an option only if a driver later names default log-rendering as a need.
- Add `pub fn Runtime::on_memo_event(...) -> Unit raise Failure` and `pub fn Runtime::clear_memo_event_listener(...) -> Unit raise Failure`. Both `fail()` unless the composite predicate `is_listener_mutation_safe()` holds (see §"Listener mutation guard"). Wire to `EventBroadcastPhaseHook.listener`.
- Add the new accessors to `.mbti` via `moon info`.

Verification: `moon info && moon fmt` produces only the expected `.mbti` additions (the 4 new public types + 2 new fns). No existing API removed.

### Phase 3 — Tests + docs

- Whitebox tests: insertion-order guarantee with accumulator + event hook coexisting; lifecycle bracketing under success/abort; HybridMemo coverage; no events for green-path verification.
- Drain-protocol tests: events buffer during nested recomputes and drain only when the outermost tracking stack becomes empty; a listener that calls `Memo::get` does not pollute a parent dep frame (because no parent frame exists at drain time); a listener that calls `Signal::set` works and the recursive recompute's events drain after the outer drain completes.
- **Abort-path tests**:
  - Top-level abort: a memo compute closure that `raise`s causes `Memo::get_result` to abort, and the listener observes the `Aborted` event before the abort fires.
  - **Nested abort**: outer memo's compute closure reads inner memo via `Memo::get_result`; inner aborts (catchable `raise`); listener observes `EnteringCompute(outer)`, `EnteringCompute(inner)`, `Aborted(inner)` — all three — before the outer `abort()` propagates. The direct drain (not idle-guarded) is what makes this work; an idle-guarded drain would strand the inner `Aborted` because the outer frame is still on `tracking.stack`.
  - Uncatchable abort inside compute: a memo compute closure that calls `abort()` directly produces `EnteringCompute` only — no terminal event. Lifecycle bracketing weakened per §"Event ordering and guarantees" §1, §7. Test asserts the observable behavior.
- **Listener-mutation guard tests** — five rejection paths, one per conjunct of `is_listener_mutation_safe()`:
  - Inside a memo / push-reactive / effect compute closure: `tracking.stack` non-empty → raises.
  - Inside a `commit_batch` body: `batch.depth > 0` → raises.
  - Inside `Runtime::gc`, `fixpoint`, or push propagation: `phase != Idle` → raises.
  - Inside a `Signal::on_change` callback after propagation buffered events (or a `commit_batch` global `on_change`): `pending` non-empty → raises. **This is the critical test** — it proves the predicate is wider than naive `tracking.stack.is_empty()` or `phase == Idle`, which both fail open in this window.
  - Inside a memo-event listener itself: `draining` true → raises.
- **Permissive test**: between operations (no compute active, no batch open, phase Idle, pending empty, not draining), both `on_memo_event` and `clear_memo_event_listener` succeed.
- Revision-capture test: a memo compute closure that calls `Signal::set_unconditional` (advancing revision mid-compute) — `EnteringCompute.started_revision < Completed.verified_at`; the event fields are consistent and don't claim equality the runtime can't honor.
- Driver-facing test: register a listener, run a small graph, assert event sequence.
- Update `docs/api-reference.md` with the four new public types + two new fns.
- Update `docs/cookbook.md` with one recipe ("animated graph visualization") and one recipe ("async event logging"). The §"What this enables" example in this ADR is a good seed for the visualization recipe.
- Brief addition to `docs/getting-started.md` only if it fits naturally; not load-bearing.

## Verification

| Check | Requirement |
|---|---|
| `moon test` | All existing tests + new event-hook tests green (Phase 0 accumulator-impl signature update must not regress the 566 existing tests) |
| `moon info && moon fmt` | The 4 new public types + 2 new fns surface in `.mbti`; no unintended diff (Phase 0 has no `.mbti` diff — trait is `priv`) |
| `moon bench --release` on `tests/bench_test.mbt` | Commit-path benches with no listener within ±2% of post-T1b baseline; with listener (single trivial callback) within ±5% |
| `scripts/check-engine-isolation.sh` | Green |
| Codex pre-implementation | Event shape + timing capture + drain-site coverage (commissioning review completed 2026-05-19) |
| Codex post-implementation | The hook impl + drain-before-abort path + listener-mutation guard |
| Whitebox test: lifecycle bracketing (best-effort) | Every `EnteringCompute` is followed by *at most* one terminal event. Catchable-raise paths produce paired `Aborted`; uncatchable-abort-during-compute paths produce orphan `EnteringCompute` (test the orphan case explicitly to pin the weakened §1 guarantee) |
| Whitebox test: hook ordering | Accumulator hook runs before event hook (insertion order at `Runtime::new`) |
| Whitebox test: top-level abort drain | A memo whose compute `raise`s delivers `Aborted` to the listener before `Memo::get_result`'s `abort()` fires |
| Whitebox test: nested abort drain | Outer memo reads inner; inner aborts; listener observes all three events (Entering outer, Entering inner, Aborted inner) before the outer abort propagates — proves direct drain (not idle-guarded) works under outer-frame-active conditions |
| Whitebox test: uncatchable abort during compute | A compute closure calling `abort()` directly produces `EnteringCompute` with no terminal event (documents the §1 / §7 weakening) |
| Whitebox test: listener-mutation guard | `on_memo_event` / `clear_memo_event_listener` raise `Failure` for each of the five rejection paths of `is_listener_mutation_safe()`: (a) inside a memo compute (tracking.stack), (b) inside a `commit_batch` body (batch.depth), (c) inside `gc`/`fixpoint`/push propagation (phase), (d) inside a `Signal::on_change` callback with events buffered (pending), (e) inside a memo-event listener itself (draining). Phase 3 §"Listener-mutation guard tests" enumerates all five |
| Whitebox test: revision capture | A compute that calls `Signal::set_unconditional` produces `started_revision < verified_at`; fields consistent |
| Driver test | End-to-end event-sequence assertion (no listener → quiet; listener attached → expected sequence) |

## Risks

| Risk | Mitigation |
|---|---|
| Listener callback throws / aborts | Listener type `(MemoEvent) -> Unit` is non-raising by MoonBit's type system; raising listeners cannot be registered. Listener `abort()` is uncatchable (it kills the process); listener must avoid `abort` and anything that calls `abort` (e.g., reading a disposed cell). Whitebox test asserts that listener `abort` is the user's problem; no test for raise (rejected at registration) |
| Listener callback is slow | Documented as user-owned concern. Drivers wanting cheap callbacks enqueue events into an `@aqueue.Queue` and drain async per the async ADR |
| Clock unavailable / low-resolution on some target | `elapsed_ns` falls back to 0 (worst case); precision varies by backend (native µs, wasm secs-f64 → µs, JS performance.now → µs). Document the `elapsed_ns` field as "best-effort monotonic elapsed nanoseconds; backend-resolution dependent" |
| Listener-mutation during framework operation | `on_memo_event` / `clear_memo_event_listener` raise `Failure` unless the composite predicate `is_listener_mutation_safe()` holds (phase Idle, tracking stack empty, batch depth 0, pending empty, not draining). Prevents the timer-leak / broken-bracketing / dropped-pending failure modes. Whitebox tests cover all five rejection paths |
| `Error` field on `MemoAbortedEvent` doesn't auto-Debug-derive | Resolved: do **not** apply `derive(Debug)` on the event structs / enum. MoonBit's `@debug.Debug` deriver does not recognize the `Error` supertype, and a fall-through would produce unhelpful output. Drivers stringify on demand via `e.error.to_string()` (the `%error.to_string` primitive). A manual `Show` impl that formats fields explicitly is an option for the implementation plan if log-friendly default rendering is later requested by a driver |
| Backdating detection changes if `verified_at` semantics ever shift | `MemoCompletedEvent` carries both `changed_at` and `verified_at` as typed fields; `backdated` is the convenience derivation. If the underlying semantics shift, the typed fields keep working and the bool can be updated in one place |
| Uncatchable-abort scope limit surprises drivers | Documented in §"Event ordering and guarantees" §7 (only catchable raises fire `after_abort`). Future ADR could add a separate uncatchable-abort tap; out of scope here |
| `bench` package's underlying clock API is `__moonbit_time_unstable` | Same dependency exists whether we import `@bench` or vendor the FFI. If the intrinsic changes, the upstream `@bench` package updates with it; vendoring would not insulate us |

## Trade-offs accepted

- **Single listener, not multi-listener.** Simpler API, matches existing `on_change` pattern. Drivers wanting fan-out enqueue inside the callback. Reopen if a real two-consumer case arrives.
- **Pull-memo events only.** No push-reactive, no effect, no signal-set, no fixpoint, no batch-commit events in this ADR. Each would be a separate hook surface; commission only when a driver names the need.
- **Sync callbacks.** Async drivers bridge via aqueue. Same trade as `Effect`-side async per the async ADR. Function-coloring contract preserved.
- **Hook always registered, even with no listener.** Costs one `is Some` check + one short-circuit per recompute. Bench gate enforces the budget. Trade-off vs. conditional registration: simpler internal state, no insertion-order recompute.
- **Best-effort timing.** No public clock-injection API (would run user code on the commit path, violating T1b's hook contract). `elapsed_ns` is backend-resolution dependent; drivers needing higher precision instrument outside the listener.
- **Listener registration is a top-level operation.** `on_memo_event` / `clear_memo_event_listener` raise `Failure` mid-compute rather than silently mutating state. Slight ergonomic cost (drivers can't toggle listening from inside their own compute closures), large correctness benefit (no broken bracketing).
- **`Error` capture, not stringification.** Listener stringifies. Trade-off: an additional non-trivial public type in the enum payload, but `Error` is already in `Runtime::batch_result`'s API surface, so no real growth.
- **Per-revision capture, not symmetric redundancy.** `EnteringCompute` carries only `started_revision`; `Completed` carries the post-epilogue truth (`verified_at`, `changed_at`) plus `backdated`. Drivers reconstructing transaction boundaries use `started_revision`, not `verified_at`. The redundancy of putting all four on every variant was rejected as overpaying for symmetry that drivers don't actually need.

## Scope

**In scope of this ADR's PR (post T1b merge, single PR):**
- T1b ADR signature amendment: extend `MemoCommitPhase::after_abort` with `Error` parameter (Phase 0)
- `pub(all) struct MemoEnteringEvent` / `MemoCompletedEvent` / `MemoAbortedEvent` + wrapping `pub(all) enum MemoEvent` (`cells/memo_event.mbt`)
- `Runtime::on_memo_event` / `Runtime::clear_memo_event_listener` public API, both `raise Failure` unless `is_listener_mutation_safe()` (composite predicate: phase Idle, tracking stack empty, batch depth 0, pending empty, not draining)
- `EventBroadcastPhaseHook` internal impl (`cells/event_broadcast_hook.mbt`), `priv` and `cells/`-resident per the engine-isolation rule
- `moonbitlang/core/bench` added to `cells/moon.pkg`'s main import block for the monotonic clock; private `capture_now()` / `elapsed_ns_from(ts)` wrappers
- Drain protocol with idle-guarded drain at normal sites plus **direct (non-idle-guarded) drain at all public catch-to-abort sites**: `Memo::get_result` (`memo.mbt:207-209`), `Memo::get_untracked` (`memo.mbt:292-293`), `MemoMap::get_result` (`memo_map.mbt:93-95`), `HybridMemo::get_untracked` (`hybrid_memo.mbt:109-110, :126-127`), plus end-of-`Runtime::fixpoint` drain (covers the post-publish window)
- Tests + docs as listed in Phase 3

**Out of scope (deferred to future ADRs or owned by drivers):**
- Multi-listener support
- Push-reactive recompute events
- Signal-change events (already exist via `Signal::on_change`)
- Effect-fire events
- Fixpoint iteration events
- Batch-commit boundary events (`BatchStart` / `BatchEnd` variants — the right shape for transaction grouping, gated on a driver naming the need)
- Universal abort observation (events for uncatchable `abort()` paths — out of scope per §"Event ordering and guarantees" §7)
- Verification-path events (no compute closure ran)
- Snapshot API (point-in-time graph state capture)
- State restoration / replay API
- CRDT / event-graph-walker integration
- The visualization tool itself (canopy-side concern)
- Persistent caching using these events
- Public clock-injection API (`Runtime::new(clock~ : () -> Int64)` rejected; not deferred)

## What this ADR retires

- The implicit assumption from the T1b ADR that the public observability API would be specified inside T1b. It is not — T1b is internal scaffolding, this ADR is the driver-facing API.
- Any future proposal to expose `MemoCommitPhase` as a `pub` trait. Drivers register callbacks, not trait impls.

## What this ADR explicitly does not retire

- The driver-gate principle for *other* event surfaces (signal / push / effect / fixpoint / batch). Adding those is each its own ADR with its own driver.
- The T3 gate. Event observation does not require runtime-registry changes.
- The snapshot/restore / CRDT time-travel deferral. Those remain open questions for when event-graph-walker integration arrives.
