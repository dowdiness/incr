# Start Gates for Machine Semantics Above `incr`

**Date:** 2026-07-14

**Status:** Directional research note. This records start and stabilization
criteria; it does not authorize a new `Machine` type or an `incr` API.

**Next experiment:**
[Machine composition evidence driver](../plans/2026-07-14-machine-composition-evidence-driver.md).

**Core dependency:**
[Bonsai-informed `incr` core direction](2026-07-14-bonsai-informed-incr-core-direction.md).

**Retention decision:**
[retention follow-up tracks stay gated](../decisions/2026-07-14-retention-followup-tracks-gated.md).

**Existing higher-layer work:**
[`Program::stateful` design](../design/specs/2026-06-25-program-stateful-design.md),
[incremental TEA direction](incr-tea-ui-direction.md).

## Current position

| State | Work |
|---|---|
| Existing | Pure `update` functions, `Cmd`, `Program::stateful`, `Program::stateful_cmd`, Scope-owned watched views, semantic-keyed editor and typed-spreadsheet drivers |
| Active next experiment | Pure parent/child composition, semantic identity, add/remove/reorder, and stale-command rejection on one aggregate Program graph |
| Parallel core work | Attribute #399 and preserve retention benchmarks |
| Conditional experiment | Per-key reactive subgraphs, only if the aggregate driver misses a measured locality or lifetime target |
| Not commissioned | A public `Machine` type, core keyed facade, detachable child Scopes, generative-UI runtime |

Do not treat the number of sections in this note as a backlog. Only the active
experiment and #399 are current work.

## Decision

Start higher-layer work according to its dependencies, not the percentage of
the `incr` roadmap completed:

- pure Machine *semantics* and a single Program graph are already feasible;
- nested and keyed state experiments may proceed as evidence-producing
  consumers;
- no new `Machine` trait or struct is justified until ordinary pure functions
  show repeated composition friction in more than one driver;
- per-key reactive ownership is an optimization candidate, not the definition
  of keyed state;
- an unbounded, long-lived per-key runtime needs stronger retirement and churn
  evidence than a bounded application does;
- generative UI remains a set of design constraints until a named generator
  and workload exist.

Machine work is therefore a consumer of `incr`, not a feature to add to the
`incr` Runtime.

## Architectural boundary

The functional core is a deterministic transition:

```text
Model + Action -> (Model, Command)
```

This notation is conceptual, not a required public type. A real transition may
return a domain `Result`, decisions, or a batch of command values. It must not
mutate an `incr` Runtime, read a clock, access the DOM, perform HTTP, or start
asynchronous work.

The imperative shell owns integration:

```text
Action
  -> pure transition
  -> next Model + command descriptions
  -> model Input update + command interpretation
  -> Derived view
  -> renderer boundary
```

`Program::stateful` and `Program::stateful_cmd` already establish much of this
boundary. The next question is composition and lifetime, not how to introduce
another state container.

## Stage A: aggregate composition evidence

**Status:** proceed now.

**Core dependency:** satisfied by the current API.

Use one Program-owned model and one terminal watched view. Model child state by
stable semantic ID, but do not allocate one reactive subgraph per child.

The driver must cover:

- parent-to-child action routing;
- child-to-parent command/result routing;
- add, remove, and reorder while preserving surviving child state;
- remove then reuse of the same semantic ID;
- rejection of a late result from the retired incarnation;
- deterministic replay of the same action sequence;
- explicit Program disposal and post-disposal message behavior.

This stage is not blocked by #399 or F7 because repeated child churn changes
model values, not the number of reactive cells. It should use the existing
Scope-owned, primed `Watch` lifetime rather than inventing component activation
inside `incr`.

### Exit evidence

- the semantic cases above are deterministic tests;
- the Program keeps the same known view root, stable view dependencies, and
  one GC root across child churn, then releases that root on disposal;
- model collection cardinality returns to the live child set after each churn
  wave;
- an application-shaped workload records view and DOM work at representative
  child counts;
- composition friction is recorded without assuming that it requires a new
  public abstraction.

## Stage B: decide whether an abstraction is missing

**Status:** decision after Stage A.

