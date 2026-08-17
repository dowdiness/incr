# Incr Next K0 product and kernel contract

**Reader:** Maintainers and implementers changing the adopted Incr Next
semantic baseline.

**Decision:** Define Incr Next as a pre-1.0 sibling product with a small,
recipe-oriented pull kernel. Select the K1 semantic contract and module seams;
do not change the current `dowdiness/incr` module.

**Keep until:** This K0 contract is superseded by an explicit contract change.

**Disposition:** Retain as the normative K0 contract under the accepted Incr
Next sibling-product ADR. K1 is complete.

---

## Product definition

Incr Next is a typed incremental query kernel for snapshot-determined
computations. It lazily verifies last-successful forward dependency traces and
recomputes only when reuse cannot be proved.

Its first product is not a UI framework, effect system, or compatibility layer.
The interface is intentionally smaller than current Incr:

```text
Store
Region
Source[T]
Query[K, V]
View[V]
QueryContext
Transaction
Revision
structural error types
```

The interface is the test seam. Verification, memo identity, active invocation
tracking, `ChangeEpoch`, cutoff storage, and trace representation remain private.

## Repository and module seam

K1 established two workspace sibling modules:

```text
incr_next/             module dowdiness/incr_next
incr_next_testkit/     module dowdiness/incr_next_testkit
```

The kernel begins as one package with multiple files so opaque typed recipes,
`QueryCore[K,V]`, typed memo maps, and dependency closures can share private
representations. Do not split the kernel into shallow forwarding packages.

The testkit is a separate module with these package import rules:

```text
model/                  operation scripts, logical IDs, normalized outcomes
fresh/                  independent memo-free evaluator
incremental_adapter/    imports dowdiness/incr_next
scenarios/              reusable workloads
differential/           compares normalized observations
```

`fresh/moon.pkg` must not import `dowdiness/incr_next`. Fresh and incremental
adapters do not share `View` values or kernel internals; they consume the same
operation scripts and compare normalized outcomes.

## Facts from evidence

### Current repository facts

- `incr/moon.mod` publishes `dowdiness/incr` version `0.15.0`.
- `moon.work` already contains independent sibling modules including `incr`,
  `incr_tea`, and `dataflow`.
- The current Incr core remains uncommissioned; Incr Next is a separate product
  track.
- MoonBit packages provide the private compilation seam needed for one kernel
  package and an independently audited Fresh package.

### Research evidence

These commits remain checked provenance and are not production dependencies.
The accepted K1 implementation is merged:

| Issue | Commit | Evidence established |
|---|---|---|
| #460 | `39569001f37bece2790f308c024187f4b43feba9` | Opaque keyed View recipe and ownership direction |
| #461 | `4e2e2650851ab0677a88b9904b6bb0c79650a442` | Memo-free Fresh evaluator and atomic transaction oracle |
| #462 | `d54e78087d3837eccee0c55247adb90c07625869` | Incremental parity, forward verification, clocks, and failure atomicity |
| #463 | `b0244adaea59e0684bac53026220c9bd0d247bea` | Invocation-level cycle detection |
| #464 | `c640f65124b2a0eb362f3f08a1b6220e6647b6b7` | Typed cutoff and backdating |
| #465 | `5e79f111d92ee49645687f2a548b6e12f2063b14` | Explicit proof loss and rematerialization |

K1 consolidated these semantics into one implementation. It does not import,
materialize, or layer the evidence providers.

## Selected K1 interface

### `View[V]`

`View[V]` is opaque and non-callable. It has no public `get`, `read`, or call
operator. A Query View privately captures its typed `QueryCore[K,V]` and key;
a Source exposes one canonical View. A View identifies a recipe, not a memo
incarnation, and therefore survives memo eviction.

Reads enter through exactly two capabilities:

```text
Store::read(view)          root read
QueryContext::read(view)   tracked nested read
```

### `QueryContext`

`QueryContext` is the selected public name. `EvalCtx` remains only a historical
evidence name. Kernel internals may use `EvalSession`, `EvalFrame`,
`TrackingFrame`, and `ActiveInvocation`.

A `QueryContext`:

