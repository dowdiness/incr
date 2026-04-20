# ADR: Accumulator API — Side-Channel Collector with Incremental Invalidation

**Date:** 2026-04-20
**Status:** Accepted (2026-04-20)
**Implementation plan:** [docs/superpowers/specs/2026-04-19-accumulator-api-design.md](../superpowers/specs/2026-04-19-accumulator-api-design.md)
**Driver adoption:** [loom/examples/lambda PR #94](https://github.com/dowdiness/loom/pull/94)
**Shipped in:** [PR #42](https://github.com/dowdiness/incr/pull/42) (API) + [`1715981`](https://github.com/dowdiness/incr/commit/1715981) (abort-preservation fix)

## Context

The lambda type-checker driver (in `loom/examples/lambda`) carried a
`diagnostics : Array[TypeDiagnostic]` field on `TypeResult`, merged
manually through every node via a `merge_diagnostics` helper. Each
level of `infer` / `check` rebuilt a fresh `Array` by concatenating
child diagnostics, and the pipeline's `collect_results` reassembled
them at the module boundary.

Two costs accumulated:

1. **Allocation churn.** O(depth) `Array` copies per inference call;
   most arrays are empty because most subterms are well-typed.
2. **Invariant drift risk.** The "stamp `def_name` only at module
   boundary" rule relied on every intermediate producer returning the
   diagnostics verbatim. A future refactor could plausibly drop or
   rewrite diagnostics mid-merge and silently corrupt the per-def
   tagging.

Independently, other drivers were hitting the same shape:
cross-package collection of log-like data where every producing memo
has its own small set. Re-inventing a manual merger in each driver
would duplicate the same fragility.

We want a reusable primitive that lets a memo's compute push values
into a side channel, and lets other memos (or drivers outside the
graph) read those values back with **correct incremental
invalidation** — so when a producing memo recomputes and produces a
*different* set of pushes, downstream consumers are notified even
though the memo's ordinary return value might be equal.

## Decision

Add an `Accumulator[T]` primitive owned by a `Scope` (or directly by
the `Runtime`). Producers call `acc.push(v)` inside their memo's
compute; consumers read via one of three methods on `Memo[_]`:

| Method | Tracks? | On failure |
|---|---|---|
| `Memo::accumulated(acc)` | records synthetic dep + forces verify | `raise Failure` |
| `Memo::accumulated_peek(acc)` | untracked, permissive on disposal | returns `[]` |
| `Memo::accumulated_result(acc)` | tracks, forces verify | `Result[_, CycleError] raise Failure` |

Incremental invalidation uses a **per-memo `push_revised_at` counter**
held in the accumulator's handle-local state. When a memo recomputes
and its push-set differs from the prior run, `push_revised_at[M]`
bumps to `current_revision`. Downstream memos record
`(slot_id, producer_id) → push_revised_at` during a tracked
`accumulated` read; during verify, any mismatch between the stored
value and the current counter invalidates the consumer.

Scope: **local-only (Path 1)**. `memo.accumulated(acc)` returns only
values pushed during that memo's own compute. Transitive aggregation
across a sub-graph is the driver's job.

## Alternatives considered

### Alternative A — Transitive Salsa-style accumulation (rejected)

Semantics: `memo.accumulated(acc)` walks the dep graph and returns
everything pushed by this memo *and all its tracked transitive
dependencies*.

Rejected after Codex round 2 traced the lambda pipeline concretely:

```
env_memo[0] → type_memo[0] → env_memo[1] → type_memo[1] → ...
```

`type_memo[i]` transitively depends on `type_memo[i-1]` through
`env_memo[i]` (see `loom/examples/lambda/src/typecheck/typecheck.mbt`
`rebuild_chain`). A transitive `accumulated()` on `type_memo[i]`
would collect diagnostics from every earlier def — not just this
def's. That contradicts per-def semantics the driver already needs
for incremental error reporting.

Manual union at module level (the current `collect_results` shape)
is the right boundary, and it's cheap because it's O(N) reads, not
O(N) re-typechecks. The local-only core fits without distortion.

If a future driver genuinely wants transitive aggregation, we add
`accumulated_transitive(acc)` as a separate method; the local-only
core stays unchanged.

### Alternative B — Keep return-type threading, just standardize the helper (rejected)

Refactor `merge_diagnostics` into a reusable utility, leave the
`TypeResult.diagnostics` field in place.

Rejected: this keeps the allocation churn and doesn't improve
incrementality. Every call still builds and merges `Array`s even
when nothing errored. And the "stamp def_name at boundary" rule
stays fragile.

### Alternative C — Effect-handler style (out of scope)

Bind the accumulator through an ambient effect context and allow
`push` anywhere in the call chain without explicit plumbing.

Rejected for this iteration: MoonBit's effect system is
`raise`-shaped, not a general handler, and building ambient
accumulators on top of it adds complexity without clear benefit over
explicit `Accumulator` handles. Revisit if MoonBit's effect system
gains broader handler support.

## Error model

### Decision: `raise Failure` (B1), not `Result` (B2)

`Accumulator::push` raises `Failure` for three defect classes:

- called outside a tracked compute context
- called from a non-Memo top frame (see §Top-frame restriction)
- called on a disposed accumulator

`Memo::accumulated` raises `Failure` on disposal / cycle / the
target memo's own raise.

Rejected B2 ("return `Result[Unit, Error]`") because:

1. Memo compute closures are already `() -> T raise Failure`, so
   raises propagate without ceremony. A `Result`-returning `push`
   would force every error site in the driver to `match` or `?`.
2. MoonBit's polymorphic `raise?` lets callers still downgrade to
   `Result[_, Error]` at a boundary with `try?`, preserving B2
   ergonomics for any caller that wants them.
3. `raise Failure` is consistent with the rest of the incr API where
   defect classes (disposed handles, cross-runtime reuse) raise
   rather than return.

`CycleError` in `accumulated_result` is the exception: a recoverable
signal that a consumer might legitimately branch on, so it's an
`Err`-side value rather than a raise.

## Top-frame restriction: Memo / HybridMemo only

`Accumulator::push` is a defect (`fail(...)`) if the top active query
is not a `PullMemo` or `HybridMemo`. Signals, Effects, and Reactive
cells cannot push.

Rationale:

- Signals have no compute — nothing to invalidate on.
- Effects run outside the graph; a push would have no observer
  tracking it.
- Reactive cells have no `push_revised_at` bookkeeping, and adding
  it would couple the push engine to the accumulator mechanism.

Drivers that want "effect-like" accumulator writes wrap them in a
Memo whose return value is ignored (or `Unit`).

## Scope-based lifecycle

Accumulators allocated via `Scope::accumulator(...)` are disposed
when the scope is disposed via `dispose_hooks`. The chain_scope
pattern used by the lambda pipeline exploits this: a structural
rebuild disposes the old chain scope, which disposes the old
accumulator, and a fresh accumulator gets allocated bound to the
new chain — no manual tracking needed.

Rejected alternative: a Runtime-owned global accumulator map keyed
by (user-provided) name. Would force drivers to reason about
accumulator identity across revisions and invent their own scoping
rules. Scope ownership reuses lifecycle machinery we already trust.

## Synthetic dep recording

Per-memo `push_revised_at : HashMap[CellId, Revision]` lives inside
the `Accumulator` handle itself (not the Runtime).

Rejected alternatives:

- **Global epoch counter on the Accumulator**: too coarse. Any
  push-set change anywhere invalidates every consumer, including
  consumers reading from a different producer.
- **Per-`(producer, consumer)` counter held on the Runtime**:
  requires runtime-side structural support. Handle-local
  bookkeeping avoids new Runtime fields.

## Consequences

### Accepted

- **Public API additions.** New types (`Accumulator`, `AccumulatorId`),
  new `Memo` methods (`accumulated`, `accumulated_peek`,
  `accumulated_result`), new `Scope::accumulator` factory. The
  public-surface growth is worth it — drivers beyond lambda are
  expected to adopt the pattern.
- **`Memo::accumulated` raises `Failure`.** Consumers calling from
  inside a memo compute propagate transparently; consumers reading
  from outside use `try?` at the boundary. This was the deciding
  factor for error-model B1.
- **Per-memo HashMap overhead.** Each accumulator carries
  `per_memo : HashMap[CellId, Array[T]]` and
  `push_revised_at : HashMap[CellId, Revision]`. Sized by the number
  of producer memos × accumulators, which is small in practice.
- **Top-frame restriction surfaces as a `fail` at push time, not
  a compile error.** Drivers that misuse it (e.g., push from an
  Effect) learn at first call. Trade-off for not complicating the
  static type system.

### Plan deviations encountered during implementation

Four of these surfaced during execution and are captured here so
future readers don't re-derive them from the spec:

1. **`verified_at == initial()` as "never computed" discriminator is
   broken on fresh runtimes** — `current_revision` also starts at
   `initial()`. Added an explicit `has_been_computed : Bool` flag on
   `MemoData` to disambiguate.
2. **`Memo::accumulated` signature narrowed from bare `raise`
   (Error) to `raise Failure`.** MoonBit rejects `raise Error`
   closures called from `raise Failure` contexts; since memo compute
   is always `raise Failure`, `accumulated` had to match. `CycleError`
   is wrapped via `fail(...)` inside `accumulated`, or surfaced
   through `accumulated_result` for explicit handling.
3. **Synthetic dep check must first force-verify the target memo.**
   The spec read `push_revised_at_for(target_id)` directly; if the
   target had its own invalidated ordinary deps, that check saw a
   stale counter. Fix: recursive `pull_verify(target_id)` before
   reading the counter.
4. **`check_cross_runtime` missing on the `acc` argument in all three
   read methods.** Code review caught this before merge — reading a
   slot from a different runtime silently returned wrong data.
   Fixed in the pre-merge review pass that landed with
   [PR #42](https://github.com/dowdiness/incr/pull/42).

### Deferred / open follow-ups

- **Transitive aggregation** — keep as `accumulated_transitive` if
  a future driver needs it. Not required by lambda.
- **N→M delta tracking** (producer pushes discrete inserts/deletes;
  consumers see an ordered stream, not a flat set) — out of scope
  for accumulators. Tracked under the ReactiveMap / DeltaObserver
  design work in [docs/reactive-collections.md](../reactive-collections.md).
- **API naming cleanup** — `accumulated_peek` / `accumulated_result`
  share the `accumulated_` prefix with `accumulated`. If we later
  converge on a different convention (e.g. `Memo::peek_accumulator`,
  `Memo::read_accumulator_result`), that's a purely cosmetic rename.
  Queued under the naming-cleanup deferred tasks.

## Related

- [docs/superpowers/specs/2026-04-19-accumulator-api-design.md](../superpowers/specs/2026-04-19-accumulator-api-design.md)
  — implementation spec (21 tasks, TDD-driven). Archive after
  retaining for historical context.
- [docs/api-reference.md](../api-reference.md) §Accumulator — user-facing
  API documentation.
- [docs/cookbook.md](../cookbook.md) — (future) accumulator usage recipes.
