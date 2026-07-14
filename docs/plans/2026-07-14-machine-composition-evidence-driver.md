# Machine Composition Evidence Driver Plan

**Date:** 2026-07-14

**Status:** Proposed. This is the next higher-layer experiment, not an `incr`
core API project.

**Direction:**
[Machine semantics start gates](../research/2026-07-14-machine-layer-start-gates.md).

**Boundary constraint:**
[`incr_tea` module identity ADR](../decisions/2026-07-03-incr-tea-module-identity.md).

## Goal

Determine whether ordinary pure functions plus the existing
`Program::stateful_cmd` surface are sufficient for parent/child Machine
composition, semantic identity, retirement, and stale-command rejection.

Produce evidence before designing a `Machine` type or allocating one reactive
subgraph per child.

## Non-goals

- no `incr` public API changes;
- no new `Machine` trait or universal component type;
- no `DerivedMap::evict`, `Scope::child` detachment, or keyed core facade;
- no per-child `Input`, `Derived`, `Watch`, or `Scope` in the baseline;
- no renderer rewrite;
- no generative-UI runtime;
- no claim that #399 is solved by this experiment.

## Why a test-only driver first

`incr_tea/browser_editor_demo.mbt` already demonstrates semantic keys and
multiple view roots, but it also doubles as a renderer white-box fixture. The
module identity ADR says the next fixture-touching change must disentangle that
coupling before moving the demo.

The first slice therefore belongs in a dedicated test-only fixture. It may
reuse the semantic-editor scenario, but it must not make the existing demo a
larger package-private dependency. A later visual driver can reuse the proven
pure transition after the fixture boundary is cleaned up.

## Baseline model

Use immutable returned values or defensive copies for collections crossing the
transition boundary. Local mutation while constructing a returned value is
acceptable when it is unobservable.

The fixture needs these concepts; exact public type names are deliberately not
prescribed:

```text
ChildId          stable semantic identity
Incarnation      changes when a removed ID is reused
ChildModel       local editable state
ParentModel      ordered child IDs + child records + next incarnation
ChildAction      edits local state or requests a command
ParentAction     routes child actions and performs add/remove/reorder
CommandResult    carries ChildId + Incarnation back to the parent
```

`ChildId` preserves logical identity across reorder. `(ChildId, Incarnation)`
identifies one mounted lifetime and prevents a late result from an old child
from mutating a replacement that reused the same ID.

## Work package 1: pure transition semantics

Create a test-only parent/child transition with no Runtime dependency.

Required tests:

1. a routed child action changes only the named child;
2. reorder preserves every surviving child's local state;
3. removal deletes the child and repairs selection/focus metadata
   deterministically;
4. adding a new ID creates a fresh state;
5. removing then reusing an ID allocates a new incarnation;
6. a command result for the current incarnation is accepted;
7. a late result for a retired incarnation is ignored or returned as an
   explicit stale decision;
8. replaying the same initial model and actions produces the same final model
   and command descriptions.

### Exit condition

All semantics are testable without `@incr`, DOM, clocks, or asynchronous
execution. If this is not possible, record the exact impurity before designing
an abstraction around it.

## Work package 2: existing Program integration

Wrap the pure transition with `Program::stateful_cmd` using:

- one Program-owned model;
- one version `InputField` created by the existing constructor;
- one terminal `Derived` view and persistent, primed `Watch`;
- one Program `Scope`;
- command interpretation at the Program shell.

Required tests:

1. dispatch produces the same state/view sequence as direct pure replay;
2. `Runtime::gc()` before and during use does not sweep the watched graph;
3. Program disposal makes later dispatch deterministic and harmless;
4. simulated deferred completion carries the incarnation token and cannot
   update a removed or replaced child;
5. a white-box Program test records the existing `_view_id` and verifies that
   repeated child churn keeps the same view root, a stable dependency count
   through `Runtime::cell_info`, and `Runtime::gc_root_count(view_id) == 1`;