- exists only during one Query invocation;
- observes the committed snapshot captured by its root read;
- records dynamic dependencies through `read`;
- exposes `revision`, which returns public `Revision` and records a tracked
  Revision-clock dependency;
- expires when the callback exits.

It exposes no write, root-read, Region mutation, debug counter, trace, `EvalId`,
or current-Query identity. Use after callback exit returns
`ExpiredQueryContext`.

### Query compute and failure channels

The conceptual callback type is:

```text
(QueryContext, K) -> Result[V, ReadError]
```

The outer `Result` carries structural kernel failures. Domain failure belongs
inside `V`, commonly by choosing `V = Result[Value, DomainError]`.

A Query author can syntactically catch `ReadError`; the admissible caller
contract requires nested structural errors to remain transparent. A callback
must not convert a failed tracked read into an apparently successful value.
Expected callback outcomes use `Result`; uncatchable aborts and arbitrary FFI
failures are outside K1 guarantees.

### Source and Transaction

`Source[T]` has no direct public setter. All writes are staged through a
`Transaction`. Source does not require `T : Eq`; every successful nonempty
transaction publishes, including an equal-value write.

The detailed write and lifetime contract is in
[Incr Next K0 Lifetime and Transactions](2026-08-13-incr-next-lifetime-and-transactions.md).

## Clocks and snapshot

Each Store owns two clocks; neither clock is Region-scoped or module-global:

```text
StoreCore
  Revision       public committed-state clock for that Store
  ChangeEpoch    private verification/lifecycle clock for that Store
```

The separate module-global execution gate coordinates callback phases across
all Stores but owns no clock. Operations on Store A never advance Store B's
clocks.

- Successful nonempty transaction on a Store: advance that Store's `Revision`
  once and `ChangeEpoch` once, including equal-value publication and one
  atomic transaction spanning multiple Regions of the Store.
- Empty, rolled-back, poisoned, or rejected transaction: advance neither.
- First successful close of any Region in a Store: advance that Store's
  `ChangeEpoch` once and leave its `Revision` unchanged.
- Duplicate or rejected close: advance neither.

One root read captures its Store's committed `Revision`; every same-Store
cross-Region nested read observes that snapshot. A commit publishing to any
Region in the Store is visible only to a later root read and advances the one
Store Revision. Nested reads cannot observe transaction staging or another
committed snapshot. `QueryContext::revision()` records a dependency on that
Store's Revision clock, so any successful nonempty same-Store transaction can
make it red. Region close alone leaves the Revision dependency green while its
closed Source/Query dependency follows the separate lifetime rules.

## Alpha execution gate

K1 uses a module-global, single-threaded execution state:

```text
Idle | Evaluating | Transacting
```

While evaluating or transacting, root reads, transactions, and Region mutation
are rejected even when attempted through another Store. All catchable exits
restore `Idle`. Rejected operations do not invoke user `Hash`/`Eq` or mutate
phase, clocks, traces, memos, or Source state.

This is a conservative alpha safety limit, not a permanent claim that
independent Stores can never execute concurrently. Thread-local gates,
Store-local scheduling, and parallel independent Stores remain deferred.

## Incremental semantic contract

### From-scratch consistency

For every admitted operation script and demanded root:

```text
normalize(IncrementalRead(state, root))
=
normalize(FreshRead(state, root))
```

Fresh is independently implemented and shares only scripts, logical IDs, and
normalized observations with the incremental adapter.

### Last-successful authority

A successful recompute atomically replaces:

```text
value
forward trace
verified_at
changed_at decision
```

A failed recompute returns the current structural error without a stale
fallback and preserves the target's previous successful memo identity, value,
trace, `verified_at`, and `changed_at`. An initial failure installs no memo.
Successful upstream work completed during the attempt remains valid.

Verification relies only on the last-successful forward trace. The pull kernel
stores no reverse subscriber edges and no globally erased memo registry.

### Dynamic traces and cycles

A successful recompute always installs its newly observed trace, including when
cutoff declares its value propagation-equivalent. Branch changes therefore
replace stale dependencies.

Cycle identity is one typed invocation:

