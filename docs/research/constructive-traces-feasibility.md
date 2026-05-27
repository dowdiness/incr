# Constructive Traces Feasibility for `incr`

**Status:** Research note — no implementation decision.  
**Date:** 2026-05-27  
**Question:** Should `incr` adopt constructive traces from Mokhov, Mitchell, and Peyton Jones's "Build Systems à la Carte" taxonomy?

## Short Answer

Do **not** replace `incr`'s default revision-based verifying traces with constructive traces.

`incr`'s current default is the right baseline for local editor and UI latency:

- it is cheap: revision comparisons are integer comparisons;
- it is precise: dependencies are dynamically discovered and verified lazily;
- it supports early cutoff through backdating;
- it does not require users to hash, serialize, or version compute closures.

Constructive traces are still worth keeping as a research direction, but only as an **opt-in cacheable-query layer** for expensive deterministic semantic computations. They are not a good default for fine-grained UI reactivity, where the cost of hashing, serialization, cache lookup, and cache eviction is likely to exceed the recomputation saved.

The more actionable near-term lesson from the paper is not constructive caching. It is the distinction between **static/applicative** and **dynamic/monadic** dependency shapes. `incr` should investigate static `Derived::map`, `map2`, `map3`, or `derived_static` APIs before adding any constructive-trace engine.

## Background: Where `incr` Sits Today

Mokhov, Mitchell, and Peyton Jones decompose build systems into two axes:

1. **Scheduler** — the order in which tasks are brought up to date.
2. **Rebuilder** — the method used to decide whether work is required.

In that taxonomy, `incr` is best described as:

> **Suspending scheduler + verifying step traces via revisions**, with recoverable cycle errors.

The correspondence is direct:

| Paper concept | `incr` concept |
|---|---|
| Task | `Derived` / `Memo` compute closure |
| Monadic task | compute closure may branch on values read from other cells |
| Suspending scheduler | `pull_verify` recursively verifies dependencies on demand |
| Verifying step trace | dependency list plus `verified_at` / `changed_at` revisions |
| Early cutoff | backdating when recomputation returns an equal value |
| Constructive trace | cache entry that can produce an output from stable task and dependency fingerprints |

The current engine answers this question efficiently:

> Is the value currently stored in this cell still valid at the current revision?

Constructive traces answer a stronger question:

> If the current value is not known to be valid, have we previously seen the same task with the same dependency fingerprints, and can we reuse that result without running the task?

That stronger question requires a stronger user and engine contract.

## What Constructive Traces Would Add

A constructive trace records enough information to reconstruct a result:

```text
(rule identity, rule version, dependency fingerprints) -> output value
```

This can help when the same computation state recurs:

- undo/redo returns an input to old content;
- an editor session reopens a project with unchanged semantic inputs;
- multiple query keys share identical normalized dependencies;
- a later run wants a result already produced by a previous run or process.

Revision-based verifying traces cannot do this across equivalent histories. If an input changes from `A` to `B` and then back to `A`, `incr` sees a newer revision and must verify or recompute. Backdating prevents downstream churn after recompute, but it does not remember all previous input-content states.

Constructive traces therefore add **content-addressed reuse**. They also add overhead and new correctness obligations.

## Feasibility by Workload

The requested target is **local editor/UI latency**, covering both language-tooling style queries and fine-grained UI reactivity. These workloads have different answers.

| Workload | Fit | Reason |
|---|---:|---|
| Fine-grained UI reactivity | Poor | Compute closures are usually tiny. Hashing and cache lookup cost more than recomputing. UI latency prefers fewer allocations, static dependency APIs, and push/pull scheduling improvements. |
| Parser/CST projection | Mixed | Incremental parsing and structural sharing should handle most reuse before `incr` sees it. Constructive traces may duplicate parser/interner caches unless placed at a higher semantic boundary. |
| Type checking / semantic queries | Best candidate | Queries can be expensive, deterministic, and keyed by stable semantic IDs. Undo/reopen/content-equivalent reuse can matter. Requires explicit query keys and versioning. |
| Datalog/fixpoint relations | Weak by default | Semi-naive evaluation already tracks deltas. Caching whole fixpoint outputs risks high storage cost and tricky invalidation unless a concrete workload proves repeated equivalent states. |
| Cross-process or distributed reuse | Technically plausible, not local-latency first | Requires serialization, stable task IDs, CAS or KV storage, eviction, and version negotiation. This belongs after a session-local prototype proves value. |