6. disposal changes `Runtime::gc_root_count(view_id)` to zero and makes the
   disposed view unavailable through introspection;
7. after each churn wave, the ordered IDs and child-record collection contain
   exactly the current live children, with no retired incarnation retained.

### Exit condition

The aggregate Program preserves the pure semantics and owns a bounded reactive
graph independent of historical child count.

## Work package 3: application-shaped measurement

Measure the aggregate design before proposing per-key reactivity. Use the
semantic-editor shape already present in the repository: editable keyed rows,
selection, reorder, add/remove, and an inspector-like projection.

Record at representative live sizes, including at least 64 and 256 children:

- transition time for one local edit;
- view recomputation time;
- DOM patch time when a browser fixture is used;
- the known Program view root's identity, dependency count, and GC-root count;
- live model cardinality after repeated add/remove/reuse waves;
- state and DOM identity preservation across reorder.

Use known-root, dependency, and model-cardinality assertions as the primary
lifetime evidence available at the `incr_tea` boundary. The aggregate baseline
does not allocate cells during child dispatch, so do not claim or infer total
Runtime slot counts from this fixture. Timing is secondary and must be stored
in a new dated performance snapshot rather than appended to an unrelated
baseline.

### Exit condition

The result states one of:

- aggregate composition meets the named workload target; stop without a
  per-key reactive design;
- rendering is the bottleneck; improve the renderer or view partitioning,
  not core ownership;
- whole-model/view recomputation is the measured bottleneck and per-key
  reactive ownership is a plausible response;
- the workload is still too artificial to authorize another layer.

## Work package 4: abstraction decision

Review this driver together with at least one other application-shaped driver
that actually exercises a pure parent/child transition and the same routing,
identity, or command protocol. The current typed spreadsheet is contextual
evidence only: it uses direct `InputField` mutation and does not qualify unless
a bounded pure-transition slice is extracted and tested separately.

Do not propose a `Machine` type unless both expose the same repeated protocol.
If they do, write a separate design that names the smallest shared
responsibility: action mapping, command mapping, state lenses, incarnation
handling, lifecycle ownership, or subscription composition.

The decision may be "pure functions remain sufficient." That is a successful
outcome.

## Conditional work package 5: per-key reactive variant

This package is not authorized by completion of packages 1–4 alone. Start only
when package 3 records a missed target caused by aggregate reactive work and a
per-key graph has a credible path to that target.

Before implementation, add a delta design covering:

- the owner and terminal root of each per-key graph;
- F7 behavior if a surviving cell can retain a retired dependency;
- removal, tombstone, or aggregate retirement protocol;
- #399 relevance to the intended bounded or unbounded workload;
- create/retire/recreate count assertions;
- the exact comparison against the aggregate baseline.

If the per-key experiment requires total live/free slot counts that public
introspection cannot provide, add a separate white-box probe alongside
`incr/cells` and the retention suite. Keep that instrumentation test-only; do
not widen the public Runtime API merely to execute this plan.

For a bounded product, publish the supported bound and measured ceiling. For a
general unbounded-lifetime claim, require #399 attribution and demonstrate
that engine-owned work converges on the live graph.

## Validation sequence

For any implementation of this plan:

1. `moon fmt`
2. targeted pure-transition tests
3. targeted `incr_tea` Program tests
4. `moon check incr_tea`
5. `moon test incr_tea`
6. browser identity tests if the DOM fixture is changed
7. known-root/dependency/model-cardinality assertions and a dated performance
   snapshot for aggregate measurement work
8. `moon info` and public `.mbti` inspection only if a public surface changes

## Deliverables

- a test-only pure composition fixture;
- aggregate Program integration tests;
- a dated semantic-editor-shaped measurement snapshot;
- a short abstraction decision: functions remain sufficient, or a separate
  narrowly scoped design is warranted;
- no core API change unless a later gated proposal supplies independent
  evidence.
