# Bonsai-Informed Core Direction for `incr`

**Date:** 2026-07-14

**Status:** Directional research note. This document preserves priorities,
boundaries, and reopen criteria; it does not authorize a new public API.

**Related decisions:**
[retention follow-up tracks stay gated](../decisions/2026-07-14-retention-followup-tracks-gated.md),
[static Derived stays private](../decisions/2026-06-01-static-derived-public-surface.md),
[modal Runtime split is not warranted](../decisions/2026-04-26-modal-runtime-split-not-warranted.md).

**Current evidence:**
[retention baseline](../performance/2026-07-14-retention-baseline.md),
[retention benchmark plan](../plans/2026-07-14-duplix-retention-benchmarks.md),
[`Expr[T]` design](../design/specs/2026-05-25-expr-formula-api.md).

**Higher-layer follow-up:**
[Machine-layer start gates](2026-07-14-machine-layer-start-gates.md).

## Purpose

A comparison with Jane Street's Bonsai raised two different questions:

1. What should a higher-level system for composable state machines and dynamic
   components provide?
2. What must the lower-level `incr` engine guarantee before such a system can
   be built safely?

This note answers only the second question. Component state machines, keyed UI
instances, renderer activation, clocks, commands, and generative-UI plans are
deliberately outside the `incr` core. Bonsai is useful here as pressure on the
engine's lifetime, ownership, and observability contracts, not as an API to
copy into `incr`.

## Executive direction

The next core objective is not another cell mode. It is a stronger lifetime
property:

> After transient subgraphs are retired, memory, graph bookkeeping, and steady
> update cost should converge on the currently live graph rather than remain
> proportional to the total graph volume created over the Runtime's history.

This is a target property and measurement criterion, not a claim that every
observed retained-volume cost is already known to be an engine defect. The
2026-07-14 wasm-gc baseline found residual cost after disposal/GC while the
live subscriber count was fixed. Issue #399 must first attribute that cost to
SoA slot volume, retained references, or target heap/collector behavior.

The immediate authorized work therefore remains narrow:

1. investigate #399 with native-target comparison and post-dispose slot-count
   assertions;
2. preserve the existing retention benchmarks as the regression instrument;
3. do not commission detachable Scope ownership, a keyed facade, or a new
   public static-derived surface without their existing evidence gates.

## Current execution status

| State | Direction |
|---|---|
| Active | Attribute #399 and retain the current benchmark controls |
| Active higher-layer evidence | Run the aggregate Machine composition driver without changing `incr` |
| Conditional | Per-key reactive experiment only after the aggregate driver misses a measured target |
| Not commissioned | Detachable child Scopes, `DerivedMap` eviction, `GraphSnapshot`, explicit commit API, static `Expr` lowering, scheduler rewrite |

The gated sections below are an inventory of preserved hypotheses, not a
promised backlog. A higher-layer driver should reopen at most the specific
direction for which it supplies evidence.

## What `incr` already does well

The Bonsai comparison does not justify replacing the current evaluation model.
`incr` already has the important low-level machinery:

- dynamic dependency discovery for ordinary `Derived` computations;
- equality backdating and custom `BackdateEq` policies;
- pull, push, reachable-lazy, and Datalog execution modes in one Runtime;
- atomic raised-error batch rollback and revert detection;
- explicit `Scope`, `Watch`, `Observer`, `dispose`, and `Runtime::gc`
  lifetimes;
- push suspension on the last read-root transition;
- runtime identity checks, cycle diagnostics, and cell-level introspection;
- an `Expr[T]` authoring layer and a package-private fixed-dependency fast path;
- `AcceptedDerived` for a current result plus a retained last-accepted value.

The core direction is to harden and expose coherent contracts around these
facilities, not to add Bonsai's `Computation`, state machine, or lifecycle API
to the Runtime.

## Priority 0: attribute historical-volume cost

The retention baseline established two separate effects:

- forgotten live graph edges can cause O(N) subscriber scans or eager
  recomputation when a source-local push path is reachable;
- after explicit disposal or GC removes those edges, some wasm-gc controls
  still become slower as cumulative constructed-node volume increases.

The second effect is the first core question because it affects disciplined
users as well as users who forget disposal. The investigation must distinguish:

- live and free SoA slot counts after disposal;
- whether free slots are reused on later allocation;
- references retained by slot arrays, closures, Scopes, hooks, or root tables;
- update loops whose work depends on array capacity or historical high-water
  marks;
- wasm-gc heap behavior versus native behavior.

### Required evidence

Before proposing a slot-reclamation change:

1. rerun the positive controls on the native target;
2. add white-box assertions for live slots, free slots, subscribers, push node
   counts, and GC roots after disposal and GC;
