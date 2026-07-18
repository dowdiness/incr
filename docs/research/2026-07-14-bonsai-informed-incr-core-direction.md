# Bonsai-Informed Core Direction for `incr`

**Date:** 2026-07-14
**Last updated:** 2026-07-18 (Datalog lifecycle evidence; cross-engine lifecycle hypothesis; logical-horizon and ownership precision pass)

**Reader:** Maintainers evaluating whether to introduce a Runtime-wide resource-lifecycle abstraction, or investigating a second engine with the same lifecycle failure shape.

**Decision:** Preserve as a single directional research hypothesis. Not an accepted architecture, not an implementation authorization.

**Keep until:** One evidence gate fires (see §Evidence gates for cross-engine lifecycle model) or a successor ADR supersedes this note.

**Disposition:** Gated directional research. The Bonsai comparison raised lifetime/ownership questions; the retention baseline and Datalog lifecycle ADR provide partial local answers. The cross-engine model below is a hypothesis, not commissioned work. Retain until an evidence gate fires or a successor ADR supersedes this note; if accepted, distill the durable decision into an ADR and retire this research note; if rejected, record the rejection rationale in an ADR and delete.

**Status:** Directional research note. This document preserves priorities,
boundaries, and reopen criteria; it does not authorize a new public API.

**Related decisions:**
[retention follow-up tracks stay gated](../decisions/2026-07-14-retention-followup-tracks-gated.md),
[static Derived stays private](../decisions/2026-06-01-static-derived-public-surface.md),
[modal Runtime split is not warranted](../decisions/2026-04-26-modal-runtime-split-not-warranted.md),
[Datalog relation-rule lifecycle](../decisions/2026-07-18-datalog-relation-rule-lifecycle.md).

**Current evidence:**
[retention baseline](../performance/2026-07-14-retention-baseline.md),
[retention cost attribution](../performance/2026-07-15-retention-cost-attribution.md),
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
observed retained-volume cost is already known to be an engine defect.

The [2026-07-15 retention cost attribution](../performance/2026-07-15-retention-cost-attribution.md)
completed the local investigation into #399 as no-go:

- Native reproduced the residual at the same magnitude and N-dependent shape
  as wasm-gc, eliminating a wasm-gc-only root-scanning hypothesis.
- White-box controls found no cumulative-slot scan and no named engine
  operation scaling with retained slot count. Pull slots are already reusable
  (`free_memos.length() == N`).
- Push-free controls (7e/7f) stay flat at N=10,000, confirming the residual
  appears only when the one live eager cell activates push propagation.
- Slot reclamation/compaction is a **no-go** under #399 until all three
  reopen conditions hold: production-shaped cost, a named profiler operation
  scaling with retained storage, and an isolated prototype that reduces it.

#399 is therefore **complete as a local investigation (no-go)**, not as a defect. The
residual is an unresolved mixture of allocator/lifetime behavior, cache
locality, and target-runtime collection — none of which names an engine
change. The retention benchmarks (7a–7f) remain as regression probes.

The next open question is whether a broader cross-engine lifecycle model is
needed. See §Runtime resource lifecycle model (hypothesis) below.

## Current execution status

| State | Direction |
|---|---|
| Resolved | #399 retention cost attribution — native reproduction, white-box controls, slot-reclamation no-go; benchmarks retained as regression probes |
| Active | Keep retention benchmarks (7a–7f) as regression evidence |
| Completed higher-layer evidence | Aggregate Machine composition passed; no shared Machine abstraction justified. See [Machine composition ADR](../decisions/2026-07-14-machine-composition-domain-functions.md), [aggregate evidence](../performance/2026-07-14-machine-composition-evidence.md), and [follow-up snapshot](../performance/2026-07-15-machine-composition-follow-up.md) |
| Gated research | Cross-engine Runtime resource lifecycle model (see §hypothesis below) |
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

## Priority 0: historical-volume cost — resolved as no engine change