Prefer functions and small domain types. Propose a `Machine` type only if at
least two application-shaped drivers actually exercise the same pure
parent/child protocol, repeat the same unsafe or verbose machinery, and a
named abstraction removes it without hiding ownership. A driver based on
direct reactive-field mutation is not corroborating evidence unless it first
extracts a comparable pure-transition slice.

A proposal must identify which responsibility cannot remain ordinary code:

- action mapping;
- command mapping and cancellation;
- parent/child state lenses;
- instance identity and incarnation tokens;
- lifecycle ownership;
- composition of views or subscriptions.

Do not combine all of these behind one type merely because Bonsai uses a
component computation abstraction.

## Stage C: optional per-key reactive experiment

**Status:** gated by Stage A measurements.

Run this experiment only if the aggregate design misses a named locality,
latency, or lifetime target and per-key reactive subgraphs plausibly address
the measured cause. The experiment itself becomes the named consumer required
by the retention ADR.

### Universal stabilization gates

Any stable keyed lifecycle, whether aggregate or per-key, must demonstrate:

- semantic identity is independent of array position and cell identity;
- create, remove, reorder, reuse, and late-result behavior is defined;
- every Scope, Watch, subscription, and task has one owner;
- churn tests cover many create/retire/recreate waves;
- bounded products publish and meet their resource and latency bounds.

### Additional gates for per-key reactive subgraphs

Only a design that creates and retires cells per key must also address:

- whether surviving downstream cells can retain retired dependencies;
- the F7 retirement protocol when that dependency shape exists;
- live/free slot counts and graph-root counts after cleanup;
- #399 attribution before claiming safe unbounded historical churn;
- a written choice among a facade-owned aggregate, tombstones plus sweep, or
  an engine semantic change when individual cell retirement is required.

When public introspection cannot supply total live/free slot counts, gather
that evidence in a separate `incr/cells` white-box probe rather than adding a
public diagnostic API for the experiment.

#399 is not an absolute blocker for every bounded keyed product. A bounded
deployment may stabilize when its measured workload and resource ceiling are
acceptable. It is a blocker for a general claim that arbitrary historical
churn is harmless.

## Stage D: production dynamic component runtime

**Status:** design may follow evidence; implementation is not commissioned.

A production runtime may eventually define component blueprints, local state,
activation, keyed identity, task cancellation, and renderer lifecycle. These
remain higher-layer semantics.

Production readiness requires:

- engine-owned bookkeeping converges on the live graph for any per-key graph
  design;
- inactive and disposed are distinct when both are exposed;
- retired instances cannot deliver results into a reused identity;
- parent removal retires all owned children, subscriptions, and tasks;
- diagnostics are sufficient to attribute retained roots in the real driver.

`GraphSnapshot`, unified tracing, or detachable child Scopes may become useful
responses to evidence from this runtime. They are not automatic prerequisites.

## Stage E: incremental generative UI

**Status:** design principles only; no runtime plan is commissioned.

Before scheduling implementation, name the generator and workload: for
example, an LLM-produced UI plan, schema-generated forms, or a projectional
editor. Those sources have different validation, trust, and churn profiles.

Any future plan must treat generated UI as declarative data validated before
commit and define:

- stable semantic IDs;
- preserve, create, move, replace, and retire reconciliation;
- state compatibility and migration across plan revisions;
- validation and capability checks;
- effect permissions at the imperative boundary;
- deterministic fallback when validation or migration fails;
- bounded churn for semantically equivalent plans.

Generated and hand-authored components must share one identity and retirement
model. Do not create a second lifecycle for generated content.

## Core work that does not block Stage A

The following remain gated ideas rather than scheduled Machine prerequisites:

- coherent `GraphSnapshot` and unified tracing;
- an abort-safe explicit commit path;
- static lowering of `Expr[T]`;
- push scheduler or subscriber rewrites;
- detachable child Scope ownership;
- public keyed collection facades.

Reopen one only when the evidence driver demonstrates the missing guarantee
and satisfies that direction's existing gate.

## Durable rule

> Start with pure functions and the aggregate graph that `incr` already
> supports. Add a higher-level abstraction or finer reactive ownership only
> when a real driver measures the gap. Stabilize only the guarantees exercised
> under that workload.
