# Incr Next explicit memo eviction and recipe rematerialization

- **Reader:** Incr maintainers evaluating explicit proof loss in the next pull kernel.
- **Decision:** Determine whether one typed memo entry can be forgotten and safely rebuilt; do not adopt a production eviction API.
- **Keep until:** The Incr Next retention direction is adopted, rejected, or superseded by stronger evidence.
- **Disposition:** Retain as checked spike evidence until that decision, then preserve the durable conclusion in an ADR or delete the spike.

This standalone spike asks one question:

> Can a typed per-Query memo entry be explicitly evicted while preserving its
> Query definition, opaque View recipes, and downstream forward dependencies,
> so later reads rematerialize a fresh memo with exact FreshEval outcomes and
> preserve the cutoff, cycle, failure, and ownership rules through #464, without
> advancing Revision or ChangeEpoch, adding reverse subscriber edges, or using a
> global erased registry?

Run from the repository root:

```bash
bash examples/spikes/incr_next_memo_eviction/run.sh
```

The provisional answer is **Pass with constraints** for the finite workloads
below. This is executable evidence, not a proof for every admissible graph and
not authorization for a production kernel or API.

## Evidence isolation

The harness runs and guards every preceding evidence tree:

```text
#461 incr_next_fresh_evaluator       unchanged
#462 incr_next_incremental_parity    unchanged
#463 incr_next_cycle_detection       unchanged
#464 incr_next_cutoff_backdating     unchanged
     incr_next_memo_eviction
     ├─ fresh_provider
     ├─ incremental_provider
     ├─ consumer
     ├─ native_rc
     └─ negative
```

Unchanged provider, cycle, cutoff, and compiler-boundary files are symlinks to
#464 and checked against an exact manifest. Query/error files are a package-local
fork because QueryCore and MemoEntry are private. The consumer reruns the entire
#464 workload before eviction-specific scenarios.

## Eviction means proof loss

Eviction is not a semantic state change. It leaves these values untouched:

```text
Source state
Revision
ChangeEpoch
Query definition and compute recipe
Query-owned cutoff policy
opaque View recipes
surviving downstream dependency closures
```

It removes one typed entry and therefore forgets:

```text
memo value
last-successful forward trace
verified_at
changed_at
MemoId
old value needed for cutoff comparison
```

After eviction, `changed_at` can no longer mean the exact historical epoch at
which meaning last changed. It is a **conservative propagation stamp**: the
earliest boundary for which the current memo still carries sufficient evidence
of downstream equivalence.

The verification invariant remains:

```text
upstream.changed_at <= downstream.verified_at
  implies the downstream's prior observation is equivalent to the current
  upstream value under the declared admissible observer discipline
```

When eviction destroys that proof, rematerialization stamps the current
ChangeEpoch. This may recompute a downstream Query unnecessarily. That false
negative is safe; skipping without evidence is not.

## Evidence-only control seam

Both providers expose:

```moonbit
query.evict_memo(key) -> Result[Bool, EvictionError]
```

Incremental returns:

```text
Ok(true)   one Eq-equal typed memo existed and was removed
Ok(false)  no memo existed; no-op
Err(...)   Region lifetime or global execution phase rejected the operation
```

Fresh owns no memo, so an idle/open call is a validated semantic no-op returning
`Ok(false)`. Its read semantics remain from-scratch evaluation. Both providers
reject evaluation- and transaction-time attempts and reject an operation after
Region close.

The operation is permitted only while the module-global execution mode is Idle.
It validates the Query's captured Region generation before consulting phase,
and both checks precede any caller-defined Hash/Eq operation. A hostile-key
probe establishes that rejected Fresh operations invoke neither trait. Eviction
does not enter an EvalSession and changes neither clock. The single-threaded
Region close path exposes no user callback in which a reentrant eviction can be
attempted; post-close rejection is the checked lifecycle boundary.

This control seam is not a production API proposal. There is no LRU, recency
state, capacity budget, pinning, weak reference, background task, or automatic
selection policy.

## Typed per-key removal

Incremental QueryCore continues to own:

```text
Map[K, MemoEntry[V]]
```

`evict_memo` uses `K : Hash + Eq`, checks membership, and removes only the
Eq-equal key. It neither scans other Queries nor publishes an erased key. Query
identity remains `(QueryCore identity, key under K::Eq)`; MemoId identifies only
one physical memo incarnation.

Absent and duplicate operations increment evidence counters but do not mutate
the table or clocks. Rejected operations do not mutate a memo. Region close
continues to clear all remaining entries, compute state, active keys, and the
cutoff policy.

## Rematerialization

A read after successful eviction follows the existing no-entry path:

```text
validate metadata and EvalCtx
check active invocation before cache lookup
enter active slow scope
compute value and temporary trace

failure or Cycle:
  return current ReadError
  install no memo
  call cutoff zero times
  return no stale fallback

success:
  allocate a new MemoId
  install current value and trace
  verified_at = current ChangeEpoch
  changed_at = current ChangeEpoch
  call cutoff zero times
```

The old changed_at, old value, and old MemoId are unavailable by design. A later
successful recompute while the new entry remains retained again uses #464's
normal cutoff relation.

Two equal-key Views continue to share the newly installed entry. A downstream
Dependency closure captures QueryCore and typed key, not MemoId or MemoEntry, so
it can rematerialize an absent child.

## Executable workloads

### Surviving View and equal-key sharing