The [2026-07-15 retention cost attribution](../performance/2026-07-15-retention-cost-attribution.md)
completed the investigation this section originally framed:

- Native and wasm-gc reproduce the residual at the same magnitude (~5.5–6×
  N=10k/N=1k). The residual is not target-specific.
- Post-cleanup storage facts confirm: every stale root edge is removed,
  every pull slot is reusable (`free_memos.length() == N`), push node count
  drops to 1, but cumulative `cell_index`/`cell_ops`/`cell_lifecycle`/`pull.memos`
  backing arrays are not compacted.
- Push-free controls (7e/7f) are flat at N=10,000 on both targets. The
  N-dependent cost appears only when the one live eager cell activates push
  propagation through retained pull storage.
- No named engine operation is shown to scale with retained slot count. The
  attribution is an unresolved mixture of allocator, cache locality, and
  target-runtime behavior.

**Slot-reclamation decision: no-go.** Pull slots are already reusable, the
executed path does not scan cumulative arrays, and push-free updates stay
flat. Compacting now would add identity-remapping and lifecycle risk without
a pinned engine bottleneck. Reopen only when all three conditions hold:

1. a production-shaped workload reproduces a material user-visible cost;
2. a profiler identifies a named operation whose work scales with retained
   storage;
3. an isolated prototype reduces that operation without changing `CellId`,
   dependency, disposal, or GC semantics.

Scenarios 7a–7f remain as regression probes and negative controls.

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

## Datalog relation-rule lifecycle: current evidence of a local contract

The [2026-07-18 Datalog relation-rule lifecycle ADR](../decisions/2026-07-18-datalog-relation-rule-lifecycle.md)
is accepted and provides a concrete local example relevant to the cross-engine
lifecycle hypothesis:

- **Declarations are snapshotted lifecycle authority.**
  `Runtime::new_rule` validates that each declared relation belongs to the
  same runtime, is not disposed, and is actually a `Relation`; it then stores
  defensive `.copy()` snapshots of the input and output arrays. Caller-owned
  arrays are not retained.
- **Live rules pin declared relations.** A live rule prevents disposal of
  every relation it declares as input, output, or both.
  `find_live_rule_declaration` scans rules in registration order, ignores
  disposed rules, and reports the first live declaration with its role
  (input/output/both). Disposal rejects rather than cascades.
- **Rule-first teardown.** Callers must `rt.dispose_rule(rule_id)` before
  disposing any relation declared by that rule. Relation disposal aborts with
  the first live rule and its role. Repeated disposal is idempotent.
- **Pure deterministic query plus lifecycle shell.**
  `find_live_rule_declaration` is a pure functional core: explicit runtime
  state in, structured result or `None` out, no abort or mutation. Lifecycle
  aborts and mutation remain in the coordinator shell; the kernel boundary
  remains one-way.
- **Fixpoint phases guard relation callbacks.** Every relation-phase callback
  in `run_fixpoint` guards with `is_cell_disposed` and continues: `begin_fixpoint`,
  `drain_delta`, staged-delta convergence (`is_staged_delta_empty`), `promote_staged_delta`,
  and `finish_fixpoint_changed` (changed-ID collection). Disposed rules are separately
  skipped before their `apply_delta` callback inside the rule-application loop. `apply_delta`
  is a rule callback, not a relation phase.

This proves a **local lifecycle contract** within Datalog. It does not prove
that a Runtime-wide lifecycle abstraction is needed, wanted, or correct. The
Datalog contract is self-contained: declaration metadata is the sole
authority, there is no cascade or reverse index, and the engine's teardown
order is enforced by scanning rules — not by a universal dependency graph.

## Runtime resource lifecycle model (hypothesis)

This section preserves a cross-engine hypothesis that emerged from Bonsai
comparison, retention attribution, and the Datalog lifecycle work. It is a
**gated research hypothesis**, not an accepted architecture or implementation
authorization.

### Resource classes

