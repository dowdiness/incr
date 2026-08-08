# Incr Next typed cutoff/backdating evidence

- **Reader:** Incr maintainers evaluating the next kernel's semantic propagation boundary.
- **Decision:** Determine whether the three typed policies justify a constrained cutoff design; do not adopt a production API.
- **Keep until:** The Incr Next cutoff direction is adopted, rejected, or replaced by stronger evidence.
- **Disposition:** Retain as checked spike evidence until that decision, then preserve the durable conclusion in an ADR or delete the spike.

This standalone spike asks one question:

> Can a Query-owned typed cutoff policy (AlwaysChanged, Eq, or type-owned
> semantic equality) run only after successful recomputation, replace an
> equivalent result's memo value and forward trace while preserving
> `changed_at`, retain exact Fresh/Incremental root outcomes for the checked
> admissible scripts, and skip downstream recomputation without reverse edges
> or a global erased registry?

Run from the repository root:

```bash
bash examples/spikes/incr_next_cutoff_backdating/run.sh
```

The provisional answer is **Pass with constraints** for the executable workloads
below. This is not a proof for every admissible graph and does not authorize a
production kernel or API.

## Evidence isolation

The spike guards and runs the preceding evidence without changing it:

```text
#461 incr_next_fresh_evaluator       unchanged
#462 incr_next_incremental_parity    unchanged
#463 incr_next_cycle_detection       unchanged
     incr_next_cutoff_backdating
     ├─ fresh_provider
     ├─ incremental_provider
     ├─ consumer
     ├─ native_rc
     └─ negative
```

Unchanged provider implementation files and cycle/negative workloads are
symlinks to #463. Query/error files are an explicit fork because QueryCore and
EvalSession are package-private. The adapted acyclic consumer reruns #463 before
cutoff-specific scenarios.

## Semantic contract

Cutoff is one-sided evidence:

```text
cutoff(old, next) = Unchanged
  implies old is observationally equivalent to next
  for every admissible downstream computation
```

A false negative causes extra recomputation. A false positive may let a
consumer observe a stale result and breaks Fresh/Incremental parity. The kernel
does not prove congruence; it relies on the Query result type's caller contract.

The admissible contract from #461 through #463 still applies: Query computation,
keys, and type-owned equality are deterministic in tracked semantic inputs;
committed and memoized values are observationally immutable throughout their
retention interval; nested structural errors remain error-transparent. Each
result type also defines an **admissible downstream observer discipline**:
fields ignored by its cutoff relation may be inspected by a direct root reader
of the newly stored value, but must not affect a downstream Query whose reuse
relies on that relation. The kernel cannot enforce this discipline. Clocks,
randomness, arbitrary mutable globals, FFI effects, unstable keys, mutable
aliases, forbidden downstream observers, and caught-to-Ok structural errors
remain caller responsibilities.

## Typed policy surface

Both providers expose the same three constructors:

```moonbit
region.query_always_changed(compute)
region.query_eq(compute)          // V : Eq
region.query_type_owned(compute)  // V : CutoffEq
```

The spike retains `Region::query` only as the unchanged #463 AlwaysChanged
baseline alias. New cutoff workloads use one of the explicit constructors.
Policy is selected once when the Query is constructed and cannot be changed.
There is no constructor accepting an arbitrary per-Query predicate. `CutoffEq`
is itself a trusted, caller-implemented type-owned extension point and can be
unsound; its implementation is part of the admissibility contract.

The type-owned relation is deliberately smaller than current Incr's
`BackdateEq : HasChangedAt`:

```moonbit
pub(open) trait CutoffEq {
  fn cutoff_equal(Self, Self) -> Bool
}
```

`CutoffEq` requires neither structural `Eq` nor a one-dimensional changed-at
projection. A non-Eq PatternLike workload compares independent value and
fingerprint revisions while retaining a render closure.

QueryCore privately owns:

```text
CutoffPolicy[V]
├─ AlwaysChanged
└─ Compare((V, V) -> Bool)
```

This representation and the memo representation do not appear in generated
interfaces. Fresh retains the policy for constructor and ownership parity but
never calls it during evaluation.

## Recompute commit point

Incremental evaluation performs cutoff only in the success arm of current
recomputation, while the invocation is active and after the temporary forward
trace is complete:

```text
compute current value and temporary trace

failure:
  increment failed-recompute evidence
  return current ReadError
  do not call cutoff
  do not alter an old memo

initial success:
  allocate MemoId
  install value and trace
  verified_at = current ChangeEpoch
  changed_at = current ChangeEpoch
  do not call cutoff

success with an old memo:
  call the fixed policy once
  install the new value
  install the new trace
  verified_at = current ChangeEpoch
  preserve MemoId

  Equivalent:
    changed_at = old changed_at

  Changed:
    changed_at = current ChangeEpoch
```

Same-epoch cache hits and green verification do not invoke cutoff. Validation,
active-cycle checking, and old-trace verification retain #463 ordering. Cycle or
another ReadError reached by current computation never invokes cutoff and never
returns a stale fallback.

The three independent freshness dimensions are therefore:

```text
value freshness      newest successful value is retained
trace freshness      newest successful dependency trace is retained
semantic changed_at  last downstream-observable semantic change
```

Backdating only affects the third dimension.

## Executable workloads

### AlwaysChanged baseline

The complete #463 acyclic and cyclic workload runs first. Its compatibility
constructor maps to AlwaysChanged. A dedicated explicit-AlwaysChanged scenario
also proves that an equal output advances `changed_at` and recomputes its parent.

### Eq backdating and invocation count

An integer source changes `2 -> 4 -> 5`; a parity Query returns `value % 2`.
Evidence establishes:

- initial success calls cutoff zero times;
- same-epoch cache reuse calls cutoff zero times;
- unrelated ChangeEpoch green-verification calls cutoff zero times;
- `2 -> 4` recomputes parity, replaces the memo, advances `verified_at`,
  preserves `changed_at` and MemoId, and skips its parent;
- `4 -> 5` recomputes parity, advances `changed_at`, and recomputes its parent;
- exact Fresh and Incremental root outcomes remain `0,0,0,0,1`.

### Dynamic trace replacement

A selected parity Query first reads `{mode,left}`, then `{mode,right}`. Switching
from even left to even right preserves `changed_at` but publishes the new trace.
A later left-only update leaves the Query green and does not call cutoff. A
right update to an odd value makes the Query and its parent red.

This directly checks that backdating never suppresses trace replacement.

### Newest value and consecutive equivalent updates

A SemanticDoc contains semantic content and an operational diagnostic counter.
Its CutoffEq relation compares only semantic content. Its declared observer
discipline permits a direct root to inspect that counter but forbids a
downstream Query from deriving semantic output from it. Under that restriction,
three equivalent updates replace the memo value while preserving the initial
`changed_at`; a direct Query read observes counter 3 and the semantic-only
parent does not recompute. A subsequent semantic change advances `changed_at`
and reaches the parent.

No old/new pair is retained by the memo.

### Type-owned non-Eq result

PatternLike contains value revision, fingerprint revision, generation, and a
render closure, so ordinary Eq is intentionally unavailable. Its CutoffEq
compares the two semantic revisions without HasChangedAt:

```text
same value revision + same fingerprint revision     Equivalent
same value revision + changed fingerprint revision  Changed
```

The declared observer discipline likewise treats generation as operational
metadata. The equivalent update exposes the newest generation to a direct root
read while the semantic parent is skipped. The fingerprint change recomputes
the parent. A downstream Query reading generation would be inadmissible and
would reproduce the expected-divergence counterexample below.

### Cycle and failure

The cutoff-specific error workload establishes:

