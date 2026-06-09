# ADR: Composable Runtime Hooks

**Date:** 2026-06-09
**Status:** Accepted
**Issue:** [#210](https://github.com/dowdiness/incr/issues/210)
**Anchors:** [Memo Event Observation](2026-05-17-memo-event-observation.md),
[T1b `MemoCommitPhase`](2026-05-17-t1b-memo-commit-phase.md)
**Spec:** [docs/plans/2026-06-09-composable-runtime-hooks.md](../plans/2026-06-09-composable-runtime-hooks.md)

## Context

Two runtime-global hooks were singleton — a second registration silently
clobbered the first: `Runtime::set_on_change` (`RuntimeCore.on_change`) and
`Runtime::on_derived_event` (`EventBroadcastPhaseHook.listener`). The Memo Event
Observation ADR explicitly deferred multi-listener support ("Single listener, not
multi-listener … Reopen if a real two-consumer case arrives"). The Incremental
TEA renderer (PR #208) installing a runtime hook on top of an existing observer
is that two-consumer case: a browser/UI integration could not coexist with any
other observer on the same `Runtime`.

## Decision

Reopen and resolve the deferral. Make both hooks composable via one generic
`ListenerRegistry[F]` (kept `pub(all)` but internal in `cells/internal/kernel/`,
so not public API). The singleton APIs map onto a reserved slot in the registry
(replace-in-place, position-preserving) and stay source-compatible; new additive
APIs `add_on_change_listener` / `add_derived_event_listener` append composable
listeners and return a public `ListenerId` for idempotent `remove_*`. A
`ListenerId` pairs the originating `RuntimeId` with an allocation number from one
per-runtime counter shared across both registries: the counter rules out
cross-registry collisions within a runtime, the `RuntimeId` rules out
cross-runtime collisions (the bare counter alone would make every runtime's first
listener number 0). A mismatched `remove` — wrong registry or wrong runtime — is
therefore a harmless no-op.

Phase-safety stays **asymmetric, by design**:

- **on-change is unguarded.** It has no buffer/drain state and is read as a
  snapshot at one well-defined point, so mutating the listener set at any time is
  safe (it takes effect on the next fire). This preserves the existing
  `set_on_change` behavior and the I4 snapshot-before-fire invariant, extended
  from one handler to N.
- **derived-event keeps the idle guard.** The hook buffers events; registering
  while events are buffered raises the "replay buffered events?" ambiguity and
  mutating during drain is a concurrent-modification hazard. The existing
  `is_listener_mutation_safe()` composite predicate rejects both.

Ordering: on-change fires in registration order; derived-event is event-major
(every listener per event, in registration order, matching the ADR's
pull-traversal same-revision guarantee). The TEA renderer switches to the
additive APIs so mounting no longer clobbers a pre-existing hook.

## Consequences

- Multiple observers coexist on one runtime; removal is idempotent and id-keyed.
- Public surface grows by `ListenerId` and four `Runtime` methods; no existing
  API changed or removed; no trait bound widened.
- Unblocks TEA follow-ups #209 (unmount/dispose stores the returned `ListenerId`s)
  and #211 (keyed VDOM).
- Not addressed (still driver-gated per the Memo Event Observation ADR): push /
  effect / fixpoint / batch event surfaces, listener priorities, and the internal
  `RuntimeEvaluationEventHook` (trace/strategy, not user-facing).