The Runtime manages at least three classes of resource that outlive their
construction and require eventual teardown:

1. **Physical storage and closures** — SoA slots (`pull.memos`, `push.reactives`,
   `push.effects`, `datalog.rules`, `datalog.relations`), compute closures captured
   at construction, subscriber arrays, dispatch tables (`cell_index`, `cell_ops`,
   `cell_lifecycle`). Bookkeeping counters like `push.node_count` track live counts
   but are not SoA storage slots.
2. **Logical facts** — Datalog relation materialized state, frontier deltas,
   staged deltas. Set `Relation[T]` is monotonic: facts accumulate in a
   `HashSet` across every `fixpoint()` call for the relation's lifetime, with
   no general fact retraction. `MapRelation[K, V]` retains keys across
   `fixpoint()` calls in a `HashMap` and can replace a key's materialized
   value, but provides no general key retraction for facts absent from a
   later source revision. Neither variant supports retracting a fact or key
   that was previously materialized. Provenance tracking (which rule produced
   which fact) is required by a future differential/retraction model and is
   not currently tracked by the Runtime.
3. **Execution frontiers and scheduler entries** — active queries on the
   tracking stack, push propagation worklists, fixpoint iteration state,
   batch rollback frames, evaluation event queues.

### First-principles questions

For each resource class, the same questions recur:

1. **Owner** — who allocates, who is responsible for teardown?
2. **Live horizon** — from allocation to last legal use, what bounds the lifetime?
3. **Pins/roots/dependencies** — what keeps this resource alive? (GC roots,
   subscriber edges, declaration snapshots, batch rollback frames.)
4. **Atomic rejection/teardown** — can disposal be rejected before mutation
   when a pin is live? (Datalog does this: `find_live_rule_declaration` rejects
   relation disposal while a rule is live.)
5. **Reclamation/reuse** — is the slot reusable (pull `free_memos`), or does
   it require compaction (cumulative `cell_index`)?
6. **Stale-handle safety** — what happens when a handle is used after teardown?
   (Disposed-relation reads abort; `Scope` methods abort on disposed scope.)
7. **Logical fact retirement** — for set `Relation`, facts are monotonic and
   there is no retirement. `MapRelation` can replace a key's value but cannot
   retract a key. For future editable facts, what is the retraction protocol?

### Distinguishing Owner, Pin, Observer Root, and Dependency

A cross-engine model must distinguish several lifetime relationships. Current
data structures already implement some of these separately:

- **Owner** — the entity whose disposal cascades to this resource. Today:
  `Scope` is the concrete aggregate owner (`Scope::dispose` does children
  bottom-up, then dispose hooks, then owned cells). `Runtime` allocates and
  contains cell storage but currently has no aggregate disposal API that
  cascades teardown to all cells.
- **Pin** — a temporary hold that rejects teardown but does not own. A pin
  prevents disposal by rejecting it before mutation; it does not cascade disposal.
  Today: Datalog rules pin declared relations (a live rule aborts relation disposal
  via `find_live_rule_declaration`).
- **Observer Root** — an external keep-alive reference that controls GC reachability.
  Today: `Watch`/`Observer` increment `gc_root_counts`; `on_unobserve` fires when the
  final counted root is removed (count reaches zero in `gc_root_counts`), triggering
  push suspension for push cells. `Effect` cells carry an implicit `GcRole::Root` that
  is discovered separately during GC root collection by scanning cell slots — it is
  **not** an entry in `gc_root_counts` and does not trigger `on_unobserve`. Observer
  roots do **not** prevent explicit target disposal — when the target cell is explicitly
  disposed, the GC root entry is cleaned up via `drop_gc_root`. A pin rejects teardown;
  a root controls GC reachability.
- **Dependency** — a computed-value edge discovered during evaluation. Today:
  `ActiveQuery` records deps during tracking; deps are diffed against prior
  deps on recompute. `CellOps::gc_dependencies` exposes upstream GC dependency
  edges for cell kinds that participate (pull memos return their tracked
  dependencies; push reactives and effects return their sources; the default
  is empty). A dependency is not a pin — it is discovered and replaced on
  each successful recompute.