- an initial self-Cycle installs no memo and calls cutoff zero times;
- a Cycle introduced over a successful memo calls cutoff zero times;
- Cycle preserves value, trace, MemoId, `verified_at`, and `changed_at`;
- no stale value is returned;
- removing the Cycle and producing an equivalent result installs the new value
  and trace, preserves changed_at, and reuses MemoId;
- initial non-Cycle ReadError installs no memo and calls cutoff zero times;
- recompute ReadError over a memo calls cutoff zero times and preserves the old
  memo byte-for-byte at the public debug boundary.

### Expected unsoundness

Two excluded counterexamples record expected Fresh/Incremental divergence and
are not counted as admissible parity successes:

1. custom Eq ignores `generation`, but a forbidden downstream observer returns
   generation, violating the type's relation contract;
2. type-owned local nearness treats adjacent integers as equivalent through
   `0 -> 1 -> 2`, while the downstream returns the integer.

The first yields Fresh 1 and Incremental 0. The second yields Fresh `0,1,2` and
Incremental `0,0,0`. These demonstrate that `V : Eq` and a plausible predicate
are not automatic soundness proofs.

## Ownership evidence

The native RC executable preserves #463's active-key, temporary-trace, old-memo,
and witness checks, then adds:

- equivalent recompute releases the old memo value;
- equivalent recompute publishes the right-child trace; after closing the old
  child clears its memo key, finalization proves no stale old trace retains the
  copied key;
- only the newest value and trace remain owned;
- changed recompute follows the same single-current-value ownership rule;
- Region close releases the newest memo and trace-owned Source payloads;
- all 13 marker categories finish with zero live objects and one finalization.

A native white-box provider test creates a private cutoff closure that captures a
separate external marker. Region close clears the cutoff slot, and a surviving
Query and View retain neither that marker nor the policy closure. This private
evidence adds no arbitrary predicate to the public API.

## Compiler and interface boundaries

Negative probes retain the opaque View/EvalCtx/Transaction and Source-write
boundaries from #463. New probes prove that no `query_by(predicate)` constructor
exists and external code cannot name private CutoffPolicy. They do not claim
that a caller's CutoffEq implementation is intrinsically safe.

Generated interfaces expose CutoffEq and the three typed constructors, but not
CutoffPolicy, BackdateEq, HasChangedAt, a trusted predicate, Dependency,
MemoEntry, active keys, or tracking frames.

## Reuse check

Reused project evidence and APIs:

- #461 opaque View/EvalCtx/Transaction boundary;
- #462 typed per-Query memo, last-successful forward trace, ChangeEpoch, and
  target-local failure atomicity;
- #463 typed active invocation map, copied QueryId witness, and cleanup order;
- production `Runtime::memo_force_recompute`, `Derived::with_backdate`, and
  pull verification tests as read-only semantic oracles.

MoonBit core APIs checked:

- `Map[K,V]`, `Hash`, and `Eq` remain the typed key/memo/active machinery;
- `Array`, `ArrayView`, and `fold` remain the forward-trace and witness tools;
- `Option`, `Result`, and `Ref` retain capability and atomic-state boundaries;
- String/StringView and StringBuilder are used only for normalized evidence;
- Bytes/BytesView, Buffer, and math APIs do not fit value comparison or trace
  ownership and were not used.

`Set` was rejected because memo and active entries need typed metadata, not only
membership. Production BackdateEq was not reused because its HasChangedAt
supertrait is exactly the coupling this spike is testing without.

## Constraints and non-goals

The spike does not select a production default, prove cutoff laws, expose an
arbitrary predicate, migrate BackdateEq, add a HasChangedAt adapter, deduplicate
dependencies, or implement eviction/rematerialization, iterative verification,
Mount, Program/Port/Manifest, Canopy integration, parallel evaluation, or
benchmarks.

Eviction remains separate: this spike asks when a retained memo may preserve
`changed_at`; eviction must ask what can be reconstructed after the memo and its
stamps no longer exist.

No ADR is needed because the spike records research evidence without adopting
Incr Next as the product direction.