3. separate "create N, retire N, then update" from "retain N dead edges";
4. verify that a second allocation wave reuses the retired slots;
5. record a new dated snapshot rather than editing the existing baseline.

### Success condition

For a fixture with the same live graph after cleanup, update work attributable
to graph traversal should be independent of historical churn. If target heap
cost still varies, document it separately rather than hiding it behind an
engine rewrite.

## Gated direction A: dynamic ownership hygiene

Dynamic systems put pressure on two current ownership surfaces, but neither
change is commissioned today.

### Disposed child Scopes

`Scope::child` appends a child to the parent's `children` array. Disposing the
child clears the child's own arrays, but does not detach its handle from the
parent. A long-lived parent with repeated child churn can therefore retain one
empty Scope handle per historical child.

Possible remedies include:

- detach-on-dispose with a generation-safe parent registration;
- a reusable child-slot/free-list representation;
- an explicit sweep of disposed children;
- keeping per-key ownership outside the parent Scope entirely.

The accepted retention ADR deliberately leaves this unchanged. Reopen only
after a dedicated probe creates and individually disposes at least 10,000
children under one live parent and demonstrates material retained memory,
parent-dispose latency, or a named consumer whose lifetime cannot be modeled
cleanly without detachable children.

### Explicit `DerivedMap` eviction

`DerivedMap` creates and retains one `Derived` entry per read key until the
cache is cleared, the owning Scope is disposed, or a disposed entry is swept.
An explicit `evict(key)` or `retain_keys(keys)` API is a plausible future
resource-control surface, but it inherits the F7 retirement problem: a live
downstream cell may still record the entry being retired as a dependency.

Do not add eviction as cache bookkeeping alone. A proposal must specify the
retirement protocol for surviving dependents and choose among a facade-owned
terminal aggregate, tombstones plus sweep, or an engine-level semantic change.
It must also name a consumer and success metric under the reopen criteria of
the retention ADR.

## Gated direction B: structural-mutation safety

The Runtime has several operations that mutate graph structure or observers:

- cell disposal and GC;
- read-root addition and removal;
- listener registration and removal;
- future cache eviction or child detachment.

Existing operations use a mixture of phase guards, idempotent no-ops, and
aborts. A future hardening pass should audit them against one invariant:

> A structural operation either completes atomically in an allowed phase, or
> rejects before mutation and leaves the Runtime unchanged.

A shared private guard is preferable to exposing the internal phase machine.
If a public recoverable error is needed, design it from a real integration
case; do not add a broad `RuntimePhase` or `RuntimeBusy` API speculatively.

This audit is independently useful, but any public signature change requires a
separate design document and tests for re-entry, listener drain, nested batch,
push propagation, fixpoint, and disposal cascade windows.

## Gated direction C: coherent observability

`Runtime::cell_info` and `Runtime::dependents` provide useful snapshots for
pull-oriented cells, while internal evaluation strategies already emit richer
pull and push events. A Bonsai-like tooling ecosystem would benefit from a
coherent view, but tooling needs do not authorize default-path overhead.

### Desired properties

If this direction is commissioned, it should provide:

- a truthful `CellKind` across all supported cell variants;
- lifecycle state where meaningful (`Active`, `Suspended`, `Disposed`);
- labels on push cells as well as pull cells;
- dependencies, subscribers, revisions, and GC-root counts as defensive
  copies;
- one opt-in evaluation event vocabulary covering pull rebuilds, push
  propagation, effects, and aborts;
- zero event construction and storage cost when tracing is disabled.

### `GraphSnapshot` gate

An earlier read-semantics design correctly rejected `Runtime::snapshot` when it
was only ceremony around several handle reads. Reconsider it only with a real
invariant:

- capture is allowed only at an idle boundary;
- every returned cell belongs to one Runtime revision;
- all mutable collections are copied;
- the snapshot has a concrete consumer such as a graph debugger, trace-aware
  test harness, or retained-volume diagnostic.

Without those properties, keep the existing cell-level API.

## Gated direction D: abort-safe atomic updates

`Runtime::batch` can roll back catchable raises, but MoonBit `abort()` is not
catchable. An abort inside the callback can leave batch depth, frames, and
pending write closures unsettled. This cannot be repaired with another catch
inside `batch`.

The promising direction is an additional explicit commit path:

1. compute and validate a change plan before entering Runtime batch state;
2. enter a short commit phase that executes no arbitrary user computation;
3. apply validated writes atomically;
4. leave callback-based `batch` as the lower-level flexible API.