### Candidate shared mechanism

If a cross-engine lifecycle model were ever commissioned, it might share:

1. **Runtime/generation validation** — every resource access checks that the
   resource belongs to the current runtime and that its generation/slot is
   live. Today: `CellId.runtime_id` checks, `is_cell_disposed` guards,
   `Scope::disposed` aborts.
2. **Phase guard (candidate invariant with partial current enforcement)** —
   structural operations should be rejected during active evaluation. Today:
   `PropagationPhase` (`Idle`/`PushPropagating`/`InFixpoint`/`GarbageCollecting`) exists,
   but `check_dispose_guard` specifically rejects disposal only during `InFixpoint` and
   a cell's own computation. It does not reject during `PushPropagating` or `GarbageCollecting`.
   `enter_phase`/`leave_phase` enforce mutual exclusion between phases.
3. **Engine-specific pure preflight decision** — before any lifecycle
   mutation, a pure function decides whether to proceed or reject. Today:
   `find_live_rule_declaration` is pure (state in, result or `None` out);
   `validate_cell_for_dispose` is pure. The abort/mutation stays in the
   coordinator shell.
4. **Atomic cleanup** — disposal either completes fully or rejects before
   mutation, leaving the resource intact. Today: Datalog relation disposal
   rejects if a live rule declares it; pull disposal clears subscribers and
   pushes the slot onto the free list. An important limitation: `Scope::dispose`
   closes first (marks `disposed` before any teardown), then performs ordered
   child/hook/cell teardown. A later abort during that teardown — including a
   pinned relation aborting cell disposal — can leave partial aggregate teardown
   complete. Atomic aggregate preflight/commit for Scope disposal is therefore
   a hypothesis, not current behavior.
5. **Generational IDs and slot reclamation (hypothesis)** — free-list reuse
   exists (pull `free_memos`/`free_inputs`), but `CellId` does not carry a generation.
   Generational IDs to detect stale handles, aggregate Runtime teardown, recoverable
   lifecycle errors, and a shared preflight abstraction are hypotheses, not accepted APIs.
6. **Lifecycle observability** — opt-in introspection of resource counts,
   pin holders, and teardown order. Today: `cell_info`, `dependents`,
   `gc_root_counts`. No structured lifecycle event stream exists.

Current code provides partial precedents for some of these mechanisms (phase
tracking, pure preflight, atomic cleanup, slot reuse), but no shared lifecycle
abstraction currently exists.

### Engine-specific policy remains separate

The hypothesis explicitly does **not** propose:

- One universal dependency graph spanning all engines.
- A global cascade protocol crossing pull, push, and Datalog boundaries.
- A mode split or Runtime decomposition (the
  [2026-04-26 modal Runtime split ADR](../decisions/2026-04-26-modal-runtime-split-not-warranted.md)
  and [2026-04-26 R2 decomposition ADR](../decisions/2026-04-26-r2-runtime-decomposition-deferred.md)
  closed those directions).
- A Runtime service decomposition beyond the current coordinator + engines.

Engine-specific lifecycle policy remains separate for Pull, Push, Datalog,
Accumulator, and Scope. Each engine's disposal path is implemented as a
`CellLifecycle` trait method (`pull_memo_lifecycle.mbt`, `pull_lifecycle.mbt`,
`push_lifecycle.mbt`, `datalog_lifecycle.mbt`). The shared mechanism above
would provide common guard infrastructure, not common policy.

### Aggregate-owner ordered teardown and individual-resource rejection

Candidate aggregate owners that may perform intentional ordered teardown:

- **`Scope::dispose`** — children bottom-up, then dispose hooks (Watch/Observer
  cleanup), then owned cells. This is already implemented.
