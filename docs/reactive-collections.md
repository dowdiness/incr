# Reactive Collections — Research Summary

Survey of how incremental computation systems propagate changes through
collection-valued computations. Background material for deciding whether to
extend `incr` beyond whole-value change propagation.

**Status:** Research only — no decision recorded. See [roadmap.md](roadmap.md)
Phase 4E / Phase 5 for related open questions.

## The Problem

When a memo returns a collection — `Memo[HashMap[K, V]]`, `Memo[Array[Def]]`,
etc. — the current engine treats the whole return value as the unit of change.
Any downstream consumer re-runs when *any* key changes, even if it only cares
about one key. The ad-hoc fix is to structure the computation as
`MemoMap[K, V]` up front, but this requires knowing the key set in advance and
scatters the pattern across primitives (`MemoMap`, `InternTable`,
`TrackedCell`).

The research question: **how do other systems propagate *which keys changed*
instead of "the whole collection changed"?**

## Four Families of Approaches

### A. Signed-multiset delta streams

A collection is never materialized as a value — it *is* a stream of change
triples `(row, time, diff)` in an abelian group. Operators are functions on
streams that preserve this structure, so composition is closed:
`f(A ⊕ ΔA) = f(A) ⊕ f'(A)(ΔA)`.

**Examples:** Differential Dataflow, DDlog, Noria, Incremental λ-Calculus.

### B. Per-item signals / per-path reactive proxies

The collection is a container of individual reactive cells, one per stable
key (or lazily-materialized property path). Change propagation is the union
of the individual cells' propagations — no algebra of changes, just many
small dependency edges.

**Examples:** SolidJS stores, MobX observable arrays, Salsa's
split-into-tracked-per-ID idiom.

### C. Nominal memoization over persistent trees

The collection is a persistent tree whose nodes are memoized thunks. An edit
replaces only the root-to-leaf spine; every unchanged thunk is reused by
identity. Per-key granularity is *internal* to the collection's structure,
not exposed at the consumer API.

**Examples:** Adapton (nominal), Self-Adjusting Computation, Jane Street's
`Incremental` with functional data structures.

### D. Whole-value equality (status quo)

Collection = one opaque value. Change = `old != new`. Granularity comes only
from *choosing* to split the computation across many cells/memos.

**Examples:** Salsa default, Compose `SnapshotStateList`, Skip, `incr` today.

## Tradeoffs

| Family | Shines when | Falls over when |
|--------|-------------|-----------------|
| **A.** Delta streams | Updates small relative to collection; pipeline fits the relational/dataflow model; downstream benefits from deltas | Higher-order logic; operator derivatives hard to express; updates are genuinely whole-collection; arrangement state dwarfs recomputation cost |
| **B.** Per-item signals | Stable identities (IDs, keys); UI-style consumers reading narrow paths; unknown-at-compile-time access patterns | Dynamic key sets with per-key overhead; collective aggregations (`sum`, `join`) need a separate incremental primitive; GC of per-item cells |
| **C.** Nominal + persistent tree | Natural structural locality of edits; comfort with framework data structures; cheap allocation + memoization in host language | Third-party collection types; non-local access patterns (global folds); nominal naming discipline in generated code |
| **D.** Whole-value equality | Small collections; recomputation already cheap; correctness baseline | Large collections with narrow consumers — forces ad-hoc decomposition |

## Fit for `incr`

`incr`'s existing shape: pull-based `Signal`/`Memo` with backdating, push-based
`Reactive`/`Effect`, `HybridMemo`, semi-naive Datalog (`Relation[T]`),
`MemoMap[K, V]`, `TrackedCell[T]`, `InternTable[T]`.

- **Family B is the least-friction extension.** `MemoMap[K, V]` is already
  skeletal Family B; what's missing is an ergonomic `ReactiveMap[K, V]`
  façade pairing a `Signal[Set[K]]` (key set) with per-key memos. No engine
  rework; preserves pull-based backdating. This is the natural direction for
  "incremental name resolution"-shaped problems in downstream language
  tooling.