Conclusion: constructive traces are not a general latency optimization. They are a possible optimization for a **small class of expensive, deterministic, explicitly keyed queries**.

## Answers to the Open Questions

### A. Closure hashing

General closure hashing is not feasible.

MoonBit closures capture runtime values, and closure identity is not a stable description of computation semantics. Even if a closure body could be identified, captured values, imported functions, compiler version, and configuration would still need to be part of the cache key.

Feasible alternatives:

1. **User-supplied stable query key** — for example `TypeOfFunction(function_id)`.
2. **Rule version string/hash** — manually bumped by the driver when query semantics change.
3. **Typed query families** — a future API can make the rule identity the type or constructor, not the closure object.

Rejected for now:

- automatic closure hashing;
- cache keys derived from source locations alone;
- treating `CellId` as stable across sessions.

### B. Workload fit

For local editor/UI latency, constructive traces should be gated behind benchmarks.

A useful prototype must beat the existing engine on at least one realistic workload:

- edit/undo/re-edit semantic query;
- reopening a project with persistent cache warmed;
- repeated type-checking of unchanged stable semantic entities;
- expensive normalized projection where equality/backdating is already too late to save the expensive work.

It should not regress UI-shaped graphs where work per cell is small. Existing UI-shaped benchmarks are the right regression guard: any cache hook on the default `Derived` path must be invisible there.

### C. Cycle interaction

Cycle results must not be cached as normal outputs.

`CycleError` depends on the active verification path, not just on a local query key and dependency fingerprints. Caching it as if it were a value risks reporting stale or misleading cycle paths and may poison later acyclic executions.

Rule:

- record constructive traces only after a successful commit;
- do not record aborted computations;
- do not record `CycleError` paths;
- if a cacheable query reads a dependency that raises `CycleError`, propagate the error and skip cache insertion.

This matches the existing invariant that failed reads should not record ordinary dependencies.

### D. Durability shortcut interaction

Constructive traces do not subsume durability.

Durability is a very cheap negative check:

> No input in this durability class changed since this cell was verified, so skip the dependency walk.

A constructive trace lookup is a more expensive positive reconstruction attempt:

> Dependencies changed or need verification; after obtaining fingerprints, try to reuse a previous output.

If both exist, durability should remain earlier in the pipeline:

1. current `verified_at >= current_revision` fast path;
2. durability skip if valid;
3. normal dependency verification;
4. only then, for opt-in cacheable queries, compute dependency fingerprints and attempt constructive reuse.

### E. Storage backend

For the stated goal of local editor/UI latency, start with **session-local bounded storage**, not distributed cache.

Candidate backends by stage:

| Stage | Backend | Purpose |
|---|---|---|
| Prototype | in-memory LRU `HashMap` | Measure whether cache hits can beat recomputation without serialization noise. |
| Local persistence | SQLite or append-only file plus content-addressed blobs | Reopen-project reuse on one machine. |
| Shared cache | CAS/KV object store | Cross-process or cross-machine reuse; out of scope until local persistence is proven. |

The first useful question is not "which distributed cache?" It is whether a session-local content cache wins on a real semantic workload.

## Required API Contract for Cacheable Queries

A general `Derived[T]` should not become cacheable automatically. An opt-in cacheable query would need a contract like this:

- stable query key;
- stable rule version;
- deterministic compute function;
- successful result type can be cloned or serialized;
- dependency fingerprints are available and cheap enough;
- cache lookup and insertion are bounded;
- failures and cycle errors are not cached;
- side effects, observers, and accumulator-only effects are either forbidden or explicitly outside the cached result.

