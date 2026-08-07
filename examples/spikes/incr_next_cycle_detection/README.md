# Issue #463: invocation-level semantic cycle detection

**Status:** Evidence-only standalone spike. It is not production `incr/` code.

**Reader:** Maintainers testing whether cycle detection can be added as one
independent variable after the #461 FreshEval and #462 verifying-trace evidence.

**Decision:** Detect semantic cycles by typed `(QueryCore, K::Eq)` invocation
identity and return a copied QueryId witness while preserving #462 failure and
ownership rules.

**Keep until:** Cycle semantics are either adopted by a later kernel or replaced
by a stronger model.

**Disposition:** Keep on its evidence branch. Do not merge into `main` or treat
this as replacement-kernel authorization.

## Question

Can typed invocation-level active tracking add deterministic cycle detection to
fresh and incremental evaluators without reverse subscriber edges or a global
erased key registry, while retaining all #462 acyclic parity, target-local
failure atomicity, and ownership boundaries?

Run from the repository root:

```bash
bash examples/spikes/incr_next_cycle_detection/run.sh
```

## Independent evidence layers

The harness guards these prior trees byte-for-byte:

```text
#461 incr_next_fresh_evaluator       unchanged
#462 incr_next_incremental_parity    unchanged
#463 incr_next_cycle_detection
├─ fresh_provider
├─ incremental_provider
├─ consumer
├─ native_rc
└─ negative
```

The cycle-aware providers fork only the private package files that require
cycle-specific state. Unchanged identity, Source, Transaction, and negative
probe files are symlinks to the guarded #461/#462 sources. MoonBit package
privacy prevents importing and extending QueryCore/EvalSession directly, so the
modified core/query/view/region/error files and the adapted consumer remain an
explicit evidence fork. The consumer reruns the complete #462 acyclic workload
before its cycle scenarios.

## Invocation identity

A cycle is re-entry into the same QueryCore with an equal active key in the same
root session. QueryId, ViewHandleId, MemoId, and key hash alone are insufficient.
Hash selects a typed map bucket; `K::Eq` makes the final decision.

```text
q(3) → q(2) → q(1) → q(0)   allowed
q(0) → q(1) → q(0)           cycle
A(x) → B(y) → A(x)           cycle
A(x) → B(y) → A(z)           allowed when x != z
```

Each QueryCore owns:

```text
active : Map[K, ActiveInvocation]
```

Each EvalSession owns only a key-free stack:

```text
active_stack : Array[ActiveFrame]
ActiveFrame { ActiveInvocationId, QueryId }
```

ActiveInvocationId is session-local operational identity and is not exposed as
a Query input. No heterogeneous key table exists outside the typed QueryCore.

## Ordering and cleanup

Both providers validate EvalCtx, Store provenance, and Region generation before
active lookup. Incremental reads then use this order:

```text
active invocation check
→ same-ChangeEpoch cache hit
→ enter active slow path
→ old-trace verification
→ green reuse or current recompute
→ remove typed active key and pop session frame
```

Fresh Query reads always enter the active scope. Incremental cache hits need no
new active entry, but an already-active invocation is rejected before cache
lookup so an old memo cannot hide a cycle.

Every structured `Result` exit (success, Cycle, ClosedRegion, CrossStore, or
another ReadError) removes the typed key and pops the matching frame. Query debug
reports active-map size and Store debug snapshots the stack depth at the end of
the last root. Uncatchable abort and arbitrary FFI failure remain outside the
admissible contract.

## Cycle witness

```moonbit
pub(all) struct CycleWitness {
  path : Array[QueryId]
}
```

The path repeats its starting Query:

```text
direct:       [A,A]
mutual:       [A,B,A]
same Query:   [Q,Q,Q]
```

Detection remains key-sensitive, but the copied witness contains no key,
ActiveFrame, QueryCore, memo value, or compute closure. Fresh and incremental
QueryIds are normalized to scenario-local names before comparison.

## Verification versus current computation

A Cycle encountered while verifying an old dependency means only that the old
cached value lacks reuse evidence:

```text
old verification Cycle → RecomputeRequired
```

The current branch is then recomputed. Only a Cycle reached by the current
recompute becomes the root ReadError. Cycle is error-transparent through parent
Queries and is never memoized.

## Failure and recovery

Cycle follows #462 target-local failure atomicity:

- existing value, last-successful trace, MemoId, `verified_at`, and `changed_at`
  remain unchanged;
- the read returns Cycle, never a stale fallback;
- an initial Cycle installs no memo;
- upstream successful operational updates remain;
- the next read retries instead of reading a cached error;
- removing the cycle through a Transaction permits recovery;
- an existing target reuses its MemoId, while an initially cyclic target gets
  its first MemoId only after success.

Cycle reads advance neither Revision nor ChangeEpoch.

The deterministic Query, stable-key, snapshot-value, and structural-error
transparency admissibility contracts from #462 remain in force.

## Workloads

After all #462 acyclic scenarios pass, the executable covers:

- direct self-cycle twice, proving cleanup and non-cached errors;
- finite same-Query recursion with four incremental memos;
- same-Query key cycle;
- mutual cycle;
- cross-Query return to the same QueryCore with a different key, which succeeds;
- successful memo followed by cycle introduction;
- repeated Cycle with unchanged target memo state;
- cycle removal and recovery with the same MemoId;
- first successful memo allocation after an initially cyclic invocation;
- old-trace-only Cycle collapsing to recomputation and an acyclic current branch;
- a current-cycle transition producing `[A,B,A]` in both providers, proving B
  reached current recompute and preserving both A and B memo state;
- sequential duplicate reads that are not a cycle;
- a dead cycle branch that is not evaluated;
- CrossStore and ClosedRegion precedence before active detection.

Cycle, failure, recursion, and recovery scenarios assert zero relevant
active-map entries; representative structured exits also assert a zero finished
session-stack depth. The native probes separately cover key release on success,
Cycle, and another ReadError.

## Native RC evidence

External-object finalizers are compiled ownership-path proxies. They establish:

- temporary active keys release after success, Cycle, and another ReadError;
- a nested equal cycle key releases while a deliberately surviving View keeps
  its own key until the View drops;
- a Cycle failure drops the parent's temporary trace while a successfully
  installed upstream memo remains;
- an old memo value survives Cycle failure and releases on Region close;
- retaining CycleWitness after close does not retain memo value or compute
  capture.

The unchanged #462 evidence remains authoritative for forward-trace SCC,
downstream tombstone, memo replacement, and Region-close ownership behavior.

## Public boundary

Generated interfaces expose CycleWitness and active-count debug snapshots only.
Typed active maps, keys, ActiveInvocation, ActiveFrame, recipes, dependencies,
and MemoEntry remain private. EvalCtx has no constructor or `eval_id`; View has
no call/get/read surface; Source has no direct set method.

## Non-goals

No iterative verification stack, stack-overflow protection, recovery value,
Cycle caching, generic key formatting, cutoff/backdating, eviction, dependency
deduplication, Mount, Program, Canopy integration, parallel evaluation,
benchmark, production authorization, or ADR is included.