- **Family A fits the Datalog engine, scoped.** `Relation[T]` + semi-naive
  fixpoint already computes per-iteration deltas. Exposing them via an opt-in
  `DeltaObserver[T]` subscriber (push-shaped, parallel to `Effect`) is
  localized. **Pull memos must stay whole-value** — mixing deltas into pull
  memos breaks the "memo result is a function of inputs at a revision"
  invariant unless the delta store retains history per revision
  (Differential Dataflow's "arrangement").

- **Family C is powerful but mismatched.** Requires a built-in `IncrMap`
  primitive whose reads record per-spine-node dependencies. Substantial new
  category of primitive; not recommended without a concrete driver.

## Reading List

Organized for progressive study — read top-to-bottom within each section.

### Start Here (Foundational)

Read these first to establish the conceptual vocabulary.

1. **Acar — "Self-Adjusting Computation" (PhD thesis, CMU-CS-05-129)** —
   [PDF](https://www.cs.cmu.edu/~rwh/students/acar.pdf)
   The theoretical foundation. Establishes the Dynamic Dependence Graph
   (DDG) and change propagation. Everything else in Families B and C
   descends from this. Long; read the introduction and Chapter 2–3 first.

2. **Cai, Giarrusso, Rendel, Ostermann — "A Theory of Changes for
   Higher-Order Languages" (PLDI 2014)** —
   [inc-lc.github.io](https://inc-lc.github.io/) ·
   [PDF](https://inc-lc.github.io/resources/pldi14-ilc-author-final.pdf)
   The Incremental λ-Calculus. Introduces the `ΔA` / `⊕` / `⊖` vocabulary
   for change types. Critical for understanding *why* signed multisets form
   the "right" delta for bags.

### Family A — Delta Streams

3. **Differential Dataflow — mdbook** —
   [timelydataflow.github.io/differential-dataflow](https://timelydataflow.github.io/differential-dataflow/)
   Frank McSherry's guided tour. Chapters 1–3 (core concepts), 5 (arrangements).
   The book is the best single resource in this family.

4. **Differential Dataflow — source repo** —
   [github.com/TimelyDataflow/differential-dataflow](https://github.com/TimelyDataflow/differential-dataflow)
   When the book gets abstract, read `input.rs`, `trace/mod.rs`, and
   `operators/arrange/`. The `InputSession` API is the programmer-facing
   surface.

5. **Gjengset — "Noria: dynamic, partially-stateful data-flow for
   high-performance web applications" (OSDI 2018)** —
   [PDF](https://pdos.csail.mit.edu/papers/noria:osdi18.pdf) ·
   [PhD thesis](https://pdos.csail.mit.edu/papers/jfrg:thesis.pdf)
   Applies differential-dataflow-style deltas to SQL materialized views.
   The thesis introduces *upqueries* / partial state — a practical answer
   to "arrangements are expensive, can we compute them on demand?".

6. **DDlog tutorial** —
   [github.com/vmware-archive/differential-datalog](https://github.com/vmware-archive/differential-datalog/blob/master/doc/tutorial/tutorial.md)
   Datalog front-end over differential dataflow. Shows what Family A looks
   like from the programmer's seat when the backend is abstracted away.

### Family B — Per-Item Signals

7. **Salsa — overview** —
   [salsa-rs.github.io/salsa/overview.html](https://salsa-rs.github.io/salsa/overview.html) ·
   [tracked structs](https://salsa-rs.github.io/salsa/tutorial/ir.html)
   The closest architectural sibling to `incr`. Tracked structs are the
   canonical Family B pattern: decompose a coarse query into per-ID tracked
   functions so downstream consumers read only the field they need.

8. **Salsa issue #41 — "Push-based invalidation"** —
   [github.com/salsa-rs/salsa/issues/41](https://github.com/salsa-rs/salsa/issues/41)
   Long-running design discussion. Shows what a pull-first system looks
   like when it grapples with exposing deltas. Directly relevant to
   `incr`'s `HybridMemo` design choices.

9. **SolidJS — stores** —
   [docs.solidjs.com/concepts/stores](https://docs.solidjs.com/concepts/stores) ·
   [mapArray](https://docs.solidjs.com/reference/reactive-utilities/map-array)
   Lazy per-property-path signal creation. `mapArray`'s per-item value
   caching is a good reference for any `ReactiveMap` design in `incr`.

10. **MobX — collection utilities** —
    [mobx.js.org/collection-utilities.html](https://mobx.js.org/collection-utilities.html)
    Proxy-based per-index observation. Similar philosophy to Solid but with
    a different granularity story — useful for comparing API ergonomics.

### Family C — Nominal Memoization over Persistent Trees

11. **Hammer, Dunfield, Headley, Labich, Foster, Hicks, Van Horn —
    "Incremental Computation with Names" (OOPSLA 2015)** —
    [PDF](https://www.cs.tufts.edu/~jfoster/papers/oopsla15.pdf)
    Nominal Adapton. Introduces *first-class names* as the mechanism for
    stable thunk identity across runs. Read after Acar's thesis.

12. **Adapton project site** —
    [adapton.org](http://adapton.org/)
    Collected papers, implementations (Rust, OCaml), and the RAZ (Random
    Access Zipper) data structure — a persistent sequence tuned for
    Adapton's memoization.

### Family D — Whole-Value (for contrast)

13. **Klipp — "Implementing snapshot-aware data structures"** —
    [blog.zachklipp.com](https://blog.zachklipp.com/implementing-snapshot-aware-data-structures/)
    How Jetpack Compose's `SnapshotStateList` works. The *limits* of
    Family D are visible here: one `StateObject`, one modification
    counter, whole-list invalidation.

14. **Skip — "How memoization works"** —
    [skiplang.com/blog/2017/01/04/how-memoization-works.html](https://skiplang.com/blog/2017/01/04/how-memoization-works.html)
    Archived but still relevant. Shows an Adapton-style pull engine
    without a dedicated collection primitive.

### Adjacent / Optional

15. **Jane Street — `Incremental` library** —
    [opensource.janestreet.com/incremental](https://opensource.janestreet.com/incremental/)
    OCaml production-grade incremental computation. Similar pull model to
    `incr` and Salsa; their `Incr_map` module is a real-world Family C +
    Family B hybrid worth studying if Family C becomes interesting.

16. **Abadi, McSherry, et al. — "Naiad: A Timely Dataflow System" (SOSP
    2013)** —
    [PDF](https://www.microsoft.com/en-us/research/publication/naiad-a-timely-dataflow-system/)
    The timely-dataflow foundation beneath Differential Dataflow. Required
    only if you want to understand *why* differential dataflow's time
    model is what it is.

17. **Giarrusso, Régis-Gianas, Schuster — "Incremental λ-Calculus in
    Cache-Transfer Style" (ESOP 2019)** —
    Link via [inc-lc.github.io](https://inc-lc.github.io/)
    Extends ILC so intermediate results are preserved between runs.
    Closes the loop between Family A (delta streams) and Family D (value
    memoization).

## Suggested Study Order

Minimal path to productive understanding:

1. Acar thesis, Ch. 1–3 — DDG + change propagation vocabulary
2. ILC PLDI 2014 — change type vocabulary
3. Differential Dataflow mdbook Ch. 1–3 — concrete Family A
4. Salsa overview + tracked structs — concrete Family B
5. Nominal Adapton OOPSLA 2015 — concrete Family C

After these five, the remaining references fill in breadth.
