# Issue #461: fresh evaluator and atomic transaction oracle

**Status:** Evidence-only standalone spike. It is not production `incr/` code.

**Reader:** Maintainers defining the from-scratch side of a future Incr Next
consistency oracle.

**Decision:** Use this memo-free evaluator as the provisional reference
semantics for `Source`, `Query`, opaque recipe `View`, and `Transaction`.

**Keep until:** A minimal incremental evaluator is compared against the same
transactions and roots.

**Disposition:** Preserve this spike only on its evidence branch. Do not merge
it into main, alter the current retention brief, or treat it as production
kernel authorization.

## Question and command

Can `Source[T]`, `Query[K,V]`, opaque recipe-backed `View[V]`, and
`Transaction` define a no-memo evaluator in which every root read observes one
committed Revision and every successful transaction publishes all staged
writes atomically?

Run from the repository root:

```bash
bash examples/spikes/incr_next_fresh_evaluator/run.sh
```

## Reference semantics

```text
Eval : CommittedState × View[V]
    -> Result[V, ReadError]

Commit : CommittedState × StagedWrites
      -> Result[CommittedState, TransactionError]
```

A View recipe is parameterized by the evaluator:

```text
View[V]
├─ private metadata
└─ private recipe : EvalCtx -> Result[V, ReadError]
```

A Source View recipe captures `SourceCore[T]`. A Query View recipe
existentially packages `QueryCore[K,V] + K`. The recipe identifies what to
evaluate; EvalCtx determines how it is evaluated. `View` has no public
`get`, `read`, or call operator.

`QueryCore[K,V]` contains only identity, Region lifetime, compute closure, and
a debug execution count. It has no memo, cached value, dependency trace,
cutoff, changed revision, or verified revision. Repeated reads recompute, and
a diamond evaluates its shared Query once per incoming read path.

## Ownership graph

```text
Store -> StoreCore { identity, Revision, allocator, counters }

Region -> RegionCore
          ├─ RegionEpoch
          └─ close actions ──> SourceCore[T] / QueryCore[K,V]

Source[T]
├─ SourceCore[T] ──> RegionEpoch
└─ canonical View[T] ──> SourceCore[T]

Query[K,V] ──> QueryCore[K,V] ──> RegionEpoch
View[V] recipe ──> QueryCore[K,V] + K
```

SourceCore and QueryCore never point to RegionCore. Region close actions
therefore have no library-controlled return edge. Close clears committed Source
payloads and Query compute captures before the action array is cleared and the
epoch is sealed. Surviving Views then return `ClosedRegion`.

Source allocates one canonical View. Repeated `source.view()` calls return that
same recipe handle. Source has no direct write method.

## Evaluation capability and global phase

EvalCtx is opaque and has no public constructor. `Store::read` validates View
owner and Region generation, enters one module-global single-thread phase,
captures the Store Revision, constructs an EvalCtx, invokes the recipe, expires
the context, and restores Idle.

```text
ExecutionMode
├─ Idle
├─ Evaluating(StoreId, EvalId)
└─ Transacting(StoreId, TransactionId)
```

Only `EvalCtx::read(view)` is legal during evaluation. Top-level reads,
transactions, and Region source/query/close operations are rejected while a
Query runs. The guard is module-global, so using another Store does not evade
the capability rule. A captured EvalCtx returns `ExpiredEvalContext` after the
root evaluation ends.

The guarantee is limited to Incr capabilities. Arbitrary closure-captured
`Ref`, clock, random source, FFI, DOM, network, and global mutation remain the
Formula author's responsibility. Query and transaction callbacks also must
return their declared `Result` rather than aborting; an uncatchable abort is
outside this prototype and may leave the module-global guard active.

## Atomic Transaction

Transaction stores heterogeneous writes in a transaction-local typed-key map:

```text
Map[SourceId, StagedWrite]

StagedWrite
└─ apply closure { SourceCore[T] + new T }
```

There is no persistent erased registry. Replacing the map value implements
last-write-wins and releases the superseded staged closure.

The executable fixes these invariants:

1. `set` only stages; committed Source values do not change in the callback.
2. Owner and Region generation are validated before creating the closure.
3. Any failed set poisons the Transaction even when its Result is ignored.
4. Callback failure or poison clears every staged closure and changes no Source.
5. A successful nonempty callback applies every prevalidated closure.
6. Revision advances exactly once after all apply closures run.
7. Empty success does not advance Revision.
8. Multiple writes to one Source apply only the final value.
9. Every nonempty success advances Revision, including an equal-value write;
   Source has no Eq bound.
10. Root reads and Region mutation are rejected throughout the callback.
11. A captured Transaction returns `ExpiredTransaction` after completion.

No root can observe apply ordering because the global phase remains
`Transacting` until commit or rollback is complete.

## Errors and domain failures

`ReadError`, `TransactionError`, and `RegionError` contain structural failures
only: provenance, closed lifetime, expired capability, and illegal phase.
Application failures remain in the value type, for example
`Query[K, Result[Value, DomainError]]`.

Cycle is intentionally absent. This oracle currently defines only finite,
acyclic Query evaluation.

## Caller-owned snapshot contracts

The executable records two counterexamples rather than pretending the type
system prevents them.

A Query key must retain the same invocation meaning for the complete lifetime
of every View that captures it. Merely preserving Hash/Eq or evicting a memo is
not enough: mutating a captured key changes what the same View means even in
this memo-free evaluator.

Source values and Query results must be observationally immutable within one
Revision. Mutating a Source payload through an external alias changes a fresh
read without a Transaction or Revision advance. Large mutable values therefore
need immutable snapshots or an explicit semantic version published through a
Source transaction.

## Executable evidence

The native and wasm-gc consumer covers:

- direct Source View, Unit Formula, and keyed Query;
- fresh chain recomputation on every root read;
- diamond duplication with no memo;
- dynamic branch reads only the selected Source;
- one captured Revision throughout a root;
- domain error as a value;
- atomic two-Source commit and blocked intermediate root read;
- callback rollback and sticky poison rollback;
- cross-Store set rejected before staging;
- last-write-wins, equal-value commit, empty commit, and expired Transaction;
- same/other-Store root and transaction rejection during Query evaluation;
- Region mutation rejection during evaluation and transaction;
- expired EvalCtx;
- metadata-first CrossStore read and ClosedRegion behavior;
- mutable-key and mutable-payload contract counterexamples.

## Native RC evidence

The native package uses the V12.4 external-object finalizer technique. C tokens
update live/finalized counters; they are proxy evidence for compiled ownership
paths, not direct destructors on every MoonBit object.

It verifies:

- Region close releases a committed Source payload and Query compute capture
  while their Views survive;
- callback rollback releases a staged payload;
- ignored cross-Store set poisons and releases the earlier staged payload;
- successful commit releases the old committed payload;
- last-write replacement releases the superseded staged payload during the
  callback;
- final Region close releases the current committed payload.

## Existing API First reuse check

Project patterns checked and reused:

- current kernel's module-global single-thread phase sentinel;
- current batch model's closure-based staging, rollback, and single Revision
  advancement;
- V12.4 native external-object finalizer evidence;
- issue #460's opaque EvalCtx-parameterized recipe ownership direction.

MoonBit core candidates checked were `Map`, `Hash`, `Eq`, `Option`, `Result`,
`Array`, and `Ref`. The spike uses `Map` only for transaction-local
last-write-wins staging, `Option` for closable payload/compute and poison state,
`Result` for structural errors, `Array` for Region close actions, and `Ref` for
explicit state transitions and capability expiry. Mutation is limited to
revision/identity allocation, committed Source replacement, transaction-local
staging, lifecycle transitions, counters, and deliberate contract probes.

## Result

**Pass with constraints.** The four concepts define an executable no-memo
reference evaluator and atomic staged transaction oracle. This establishes the
future `FreshEval` side of a consistency comparison; it does not establish
from-scratch consistency until a separate incremental evaluator is run against
it.

## Non-goals and limits

No memo, dependency trace, invalidation, changed/verified revision,
cutoff/backdating, eviction, cycle detection, Mount, Program/Port/Manifest,
Action/Resource, AcceptedDerived, Accumulator, Datalog, Canopy integration,
parallel evaluation, performance optimization, current V12 change, or
production authorization is included.

No replacement-kernel authorization and no ADR are included. An ADR becomes
appropriate only after a later incremental evaluator satisfies the reference
oracle and the product direction is adopted.