Possible forms include a transaction builder or a reducer-produced update
plan. Heterogeneous typed writes, equality policy, rollback hooks, and
cross-runtime validation make this a design problem rather than a small
convenience method. Do not implement it without a consumer that demonstrates
why `batch_result` is insufficient.

## Gated direction E: static lowering for `Expr[T]`

`Expr[T]` currently materializes as one ordinary dynamically tracked
`Derived`. The package-private static-derived path already proves that fixed
dependencies can avoid tracking-stack work and dependency-list diffing.

The long-term lowering split remains:

```text
fixed-source Expr graph  -> private static-derived backend
ordinary closure         -> dynamic dependency tracking
```

This is not permission to expose raw static installers or add public
arity-specific static constructors. Follow the accepted static-derived ADR:

1. identify an `Expr` or attachment consumer;
2. measure an end-to-end workload, not only scalar microbenchmarks;
3. preserve same-runtime validation and duplicate-dependency normalization;
4. define behavior for undeclared reads, accumulators, cycles, and failure
   cleanup;
5. keep the resulting handle's inside/outside read semantics identical to
   ordinary `Derived`.

If the real workloads do not improve, retain the dynamic backend.

## Performance work after lifetime attribution

The push scheduler's priority queue, subscriber representation, and other hot
path constants remain valid investigation candidates. They are lower priority
than #399 because optimizing live-node scheduling does not answer why a cleaned
Runtime can retain cost correlated with historical volume.

The order is:

1. establish what work remains after cleanup;
2. make cost proportional to the live graph where the engine controls it;
3. then reduce the constant factors inside that live work;
4. rerun UI-shaped, semantic-query, and cross-target benchmarks before
   accepting a scheduler rewrite.

## Core boundary: what not to add to `incr`

The following belong in `incr_tea` or another higher-level module:

- component blueprints and component-local application state;
- `Model + Action -> (Model, Command)` state machines;
- keyed stateful component instances;
- UI-level `Active` / `Inactive` lifecycle policy;
- clocks, timers, HTTP, async commands, and renderer phases;
- semantic IDs, generated UI plans, and state migration;
- DOM or terminal rendering.

Do not add `Watch::pause` / `resume` merely to mirror Bonsai activation. Lazy
`Derived` work already stops when it is not read, and observed push cells
suspend when their last read root is removed. A new "retained but inactive"
core state needs a measured engine-level gap, not a UI analogy.

## Direction inventory

| Priority | Direction | Current authorization | Reopen / completion gate |
|---|---|---|---|
| P0 | Attribute residual historical-volume cost (#399) | Proceed | Native comparison, slot assertions, dated snapshot |
| P0 | Keep retention benchmarks as regression evidence | Proceed | Controls remain reproducible across targets |
| P1 | Detachable child Scope ownership | Gated | Named churn consumer plus ≥10k-child evidence |
| P1 | `DerivedMap` eviction / keyed ownership | Gated | Named consumer plus explicit F7 retirement protocol |
| P1 | Structural-mutation contract audit | Research allowed | Concrete unsafe/re-entrant case; separate design for API changes |
| P1 | Coherent graph snapshot and unified trace | Gated | Idle-snapshot invariant plus debugger/test consumer |
| P2 | Abort-safe explicit commit path | Gated | Consumer for which `batch_result` is insufficient |
| P2 | Static lowering of `Expr[T]` | Gated | Accepted ADR trigger plus end-to-end win |
| P3 | Push scheduler / subscriber rewrite | Deferred | Lifetime attribution complete; measured hot-path driver |

## Validation standard for future core work

Any implementation arising from this note must include evidence proportional
to its risk:

- deterministic semantic tests for disposal, GC, cross-runtime reads, cycles,
  nested batches, and re-entry;
- count assertions in addition to timing;
- create/retire/recreate churn tests, not only one-shot construction;
- wasm-gc and native comparison when heap behavior is part of the claim;
- a dated benchmark snapshot for performance decisions;
- public `.mbti` inspection and documentation updates for any surface change;
- no mutable internal collection exposed through an introspection result.

## Long-term completion criterion

The core is ready to support higher-level dynamic systems when the following is
demonstrably true:

> A long-lived Runtime can repeatedly create, observe, retire, collect, and
> recreate transient subgraphs while its graph bookkeeping and engine-owned
> steady update work converge on the live graph, with explicit ownership and
> defined retirement behavior.

That criterion is the durable lesson taken from Bonsai for `incr`. The
higher-level component abstraction may eventually exploit it, but it should
not determine or pollute the core API before the evidence gates fire.
Coherent diagnostics and atomic structural mutation remain valuable when a
real consumer requires them, but neither is a universal prerequisite for an
aggregate higher-level Machine design.