```text
QueryCore identity + key equality under K::Eq
```

Finite recursion over distinct keys is legal. Cycle detection runs before a
same-epoch memo hit so an old memo cannot conceal active re-entry. Structured
exits remove active keys and frames.

### Typed cutoff and backdating

Cutoff is selected once by the Query. K1 supports only explicit policies proven
by #464: always changed, structural `Eq`, and a type-owned propagation relation.
Exact public constructor and trait names are confirmed by compile probes before
the first public `.mbti` is accepted; arbitrary per-Query predicates are not
public K1 surface.

The relation is one-sided evidence:

```text
Equivalent(old, next)
  implies every admissible downstream observer may reuse its prior observation
```

After every successful recompute, K1 retains the newest value and newest trace.
When equivalent, it preserves the old `changed_at`; otherwise it stamps the
current `ChangeEpoch`. Cutoff never runs for first success, cache hit, green
verification, or failed recompute.

### Private proof loss

K1 implements typed per-key eviction privately for white-box testing. Eviction
removes value, trace, stamps, and memo identity without changing either clock,
Source state, Query definition, cutoff policy, or View recipe. Rematerialization
creates a new memo and conservatively stamps the current `ChangeEpoch` because
prior equivalence proof was lost. Public eviction policy and LRU are deferred.

## Snapshot-value caller contract

The kernel never mutates committed Source values or cached Query results. It
does not promise a generic defensive copy.

For as long as a key, Source value, or Query result is captured, committed, or
cached, everything reachable through external aliases must remain
observationally immutable. The independent testkit retains expected-divergence
counterexamples for mutable keys, mutable Source payloads, and mutable memo
results.

Applications that require mutable objects use immutable values, persistent
collections, read-only facades, explicit copies in adapters, or a tracked
`(reference, semantic_version)` pair.

## Functional core and imperative shell

The functional core decides verification, trace replacement, cycle outcomes,
cutoff/backdating, transaction validation, clock transitions, and structured
diagnostics from explicit inputs. It may use local mutation only to build a
returned value.

The imperative shell owns phase transitions, capability expiry, Source payload
replacement, Region close actions, allocation, and user-callback invocation.
It applies core decisions atomically and restores trusted phase state on every
catchable exit.

## K1 acceptance

K1 is not accepted until all of the following pass:

- independent Fresh/Incremental differential scenarios;
- repeated read in one `ChangeEpoch` performs no recompute;
- unrelated publication can green-verify an observed root;
- dynamic branch trace replacement;
- target-local failure atomicity and recovery;
- invocation-level cycle detection and cleanup;
- cutoff-equivalent recompute preserves `changed_at` and skips at least one
  downstream compute while retaining the newest value and trace;
- private eviction/rematerialization and proof-loss behavior;
- Region close, cross-Region branch-away, and surviving-View behavior;
- native, JS, and wasm-gc checks/tests;
- native reference-count/finalizer ownership evidence;
- compile-negative capability and package-import probes;
- validation order is `moon fmt`, `moon info`, immediate generated `.mbti`
  inspection, then affected `moon check` and `moon test`;
- current `dowdiness/incr` unchanged and no dependency from Incr Next to it.

Work-count assertions are gates; K1 has no wall-clock threshold.

## Deferred product choices

K1 excludes public eviction, automatic LRU, Mount/reactive roots,
Program/Port/Formula, reducers and history-sensitive state, actions/resources,
async effects, parallel evaluation, cross-Store direct reads, current-Incr
compatibility, persistent caches, and public debug/explain.

Internal counters needed to prove K1 work counts are permitted but cannot be
read through `QueryContext` or affect Query results. A public content-free
observability interface is a separate K2 design.

## Existing API First boundary

K1 may reuse ideas and pure value operations, but it must not depend on current
`dowdiness/incr` handles or runtime. Before every new definition, inspect the
project and actual MoonBit core APIs fitting the data shape. The required
candidate set and validation commands are preserved in
[completed Plan 015](https://github.com/dowdiness/incr/blob/58469934c5644686992688bc7a9f1685326a081d/plans/015-incr-next-kernel-alpha.md).