One View reads MemoId M1, explicit removal returns `Ok(true)`, duplicate removal
returns `Ok(false)`, and the same View creates M2. M1 and M2 differ. A distinct
View with an Eq-equal key then reuses M2. Revision and ChangeEpoch are unchanged,
and rematerialization calls cutoff zero times.

Fresh performs the same reads around an `Ok(false)` semantic no-op and returns
the exact same root outcomes.

### Downstream trace and same-epoch parent cache

A parent memo records a child Query dependency, then only the child entry is
removed. Reading the parent in the same ChangeEpoch returns its same-epoch cache;
the child remains absent because eviction did not change semantics or advance
the clock.

After an unrelated commit, parent verification invokes its surviving child
Dependency closure. The child rematerializes with a new MemoId and current
changed_at. That conservative stamp forces the parent to recompute even though
the child's value is equivalent. This is expected proof-loss work, not a parity
failure. A later retained equivalent child recompute calls cutoff once,
preserves that new stamp, and skips the parent.

### Dynamic trace

A selected parity Query first memoizes the left branch, is evicted, then
rematerializes while the right branch is selected. Its new trace contains only
`{mode,right}`. A later left-only commit leaves it green; a right change makes it
red. The old trace is never restored.

### Failure and Cycle

A successful memo is evicted before current computation is changed to another
ReadError. The read returns the current error, installs no memo, calls cutoff
zero times, and offers no stale fallback. Recovery creates a new MemoId.

The equivalent Cycle workload compares the normalized copied QueryId witness,
not only the error kind, and proves the same rules plus empty active maps, empty
finished session stack, temporary-trace cleanup, and successful recovery after
the cycle is removed.

### Per-key isolation

Two keys own two MemoIds. Removing key A leaves key B's entry and MemoId
untouched; B is a cache hit while A rematerializes with a third Query-local
MemoId. The memo table returns to two entries.

### Phase and lifetime rejection

Fresh and Incremental both reject eviction invoked from Query computation and an
empty Transaction callback. The target Incremental memo remains byte-for-byte
equal at the public debug boundary, and both clocks remain unchanged. A
post-close attempt returns ClosedRegion without advancing either clock again.

## Ownership evidence

The native RC executable reruns #463/#464 ownership checks and adds the following
discriminating cases:

- removing an entry releases its table-owned value;
- removing its trace and then closing the child Query releases a key that a stale
  trace would otherwise retain;
- an external value alias remains live after table removal and releases only
  when that alias leaves scope;
- a surviving View retains its own key after the table key is removed and after
  Region close, then releases it when the View leaves scope;
- a parent dependency trace retains a child QueryCore/key recipe after the child
  memo and Region are cleared, then releases it with the parent memo;
- removing key A releases only A's value while key B remains owned;
- rematerialization releases the old incarnation before retaining the new one;
- Region close releases every remaining memo and policy-owned reference.

All 22 marker categories finish with zero live objects. Finalization counts
separate table ownership from equal temporary lookup keys, Views, external
aliases, and downstream traces.

A native white-box test supplies a private cutoff closure with a separate
external marker. Memo eviction leaves the policy available and alive; Region
close clears and finalizes it. No arbitrary per-Query predicate is added to the
public interface.

## Compiler and interface boundaries

The inherited negative probes retain opaque View/EvalCtx/Transaction and cutoff
boundaries. New probes establish that View cannot authorize eviction and
external code cannot name private MemoEntry.

Generated interfaces expose only the evidence seam, EvictionError, and immutable
counter snapshots. MemoEntry, typed memo Map, CutoffPolicy, ExecutionMode,
phase helper, dependencies, active keys, and tracking frames remain private.
There is no reverse subscriber edge or store-wide erased registry.

## Reuse check

Reused project evidence and APIs:

- #461 opaque View/EvalCtx/Transaction and atomic transaction oracle;
- #462 typed memo table, last-successful forward trace, ChangeEpoch, and
  target-local failure atomicity;
- #463 active-before-cache cycle ordering and structured cleanup;
- #464 successful-recompute cutoff and Query-owned policy lifecycle;
- production DerivedMap lazy recreation, Runtime disposal, and pull GC tests as
  read-only analogues, not as the spike evaluator.

MoonBit core APIs checked and reused:

- `Map::contains` plus `Map::remove` perform typed per-key removal;
- `Hash` and `Eq` define logical invocation identity;
- `Option`, `Result`, and `Ref` preserve explicit state/error boundaries;
- `Array`, ArrayView operations, and fold retain trace and witness handling;
- String and StringBuilder support normalized evidence output.

Set was rejected because each key owns a full MemoEntry. Bytes/BytesView and
Buffer do not fit typed memo ownership. cmp/math helpers do not decide equality
or stamps and were not used.

## Constraints and non-goals

The admissibility contracts through #464 still apply: deterministic Query and
cutoff behavior, stable Eq/Hash keys, snapshot values, structural error
transparency, and each result type's declared downstream observer discipline.

No memo tombstone, prior changed_at certificate, semantic fingerprint, or old
value is retained. Those would be different retention policies rather than full
memo eviction. One entry's removal cuts only edges owned by that entry; other
same-Query entries may keep a forward-trace SCC alive until their own removal or
Region close.

Automatic LRU, capacity budgets, recency tracking, pins, weak references,
background GC, dependency deduplication, iterative verification, Mount,
Program/Port/Manifest, Canopy integration, parallel evaluation, benchmarks, and
production naming remain outside this spike.

No ADR is needed because this is research evidence and does not adopt Incr Next
as a product direction.
