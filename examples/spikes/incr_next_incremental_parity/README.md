# Issue #462: incremental parity evaluator

**Status:** Evidence-only standalone spike. It is not production `incr/` code.

**Reader:** Maintainers comparing a fresh evaluator with a from-scratch
incremental evaluator before authorizing any replacement kernel.

**Decision:** Keep the issue #461 fresh provider unchanged and compare it with
this memoizing provider through the same explicit operation/read workloads.

**Keep until:** The evaluator contracts are either adopted by a later kernel or
replaced by a stronger oracle.

**Disposition:** Preserve as a checked spike. Do not use `@incr` as an evaluator,
modify the production tree, or treat this evidence as kernel authorization.

## Question

Can a small incremental evaluator preserve the #461 values, structural errors,
atomic transaction behavior, and public Revision observations while adding
keyed memo reuse, dynamic dependency traces, and ChangeEpoch-based verification?

The consumer constructs a fresh graph and an incremental graph separately, runs
the same operation/read script, normalizes the values/errors/revisions, and
prints the full state and counters. Reads are operations in the history, not
post-hoc probes.

## Contracts

- `Source[T]`, `Query[K: Hash + Eq, V]`, opaque recipe `View[V]`, capability-only
  `EvalCtx`, and `Transaction` are the complete provider surface. Query compute
  is deterministic in its immutable key meaning and tracked semantic inputs.
  A structural `ReadError` from `ctx.read` must be propagated as that
  invocation's `Err`; converting it to `Ok` is outside the admissible contract.
- `EvalCtx` has no public constructor or `eval_id` accessor. `View` has no public
  call, `get`, or `read`; recipe success is the private value-plus-Dependency
  boundary. A root read records no dependency.
- `Revision` and `ChangeEpoch` are separate clocks. A nonempty/equal successful
  commit advances both. The first successful Region close advances ChangeEpoch
  only. Empty, rollback, rejected, and duplicate close operations advance
  neither clock.
- `StoreCore` has separate definition, view, and session allocators. Every
  `QueryCore` owns its own typed `Map[K, MemoEntry[V]]` and `MemoId` allocator;
  there is no reverse edge or erased global registry.
- A `MemoEntry` owns its `MemoId`, value, successful dependency trace,
  `verified_at`, and `changed_at`. Reverification returns only
  `ProvenUnchanged(changed_at)` or `RecomputeRequired`; changed, closed,
  unavailable, or failed old dependencies all require current recomputation.
  Old structural errors never decide a parent result. Only a `ctx.read`
  executed by the current recompute may produce the returned `ReadError`.
- Query verification uses the prior `verified_at`. Source dependencies inspect
  current/closed state. Query dependencies verify/recompute upstream directly
  without recording into their parent. `EvalCtx::revision()` records a
  RevisionClock dependency only inside a query computation, so an unrelated
  Region close stays green while a commit turns it red.
- A same-epoch memo is a cache hit. Otherwise all old dependencies are checked;
  unchanged traces update only `verified_at`. Recompute runs with a temporary
  frame. Success atomically replaces value/trace/stamps and stamps
  `changed_at` at the current epoch without a cutoff. Failure preserves the
  target memo identity, old value, last successful trace, and stamps; a first
  failure installs no memo, and the failed read returns no stale fallback.
  Successful verification/recompute and newly installed memos upstream of the
  failed target remain valid operational updates.
- Close clears Source payloads, Query compute closures, and typed memo tables
  before sealing the Region and advancing ChangeEpoch once. It cuts only the
  closed QueryCore's owning references. A surviving View retains a tombstone
  QueryCore and its captured key; a downstream trace may retain the same until
  verification, replacement, or its own close. Neither path keeps the closed
  QueryCore's compute, memo values, or owned traces alive.
- Transactions follow #461, including phase/metadata checks and passing the
  target ChangeEpoch to validated apply closures. Application failures remain
  values such as `Result[V, DomainError]`; `ReadError` is structural and
  transparent to the caller.
- **Admissibility precondition, not a generic API guarantee:** committed Source
  values and cached Query results must behave as persistent snapshots.
  Everything reachable through any alias, including values returned to a
  caller, must remain observationally immutable for the complete interval in
  which the Store or memo can retain or reuse it. MoonBit's unconstrained
  generic `T`/`V` cannot enforce or defensively copy this. The executable
  includes an excluded counterexample showing parity failure after alias
  mutation; callers needing mutable objects must publish an immutable snapshot
  or a tracked `(reference, semantic_version)` value.

## Workloads

The executable applies matching operation-and-read scripts to separate fresh
and incremental graphs and compares normalized results and public Revisions at
every scripted read. It covers same-snapshot reuse, unrelated green work,
dependent red work, diamond sharing, dynamic trace replacement, failed
recompute/current error/no stale fallback/recovery, initial failure without a
memo, direct closed-root reads, a closed old dependency that can branch away,
lifecycle-only close,
RevisionClock behavior, equal-key memo sharing, domain `Result`, and rejected,
rollback, empty, equal-write, and duplicate-close cases. Runtime identities and
operational counters are intentionally not parity values.

## Native RC evidence

`native_rc` uses external-object markers as ownership proxies. It distinguishes
cutting an owning reference from finalizing an object held elsewhere. It checks
close-time Source/compute/memo release, staged rollback, committed and memo-value
replacement, old dynamic trace replacement, failed temporary-trace release,
a finite same-Query recursive trace SCC, surviving-View key retention, and
downstream tombstone/key retention until trace replacement. The markers are
compiled ownership-path evidence, not claims that every MoonBit object has a
directly observable destructor.

## Negative probes and harness

The negative package keeps capability constructors and recipe invocation
attempts disabled and compiles each probe only to assert the expected compiler
boundary. `run.sh` runs native and wasm parity, native RC, negative probes,
workspace/documentation boundary checks, and a byte-for-byte guard that the
#461 tree is unchanged from commit `4e2e265`.

Run from the repository root:

```bash
bash examples/spikes/incr_next_incremental_parity/run.sh
```

## Non-goals

No production `incr/` changes, documentation migration, `@incr` evaluation,
reverse-edge invalidation, global erased registry, cutoff/backdating, semantic
cycle detection, parallelism, eviction, persistence, or replacement-kernel authorization is
included. No commit, push, issue comment, or publication is part of this spike.