- **`Runtime` end-of-life** — not currently modeled. Runtime allocates and
  contains cell storage but currently has no aggregate disposal API. A future
  design might specify that disposing a Runtime tears down engines in a
  defined order.

Individual resource disposal rejects live pins:

- Datalog relation disposal rejects if a live rule declares it. This is the
  current concrete example of pin-based rejection.

### Datalog ownership choice: deferred

Datalog must eventually choose explicitly between:

- **Monotonic session/epoch ownership** — facts live for the duration of a
  `fixpoint()` session or an explicit epoch. No retraction. For set `Relation`,
  the current implementation is monotonic across the relation's lifetime:
  materialized facts accumulate across every `fixpoint()` call. For
  `MapRelation`, keys are retained across `fixpoint()` calls and a key's value
  can be replaced, but neither variant supports removing a fact or key that
  was previously materialized. A session or epoch reset mechanism is a possible
  future ownership model, not current behavior.
- **Differential retraction/provenance** — facts can be retracted, with
  provenance tracking that identifies which rules contributed which facts.
  This model would require provenance tracking, which is not currently implemented.

This choice is a precondition for serving editable non-monotonic facts. It
is not commissioned. The current lifecycle ADR (declaration snapshots,
rule-first teardown) is compatible with either choice.

### Closure captures and declarative rules

Raw `apply_delta` closure captures remain unverifiable: the Runtime cannot
inspect what relations a rule closure reads beyond the declared input/output
arrays. This is a known limitation. Declarative/capability-based rules —
where the Runtime mediates all fact access — are a long-term hypothesis, not
commissioned work. The current contract ("declare your relations, we enforce
teardown order on declarations") is the pragmatic answer.

### Evidence gates

The cross-engine lifecycle model should be promoted from hypothesis to
design only when at least one of the following fires:

1. **A second engine exhibits the same lifecycle failure** — a pull, push,
   accumulator, or Scope consumer encounters a stale-handle or teardown-order
   bug analogous to the Datalog relation-rule problem that motivated the
   2026-07-18 ADR.
2. **Production-shaped retained-resource growth** — a long-lived Runtime with
   realistic churn shows measurable retained-resource growth attributable to
   lifecycle gaps (not allocator behavior).
3. **A named profiler operation** — a profiler identifies a specific engine
   operation whose cost scales with retained-but-disposed resource count.
4. **Repeated ownership-order duplication** — three or more engines independently
   need the same "scan declarations, reject if live pin exists" pattern,
   justifying a shared abstraction.
5. **A consumer requires non-monotonic facts** — a real use case needs
   Datalog fact retraction or editable relations, forcing the ownership
   choice described above.

Until an evidence gate fires, the Runtime's lifecycle contracts remain
engine-specific. Current code provides partial precedents for the mechanisms
described above, but no already-existing shared lifecycle abstraction spans
all engines.

## Performance work after lifetime attribution

The push scheduler's priority queue, subscriber representation, and other hot
path constants remain valid investigation candidates. They are lower priority
than the retention regression probes because optimizing live-node scheduling
does not answer why a cleaned Runtime can retain cost correlated with
historical volume. The retention attribution resolved this: no named engine
operation scales with retained slot count, and slot reclamation is no-go
until the three reopen conditions hold.

The order is now:

1. keep 7a–7f as regression probes;
2. if an evidence gate fires for the cross-engine lifecycle model, design
   before implementing;
3. then reduce constant factors inside live work;
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
| — | Attribute residual historical-volume cost (#399) | **Resolved**: native reproduction, slot-reclamation no-go | All three reopen conditions: production cost, named profiler operation, isolated prototype |
| P0 | Keep retention benchmarks (7a–7f) as regression evidence | Proceed | Controls remain reproducible across targets |
| P1 | Cross-engine Runtime resource lifecycle model | Gated research | Second-engine lifecycle failure, production retained-resource growth, named profiler operation, repeated ownership-order duplication, or non-monotonic-fact consumer |
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
