# `AcceptedDerived` for fallible authoring pipelines

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
  -> success: accept the candidate as the new value
  -> failure: expose current diagnostics while retaining the previous accepted value
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
both **current candidate state** and **last accepted semantic state**.

## Naming

Use `AcceptedDerived` for the first design.

Rejected names:

- `CommittedDerived` — the original working name, rejected because `commit` is
  already heavily loaded inside `incr` itself: the runtime's batch commit phase
  uses `commit_batch`, `commit_pending`, `commit_hooks`, `Committable`,
  `MemoCommitPhase`, and `AccumulatorCommitHook` (~160 identifier uses). A public
  `CommittedDerived` / `CommitStatus` / `commit_count` would collide with that
  vocabulary in the same namespace (`commit_count` reads as "number of batch
  commits", `CommitStatus` as batch-commit status), and `commit` also clashes
  with CRDT/document vocabulary in downstream consumers.
- `LastGoodDerived` — understandable in product docs, but `good` is vague and
  too domain-colored for a generic library API.
- `RetainedDerived` — describes the storage symptom but not the lifecycle rule;
  it can also be confused with retained-mode UI terminology.
- `ValidatedDerived` — close, but it emphasizes validation rather than the
  acceptance boundary.

Considered runner-up:

- `LatchedDerived` — `latch` is collision-free and is the precise term for
  "hold the last value, update only when an enable condition fires." Rejected
  only because it names the retention *mechanism* rather than the *success gate*
  that is the concept's reason for existing, and `latch` carries a
  concurrency-primitive connotation (`CountDownLatch`) in the wider ecosystem.

`AcceptedDerived` names the important rule: a candidate is computed from current
inputs, but only candidates that pass the success gate are *accepted* as the new
value. The name matches the conceptual vocabulary used throughout this spec
("success condition", "accepted value", "acceptance boundary") and is
collision-free in `incr`.

## Non-goals

- Do not put Canopy `NodeId`, MoonDsp `GraphNodeId` / `PatternNodeId`, parser
  diagnostics, source spans, graph templates, or UI concepts in `incr`.
- Do not move Loom projection identity helpers into `incr`. Loom/source
  projection may allocate and realign stable IDs; `AcceptedDerived` only owns
  success-gated derived state.
- Do not change default `Derived` semantics.
- Do not imply that parser/projection/lowering should run in audio callbacks or
  UI event handlers that require strict latency. This is authoring/control-side
  state.
- Do not use this as justification for per-node reactive granularity. Start with
  coarse stages; use `DerivedMap` only when measurements justify it.

## Conceptual model

An `AcceptedDerived[V, E]` has two observable channels:

```text
current result      Result[V, E]      // always reflects current inputs
accepted value      V?                // last accepted value, if any
```

A recomputation follows this state machine:

| Previous accepted value | Candidate result | New accepted value | Status |
| --- | --- | --- | --- |
| `None` | `Err(e)` | `None` | `NoAccept` |
| `None` | `Ok(v)` | `Some(v)` | `AcceptedChanged` |
| `Some(old)` | `Err(e)` | `Some(old)` | `RetainedDueToError` |
| `Some(old)` | `Ok(v)` where `v == old` | `Some(old)` | `AcceptedUnchanged` |
| `Some(old)` | `Ok(v)` where `v != old` | `Some(v)` | `AcceptedChanged` |

The current `Err(e)` is not hidden by retaining an accepted value. A consumer
that reports diagnostics must observe the current channel. A consumer that needs
semantic continuity may observe the accepted channel.

## Proposed surface sketch

Exact names are intentionally provisional, but the target facade should look
like a normal `incr` handle rather than a domain pipeline object.

```moonbit
pub struct AcceptedDerived[V, E]

pub(all) enum AcceptStatus {
  NoAccept
  AcceptedChanged
  AcceptedUnchanged
  RetainedDueToError
}

pub struct AcceptedSnapshot[V, E] {
  current : Result[V, E]
  accepted : V?
  status : AcceptStatus
}
```

Candidate constructors:

```moonbit
// Build from a noraise domain-fallible compute. Domain failures are values.
pub fn[V : Eq, E : Eq] AcceptedDerived::AcceptedDerived(
  rt : Runtime,
  compute : () -> Result[V, E],
  label? : String,
) -> AcceptedDerived[V, E]

// Build from an existing candidate derived stage.
pub fn[V : Eq, E : Eq] AcceptedDerived::from_candidate(
  candidate : Derived[Result[V, E]],
  label? : String,
) -> AcceptedDerived[V, E]

// Scope-owned convenience, mirroring Scope::derived.
pub fn[V : Eq, E : Eq] Scope::accepted_derived(
  self : Scope,
  compute : () -> Result[V, E],
  label? : String,
) -> AcceptedDerived[V, E]
```

Observation methods:

```moonbit
// Reads carry the read-error channel, matching the Derived/Watch honest-read
// split (`.read() -> Result[T, ReadError]`); each graceful read below also has a
// strict `*_or_abort` variant (omitted) that returns the inner value and aborts
// on ReadError. `current` nests two Results: the outer is the read channel
// (Cycle/Disposed), the inner is the domain candidate (Ok/Err).
pub fn[V, E] AcceptedDerived::current(
  self : AcceptedDerived[V, E],
) -> Result[Result[V, E], ReadError]

pub fn[V, E] AcceptedDerived::accepted(
  self : AcceptedDerived[V, E],
) -> Result[V?, ReadError]

pub fn[V, E] AcceptedDerived::snapshot(
  self : AcceptedDerived[V, E],
) -> Result[AcceptedSnapshot[V, E], ReadError]

// Persistent anchors; `Watch::read` already returns `Result[T, ReadError]`.
pub fn[V, E] AcceptedDerived::watch_snapshot(
  self : AcceptedDerived[V, E],
) -> Watch[AcceptedSnapshot[V, E]]

pub fn[V, E] AcceptedDerived::watch_accepted(
  self : AcceptedDerived[V, E],
) -> Watch[V?]
```

These read methods follow the established `Derived`/`Watch` honest-read contract:
a graceful `.read() -> Result[T, ReadError]` (shown above) plus a strict
`*_or_abort` variant that returns the inner value and aborts on `ReadError` (see
[Error ownership](#error-ownership) and the honest-read-ownership spec). The only
remaining open choice is cosmetic — whether to keep the bare `current` /
`accepted` / `snapshot` names or prefix them `read_*` to signal outside-graph
reads — to be settled against the final `Derived`/`Watch` surface at
implementation time.

## Implementation direction

The likely implementation is a small wrapper around ordinary cells:

```text
candidate : Derived[Result[V, E]]
snapshot  : Derived[AcceptedSnapshot[V, E]]
accepted  : Derived[V?]
```

`snapshot` owns the state transition. It reads `candidate` inside its compute
closure and updates private retained state only when the candidate is `Ok(v)` and
`v` differs from the previous accepted value. `accepted` projects the accepted
part out of `snapshot`; ordinary equality/backdating should prevent downstream
accepted-only consumers from observing changes when only the current diagnostic
changed.

Because `snapshot` must read its own previously accepted value during compute,
this is a self-referencing pattern. The previous accepted value must be held in
retained state *outside* the reactive dependency graph — it must not be modeled
as a derived self-dependency, which would form a cycle. The concrete mechanism
for holding and accessing that retained slot is an implementation choice deferred
to the stage-2 spike (see [Implementation stages](#implementation-stages)); the
design fixes the observable transition rules in the state machine above and this
no-self-edge constraint, not how the previous value is stored.

Because `Derived` is lazy (pull-based), the accept-advancing cell (`snapshot`)
must be driven on every candidate change — the acceptance state machine is a fold
over the candidate sequence and must observe every transition, so it cannot rely
on incidental pulls. Otherwise a transient successful candidate is lost: if a
consumer observes only the current channel across an `Ok(v)` edit (reading
`candidate` without forcing `snapshot`) and the accepted channel is first read
after a later `Err(e)`, the state machine never saw `Ok(v)` and the accepted
value wrongly remains at its prior value. The design therefore requires the
accept cell to be evaluated eagerly per candidate revision (e.g. a persistent
forcing `Watch` / `Effect`, or an eager cell); the exact forcing mechanism is
deferred to the stage-2 spike. As a corollary, observing the current channel must
not be able to bypass the acceptance — `current` is the candidate result, but its
delivery must not let candidate changes advance without the accept cell also
running.

The fold operates over *committed* candidate revisions, not intra-batch writes.
`Runtime::batch` coalesces multiple input writes into a single revision, so a
batch yields exactly one candidate transition (the post-commit candidate) and the
accept cell is evaluated exactly once per committed revision; intermediate values
written inside a batch are never separately accepted. The "every transition"
requirement above therefore means every *committed revision's* transition, which
is the granularity the lazy-pull hazard applies to.

This mirrors the hand-written pattern downstream projects already use, but makes
its lifecycle and read channels explicit.

### Backdating and revisions

`V : Eq` and `E : Eq` are required in v1 so the candidate and snapshot can use
normal backdating. `V : Eq` drives the accepted-value equality check in the
state machine (`v == old`); `E : Eq` lets the current channel backdate when an
error repeats (`Err(e1)` then `Err(e2)` with `e1 == e2`), so current-result
observers are not woken for an unchanged diagnostic. v1 therefore does **not**
support non-`Eq` `V` or `E`: a caller whose domain error is not cheaply `Eq` must
wrap it in an `Eq` keying type (or accept that the current channel will not
backdate). Lifting this via a no-backdate / no-`Eq` constructor is tracked as an
open question below, not part of the v1 surface.

The accept revision/count should advance only when the accepted value actually
changes, not on every successful candidate recomputation. This matters for
source edits that parse successfully but produce the same semantic value.

Invariant: the accepted projection's identity (and its `Revision` /
`accept_count`) is gated solely by `V`-equality on the accepted value.
Current-result churn — changing diagnostics, repeated errors, equal successful
recomputations — must never advance it.

Open design choice:

- expose `accepted_changed_at() -> Revision`, mirroring `Derived::changed_at`,
  for the accepted projection; or
- expose a simpler `accept_count() -> Int64` that increments only on accepted
  value changes.

`Revision` is more consistent with existing `incr` vocabulary, but callers must
not confuse it with a domain document revision.

### Error ownership

`AcceptedDerived` should build on the honest-read split:

- graph/read failures remain in the read channel (`ReadError`);
- domain failures remain in the computed value (`Result[V, E]`);
- defects still abort/raise `Failure` only where ordinary `Derived` would.

The constructor should be noraise like `Derived::fallible` so recoverable domain
errors cannot accidentally become uncaught compute failures.

A `ReadError` raised while reading the underlying `candidate` cell (a `Cycle` or
`Disposed`, never a domain `E`) is a structural read failure, not a candidate
outcome. It does not drive the acceptance state machine: no `NoAccept` /
`RetainedDueToError` transition occurs, and the internally retained accepted
value is left untouched. The `ReadError` instead surfaces on the read channel of
`current`, `accepted`, and `snapshot` exactly as it would for an ordinary
`Derived`, and clears once the graph recovers — at which point the state machine
resumes from the retained accepted value. This keeps the read-channel error
(`ReadError`) and the domain error (`E` inside `Result`) on separate channels,
as the honest-read split intends.

Concretely, the observation accessors carry this read channel (see the read
signatures under "Proposed surface sketch"): the graceful reads return
`Result[..., ReadError]` and the strict `*_or_abort` reads abort on `ReadError`.
While a `ReadError` is active, no `AcceptedSnapshot` is produced and the accepted
value, `status`, and accept revision are all unchanged — the read returns the
error in place of a value.

## Interaction with Loom projection identity

Loom may own projection identity realignment:

```text
source + edit + current CST
  -> ProjectionLeaf[]
  -> ProjectionIdentityTracker::realign_success(...)
  -> semantic projection with domain IDs
```

`AcceptedDerived` owns only the later acceptance boundary:

```text
Result[semantic projection with IDs, Diagnostic]
  -> AcceptedDerived
  -> accept only after parse + projection + lowering succeed
```

If semantic lowering fails after projection identity preview succeeds, the
projection identity baseline must not advance. That rule belongs to the caller or
Loom tracker; `AcceptedDerived` can help by making the final success gate
explicit, but it must not allocate IDs or advance projection baselines itself.

## Canopy-shaped example

```text
Input[String]
  -> Derived[ParseSnapshot]
  -> Derived[Result[Projection, Diagnostic]]
  -> AcceptedDerived[Projection, Diagnostic]
  -> Derived[Map[NodeId, ProjNode]]       // reads accepted projection
  -> Derived[SourceMap]                   // reads accepted projection
  -> Derived[DiagnosticSet]               // reads current result
```

The source text and diagnostics remain current. Registry/source-map consumers can
choose whether they need the current candidate or the last accepted projection.

## MoonDsp-shaped example

```text
Input[String]
  -> Derived[Result[PatternDoc, String]]
  -> AcceptedDerived[PatternDoc, String]
  -> Derived[Result[PatternSnapshot, String]]
```

A parse error reports the current error while preserving the last accepted
`PatternDoc` for editor preview or last-good playback policy. Runtime parsing and
audio processing remain independent of this authoring-only pipeline.

## Relationship to `ReachableDerived`

This does not trigger the deferred `ReachableDerived` differentiation by itself.
`AcceptedDerived` solves success-gated semantic retention. `ReachableDerived`
issue #124 is about eager-when-reachable behavior and observable changed/clean
sets for bounded visible regions.

They may compose later:

```text
AcceptedDerived[Projection, Diagnostic]
  -> registry/source-map branches
  -> ReachableDerived viewport / inspector branches
```

## Implementation stages

1. **Docs/spec only.** Land this design with no public API. ✅ Done (PR #213).
2. **Spike tests in `cells/` or `tests/`.** Implement the smallest private helper
   or local test fixture that validates the state machine above. ✅ Done (PR #214);
   fixture removed in stage 3 and its rows ported onto the public type.
3. **Public target facade.** Add `AcceptedDerived`, `AcceptedSnapshot`, and
   `AcceptStatus` only after the stateful-cell/backdating behavior is proven.
   ✅ Done — see [Stage 3 resolution](#stage-3-resolution-2026-06-06).
   `Scope::accepted_derived` landed here too.
4. **Docs integration.** API reference docs and checked `.mbt.md` examples.
5. **Downstream validation.** Replace one manual pattern in Canopy or MoonDsp and
   confirm tests still prove current diagnostics and last accepted semantics.

## Acceptance tests for an implementation

When the API ships, tests should cover:

- failure before first success leaves `accepted == None`;
- first success creates `Some(value)`;
- failure after success exposes current `Err` while preserving accepted value;
- later changed success replaces the accepted value;
- later equal success does not advance the accepted changed revision/count;
- each `AcceptStatus` transition is asserted explicitly: `NoAccept` (no prior,
  `Err`), `AcceptedChanged` (first `Ok`, and a later changed `Ok`),
  `AcceptedUnchanged` (equal `Ok`), `RetainedDueToError` (prior value exists,
  `Err`);
- a repeated equal error (`Err(e)` then `Err(e)` with `e == e`) backdates the
  current channel — current-result observers are not woken and the accept
  revision/count does not advance;
- a transient successful candidate is accepted even when no consumer reads the
  accepted channel between that success and a later failure — i.e. observing only
  the current channel across an `Ok(v)` edit, then reading `accepted` after a
  later `Err(e)`, still yields `Some(v)` (the acceptance advances without an
  intervening accepted read);
- accepted-only downstream consumers do not observe current-error churn;
- snapshot/current consumers do observe current-error changes;
- a candidate `ReadError` (`Cycle` / `Disposed`) while an accepted value exists
  leaves the retained accepted value, `status`, and accept revision unchanged,
  and surfaces the error on the read channel rather than a snapshot value;
- after a transient `ReadError` clears, the state machine resumes from the
  retained accepted value and transitions normally on the next candidate;
- `Scope` + `Watch` ownership survives `Runtime::gc()` according to the normal
  persistent-watch rule;
- `Runtime::batch` with several input changes publishes one coherent candidate
  and accepted state.

## Open questions

- Should `AcceptedDerived::from_candidate` be v1, or should v1 only expose a
  constructor that owns its candidate compute?
- Should the accepted projection expose `Revision` or a simple accept counter?
- Should there be a no-backdate / no-`Eq` variant, and if so should it be public
  or internal only?
- Should `snapshot` include the previous accepted value in addition to the new
  accepted value for consumers that want transition effects? (Tentative
  default: no — transition effects belong at `Effect` / observer boundaries.)
- Should `AcceptedDerived` live in `cells/` directly, or should it start as an
  example-local helper until a downstream replacement proves the public shape?

## Stage 3 resolution (2026-06-06)

Stages 1–3 shipped (`incr/cells/accepted_derived.mbt` + `accepted_derived_wbtest.mbt`,
re-exported from the root facade; the stage-2 spike fixture was removed and its
state-machine rows ported onto the public type). The open questions were resolved
as follows (design-validated by Codex before implementation):

- **`from_candidate` in v1:** yes. v1 ships `AcceptedDerived::AcceptedDerived`
  (owns-compute), `AcceptedDerived::from_candidate` (wraps an external candidate
  `Derived`; the candidate's lifecycle stays with the caller), and
  `Scope::accepted_derived`.
- **Accepted projection identity:** `accepted_changed_at() -> Revision`,
  implemented as the accepted-projection `Derived`'s `changed_at()`. Gating by
  `V`-equality falls out of ordinary backdating; no manual accept counter is
  kept. Documented as an `incr` graph `Revision`, not a domain document revision.
- **No-backdate / no-`Eq` variant:** deferred. v1 requires `V : Eq, E : Eq`.
- **Previous accepted value in `snapshot`:** no (transition effects belong at
  `Effect` / observer boundaries).
- **Location:** `incr/cells/` as a public target facade (the cross-repo
  Canopy/MoonDsp reuse driver rules out an example-local home, and stage 2
  proved the mechanism).
- **Read API:** outside-graph accessors `current` / `accepted` / `snapshot`
  (each `Result[…, ReadError]`) with strict `*_or_abort` variants, plus
  `watch_accepted() -> Watch[V?]`. `watch_snapshot` is deferred — `Watch`'s
  getter is constructed internally, so a `Watch` cannot compose the direct
  `candidate.read()` the read-error channel requires; the accessor methods carry
  it instead.

**ReadError channel — engine limitation found during stage 3.** The accessors
surface a candidate `ReadError` honestly by composing `candidate.read()`
directly; the eager fold reads `candidate.get()` gracefully and skips advancing
on `Err`, so a mechanism failure never drives the state machine. However, the
only gracefully-surfaceable `ReadError` in this engine is **`Disposed`**: a
transient, persistent `Err(Cycle)` is structurally unreachable — incr prevents
recorded dependency cycles, so a cell either aborts (`get_or_abort` on an
in-progress dep) or self-heals a cycle into a domain value (`get()` handled
in-compute); it never leaves a clean transient `Err(Cycle)` to recover from.
Therefore the acceptance row "after a transient ReadError clears, the state
machine resumes" cannot be constructed for `Cycle` (and `Disposed` is permanent).
Stage 3 tests the constructible behavior — `Disposed` non-driving + honest
surfacing + retained accepted state untouched — and documents the
resume-on-clear row as not applicable in this engine.

Remaining: stage 4 (API-reference docs + checked `.mbt.md` examples) and stage 5
(replace one Canopy/MoonDsp manual pattern).