A possible future shape:

```moonbit
// Sketch only — not an accepted API.
let typed = scope.cached_derived_map(
  query="type_of_function",
  version="typechecker-v3",
  key=function_id,
  compute=fn(id) { typecheck_function(id) },
)
```

This shape is intentionally closer to a Salsa-style query than to ordinary `Derived`. The user names the semantic query; the runtime does not infer identity from a closure.

## Engine Sketch for an Opt-In Prototype

A cacheable query should be layered on top of the current verifying-trace engine, not replace it.

Suggested order for a stale cacheable cell:

1. Run the normal revision fast paths.
2. Verify dependencies using the existing suspending scheduler.
3. Build a fingerprint vector from the dependencies that were actually read.
4. Look up `(query_id, query_version, key, dependency_fingerprints)` in the constructive trace store.
5. On hit:
   - install the cached output;
   - store the dependency list discovered for that trace;
   - set `verified_at` to the current revision;
   - preserve `changed_at` if the cached output equals the previous output, otherwise set it to the current revision.
6. On miss:
   - run the compute closure normally;
   - record dependencies through the existing tracking stack;
   - insert the constructive trace only if the computation succeeds.

The sketch hides a hard problem: step 3 requires dependency fingerprints, not just revisions. For local-only prototypes, fingerprints may come from user-provided `Hash` implementations or from already-interned semantic IDs. The engine should not compute deep structural hashes of arbitrary values by default.

## Better Near-Term Improvement from the Paper

The paper's static/dynamic dependency distinction suggests a lower-risk performance improvement:

> Add explicit static/applicative derived APIs for fixed dependency shapes.

Examples:

```moonbit
// Sketch only.
let full_name = Derived::map2(first, last, fn(f, l) { f + " " + l })
```

or:

```moonbit
// Sketch only.
let total = scope.derived_static([subtotal.id(), tax.id()], fn(read) {
  read(subtotal) + read(tax)
})
```

Potential benefits:

- no tracking-stack frame for common fixed-shape cases;
- no dependency-list diff after recomputation;
- fewer allocations in UI-shaped graphs;
- clearer user intent;
- preserves the current revision/backdating model.

For local editor/UI latency, this is more likely to pay off than constructive traces.

## Benchmark Gate Before Implementation

Treat any implementation as hypothesis-driven.

### Static/applicative fast path

- **Hypothesis:** fixed-dependency APIs reduce recompute overhead on UI-shaped graphs without changing semantics.
- **Comparator:** current `Derived` with dynamic dependency tracking.
- **Primary metric:** ns/recompute and allocation count on flat, layered, sparse, and tree UI benches.
- **Stop condition:** reject if improvement is within noise or if API complexity exceeds measured savings.

### Cacheable semantic query

- **Hypothesis:** opt-in constructive traces reduce latency for expensive deterministic semantic queries after undo/reopen/content-equivalent states.
- **Comparator:** current verifying-trace `DerivedMap` / `MemoMap` query.
- **Primary metric:** end-to-end read latency after edit/undo and warm-cache reopen.
- **Artifact:** benchmark table with hit rate, lookup cost, hash cost, recompute cost, memory use.
- **Stop condition:** reject if hit rate is low, hash cost dominates, or UI-shaped benchmarks regress.

## Recommendation

1. Keep the default engine as **suspending + revision verifying traces**.
2. Do not add automatic constructive traces to `Derived` / `Memo`.
3. Investigate static/applicative derived APIs first; they match the local editor/UI latency goal better.
4. Consider an opt-in cacheable-query prototype only after a real semantic workload exists and can provide stable query keys, rule versions, and cheap dependency fingerprints.
5. Defer persistent or distributed cache storage until a session-local prototype demonstrates a clear win.

In short: constructive traces are a useful vocabulary and a possible future query-cache layer. They are not the next default-runtime optimization for `incr`.
