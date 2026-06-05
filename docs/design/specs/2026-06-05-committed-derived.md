# `CommittedDerived` for fallible authoring pipelines

**Status:** Proposed

**Date:** 2026-06-05

**Parent issue:** [#212](https://github.com/dowdiness/incr/issues/212)

**Related:** [Honest Read-Error Ownership](2026-05-28-honest-read-error-ownership.md), [Public API Ideal Naming](../../decisions/2026-05-21-public-api-ideal-naming.md), [ReachableDerived deferred differentiation](https://github.com/dowdiness/incr/issues/124)

## Goal

Add a generic target-facade primitive for authoring/editor pipelines that compute
fallible candidates but only advance their accepted semantic state after a
caller-defined success condition:

```text
current inputs
  -> fallible candidate parse/projection/semantic/lowering result
  -> success: commit the accepted semantic value
  -> failure: expose current diagnostics while retaining the previous commit
```

This is a semantic-state primitive, not a UI-tree retention model. It exists so
callers can keep current diagnostics honest without destroying the last accepted
semantic value that downstream UI, preview, or indexing stages still need.

## Drivers

Two downstream systems already hand-write this pattern:

- **Canopy** projection pipelines keep text as the current truth while retaining
  a reconciled projection tree for UI continuity and structural identity. Today
  `core/projection_memo.mbt` keeps a mutable previous projection reference around
  the generic projection memo chain.
- **MoonDsp** Mini authoring keeps the last successful `PatternDoc` while current
  source edits may fail parsing. Its `MiniAuthoringPipeline` uses a mutable
  `previous` document so parse errors can surface without discarding stable
  subtree IDs and lowering-cache reuse.

The underlying need is broader than either domain: authoring code often needs
both **current candidate state** and **last committed semantic state**.

## Naming

Use `CommittedDerived` for the first design.

Rejected names:

- `LastGoodDerived` — understandable in product docs, but `good` is vague and
  too domain-colored for a generic library API.
- `RetainedDerived` — describes the storage symptom but not the lifecycle rule;
  it can also be confused with retained-mode UI terminology.
- `ValidatedDerived` — close, but it emphasizes validation rather than the
  commit/acceptance boundary.

`CommittedDerived` names the important rule: a candidate is computed from current
inputs, but only accepted candidates become the committed value. If `commit` is
found to conflict too strongly with CRDT/document vocabulary in downstream code,
`AcceptedDerived` is the fallback name to revisit before implementation.

## Non-goals

- Do not put Canopy `NodeId`, MoonDsp `GraphNodeId` / `PatternNodeId`, parser
  diagnostics, source spans, graph templates, or UI concepts in `incr`.
- Do not move Loom projection identity helpers into `incr`. Loom/source
  projection may allocate and realign stable IDs; `CommittedDerived` only owns
  success-gated derived state.
- Do not change default `Derived` semantics.
- Do not imply that parser/projection/lowering should run in audio callbacks or
  UI event handlers that require strict latency. This is authoring/control-side
  state.
- Do not use this as justification for per-node reactive granularity. Start with
  coarse stages; use `DerivedMap` only when measurements justify it.

## Conceptual model

A `CommittedDerived[V, E]` has two observable channels:

```text
current result      Result[V, E]      // always reflects current inputs
committed value     V?                // last accepted value, if any
```

A recomputation follows this state machine:

| Previous committed value | Candidate result | New committed value | Status |
| --- | --- | --- | --- |
| `None` | `Err(e)` | `None` | `NoCommit` |
| `None` | `Ok(v)` | `Some(v)` | `CommittedChanged` |
| `Some(old)` | `Err(e)` | `Some(old)` | `RetainedDueToError` |
| `Some(old)` | `Ok(v)` where `v == old` | `Some(old)` | `CommittedUnchanged` |
| `Some(old)` | `Ok(v)` where `v != old` | `Some(v)` | `CommittedChanged` |

The current `Err(e)` is not hidden by retaining a committed value. A consumer
that reports diagnostics must observe the current channel. A consumer that needs
semantic continuity may observe the committed channel.

## Proposed surface sketch

Exact names are intentionally provisional, but the target facade should look
like a normal `incr` handle rather than a domain pipeline object.

```moonbit
pub struct CommittedDerived[V, E]

pub(all) enum CommitStatus {
  NoCommit
  CommittedChanged
  CommittedUnchanged
  RetainedDueToError
}

pub struct CommittedSnapshot[V, E] {
  current : Result[V, E]
  committed : V?
  status : CommitStatus
}
```

Candidate constructors:

```moonbit
// Build from a noraise domain-fallible compute. Domain failures are values.
pub fn[V : Eq, E : Eq] CommittedDerived::CommittedDerived(
  rt : Runtime,
  compute : () -> Result[V, E],
  label? : String,
) -> CommittedDerived[V, E]

// Build from an existing candidate derived stage.
pub fn[V : Eq, E : Eq] CommittedDerived::from_candidate(
  candidate : Derived[Result[V, E]],
  label? : String,
) -> CommittedDerived[V, E]

// Scope-owned convenience, mirroring Scope::derived.
pub fn[V : Eq, E : Eq] Scope::committed_derived(
  self : Scope,
  compute : () -> Result[V, E],
  label? : String,
) -> CommittedDerived[V, E]
```

Observation methods:

```moonbit
pub fn[V, E] CommittedDerived::current(
  self : CommittedDerived[V, E],
) -> Result[V, E]

pub fn[V, E] CommittedDerived::committed(
  self : CommittedDerived[V, E],
) -> V?

pub fn[V, E] CommittedDerived::snapshot(
  self : CommittedDerived[V, E],
) -> CommittedSnapshot[V, E]

pub fn[V, E] CommittedDerived::watch_snapshot(
  self : CommittedDerived[V, E],
) -> Watch[CommittedSnapshot[V, E]]

pub fn[V, E] CommittedDerived::watch_committed(
  self : CommittedDerived[V, E],
) -> Watch[V?]
```

Open naming question: whether read-like methods should be named `read_current`,
`read_committed`, and `read_snapshot` to make clear that they are outside-graph
reads. The first implementation should follow the final read-channel policy in
`Derived`/`Watch` at that time.

## Implementation direction

The likely implementation is a small wrapper around ordinary cells:

```text
candidate : Derived[Result[V, E]]
snapshot  : Derived[CommittedSnapshot[V, E]]
committed : Derived[V?]
```

`snapshot` owns the state transition. It reads `candidate` inside its compute
closure and updates private retained state only when the candidate is `Ok(v)` and
`v` differs from the previous committed value. `committed` projects the committed
part out of `snapshot`; ordinary equality/backdating should prevent downstream
committed-only consumers from observing changes when only the current diagnostic
changed.

Because `snapshot` must read its own previously committed value during compute,
this is a self-referencing pattern. The concrete mechanism for holding and
accessing that retained state is an implementation choice deferred to the
stage-2 spike (see [Implementation stages](#implementation-stages)); the design
fixes only the observable transition rules in the state machine above, not how
the previous value is stored.

This mirrors the hand-written pattern downstream projects already use, but makes
its lifecycle and read channels explicit.

### Backdating and revisions

`V : Eq` and `E : Eq` are required in v1 so the candidate and snapshot can use
normal backdating. `V : Eq` drives the committed-value equality check in the
state machine (`v == old`); `E : Eq` lets the current channel backdate when an
error repeats (`Err(e1)` then `Err(e2)` with `e1 == e2`), so current-result
observers are not woken for an unchanged diagnostic. A no-backdate constructor
can be considered later if a caller has non-`Eq` diagnostics or expensive
comparisons.

The commit revision/count should advance only when the committed value actually
changes, not on every successful candidate recomputation. This matters for
source edits that parse successfully but produce the same semantic value.

Open design choice:

- expose `committed_changed_at() -> Revision`, mirroring `Derived::changed_at`,
  for the committed projection; or
- expose a simpler `commit_count() -> Int64` that increments only on committed
  value changes.

`Revision` is more consistent with existing `incr` vocabulary, but callers must
not confuse it with a domain document revision.

### Error ownership

`CommittedDerived` should build on the honest-read split:

- graph/read failures remain in the read channel (`ReadError`);
- domain failures remain in the computed value (`Result[V, E]`);
- defects still abort/raise `Failure` only where ordinary `Derived` would.

The constructor should be noraise like `Derived::fallible` so recoverable domain
errors cannot accidentally become uncaught compute failures.

A `ReadError` raised while reading the underlying `candidate` cell (a `Cycle` or
`Disposed`, never a domain `E`) is a structural read failure, not a candidate
outcome. It does not drive the commit state machine: no `NoCommit` /
`RetainedDueToError` transition occurs, and the internally retained committed
value is left untouched. The `ReadError` instead surfaces on the read channel of
`current`, `committed`, and `snapshot` exactly as it would for an ordinary
`Derived`, and clears once the graph recovers — at which point the state machine
resumes from the retained committed value. This keeps the read-channel error
(`ReadError`) and the domain error (`E` inside `Result`) on separate channels,
as the honest-read split intends.

## Interaction with Loom projection identity

Loom may own projection identity realignment:

```text
source + edit + current CST
  -> ProjectionLeaf[]
  -> ProjectionIdentityTracker::realign_success(...)
  -> semantic projection with domain IDs
```

`CommittedDerived` owns only the later acceptance boundary:

```text
Result[semantic projection with IDs, Diagnostic]
  -> CommittedDerived
  -> commit only after parse + projection + lowering succeed
```

If semantic lowering fails after projection identity preview succeeds, the
projection identity baseline must not advance. That rule belongs to the caller or
Loom tracker; `CommittedDerived` can help by making the final success gate
explicit, but it must not allocate IDs or commit projection baselines itself.

## Canopy-shaped example

```text
Input[String]
  -> Derived[ParseSnapshot]
  -> Derived[Result[Projection, Diagnostic]]
  -> CommittedDerived[Projection, Diagnostic]
  -> Derived[Map[NodeId, ProjNode]]       // reads committed projection
  -> Derived[SourceMap]                   // reads committed projection
  -> Derived[DiagnosticSet]               // reads current result
```

The source text and diagnostics remain current. Registry/source-map consumers can
choose whether they need the current candidate or the last committed projection.

## MoonDsp-shaped example

```text
Input[String]
  -> Derived[Result[PatternDoc, String]]
  -> CommittedDerived[PatternDoc, String]
  -> Derived[Result[PatternSnapshot, String]]
```

A parse error reports the current error while preserving the last committed
`PatternDoc` for editor preview or last-good playback policy. Runtime parsing and
audio processing remain independent of this authoring-only pipeline.

## Relationship to `ReachableDerived`

This does not trigger the deferred `ReachableDerived` differentiation by itself.
`CommittedDerived` solves success-gated semantic retention. `ReachableDerived`
issue #124 is about eager-when-reachable behavior and observable changed/clean
sets for bounded visible regions.

They may compose later:

```text
CommittedDerived[Projection, Diagnostic]
  -> registry/source-map branches
  -> ReachableDerived viewport / inspector branches
```

## Implementation stages

1. **Docs/spec only.** Land this design with no public API.
2. **Spike tests in `cells/` or `tests/`.** Implement the smallest private helper
   or local test fixture that validates the state machine above.
3. **Public target facade.** Add `CommittedDerived`, `CommittedSnapshot`, and
   `CommitStatus` only after the stateful-cell/backdating behavior is proven.
4. **Scope and docs integration.** Add `Scope::committed_derived`, API reference
   docs, and checked examples.
5. **Downstream validation.** Replace one manual pattern in Canopy or MoonDsp and
   confirm tests still prove current diagnostics and last committed semantics.

## Acceptance tests for an implementation

When the API ships, tests should cover:

- failure before first success leaves `committed == None`;
- first success creates `Some(value)`;
- failure after success exposes current `Err` while preserving committed value;
- later changed success replaces the committed value;
- later equal success does not advance the committed changed revision/count;
- committed-only downstream consumers do not observe current-error churn;
- snapshot/current consumers do observe current-error changes;
- `Scope` + `Watch` ownership survives `Runtime::gc()` according to the normal
  persistent-watch rule;
- `Runtime::batch` with several input changes publishes one coherent candidate
  and committed state.

## Open questions

- Should `CommittedDerived::from_candidate` be v1, or should v1 only expose a
  constructor that owns its candidate compute?
- Should the committed projection expose `Revision` or a simple commit counter?
- Should there be a no-backdate / no-`Eq` variant, and if so should it be public
  or internal only?
- Should `snapshot` include the previous committed value in addition to the new
  committed value for consumers that want transition effects? (Tentative
  default: no — transition effects belong at `Effect` / observer boundaries.)
- Should `CommittedDerived` live in `cells/` directly, or should it start as an
  example-local helper until a downstream replacement proves the public shape?
