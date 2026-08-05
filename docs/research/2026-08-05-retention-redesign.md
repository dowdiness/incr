# Retention redesign — current design brief

**Date:** 2026-08-05

**Reader:** Maintainers deciding whether to commission a retention and
public-interface redesign for `incr`; implementers of any later prototype.

**Decision:** Preserve as the sole current design brief for the retention
redesign track. Selected decisions bind the redesign track only; they do not
commission a kernel replacement and do not change the current public API.

**Keep until:** The redesign track is commissioned (distill durable decisions
into ADRs and retire this note) or rejected (record the rejection rationale
in an ADR and delete this note).

**Disposition:** Gated research consolidation. No implementation is
authorized. This document supersedes prior drafts, amendments, and
correspondence tables that accompanied the original proposal and handoff.

---

## Status at a glance

| Category | Items |
|----------|-------|
| **Selected** | Callable `View[T]`, `Store::derived[T : Eq]`, View-owned passive state, Store-owned active records, rooted diagnostics, breakers (Stop / close), wake-up theorem, batch staged-write rollback |
| **Provisional** | `Write[T]` shape, Effect cleanup contract, `GraphSnapshot` fields, `suberror` syntax, ownership derivation (pending RC proof) |
| **Open** | F7 keyed retirement, multi-Store composition, event observability, BackdateEq migration surface, advanced mapping parity, close interleavings |
| **Evidence required** | V12.3 parity oracle, V12.4 ownership proof, V12.6 Effect contract, V12.10 error hierarchy, V12.11 diagnostics, F7 resolution, release benchmarks |

---

## Library promise

The current `incr` engine is powerful: it offers `Input` / `Derived` /
`ReachableDerived` / `DerivedMap` / `Accumulator` / `EagerDerived` /
`AcceptedDerived`, custom backdating (`BackdateEq`, `Derived::with_backdate`),
durability-based verification shortcuts, push-mode `Effect`, Datalog
`Relation` / `MapRelation`, evaluation hooks, and `Scope`-owned lifecycle.
Callers who need these facades pay a corresponding cognitive burden: the
`get` / `read` / `watch` split, `Scope` and `Runtime` GC roots, durability
tuning, and the knowledge that `Scope::collect()` acts on the whole runtime.

The target is a **deeper** library, not merely a smaller one. The callable
`View[T]` and `Store::derived` reduce the common path to a getter and a
creation call. But every current advanced facade — durability, custom
backdating, DerivedMap, Accumulator, Datalog, AcceptedDerived, EagerDerived,
event hooks, phase enforcement, batch rollback — must be preserved or mapped
in the target. The redesign is not an improvement unless these capabilities
survive.

---

## Selected public interface

The selected public read capability is a callable closure:

```moonbit
pub type View[T] = () -> T raise ReadError
```

Creation uses `Store::derived` with a zero-argument compute and an optional
label:

```moonbit
pub fn[T : Eq] Store::derived(
  Self,
  compute : () -> T raise ReadError,
  label? : String,
) -> View[T]
```

### Canonical selected-surface example

This example uses only the selected callable View and `derived` shapes;
`input`, write, and Effect creation remain provisional.

```moonbit
fn preview_view(
  store : Store,
  source : View[String],
  mode : View[Mode],
) -> View[Preview] {
  let document = store.derived(() => parse_markdown(source()))
  store.derived(() =>
    match mode() {
      Raw => render_raw(source())
      Preview => render_markdown(document())
    }
  )
}

let preview = preview_view(store, source, mode)
render(preview())
```

### What is selected vs provisional

The callable `View[T]` and `Store::derived[T : Eq]` are selected. The
following remain provisional and must be compile-probed before adoption:

- **`Write[T]`**: the write capability shape. Must preserve the distinction
  between equality-suppressing `set` (needs `Eq`), unconditional `force_set`,
  and any future atomic `update`. A bare `(T) -> Unit` hides these semantics.
- **Effect cleanup**: the contract for cleanup that runs before re-run or on
  stop is underspecified. `() -> Unit` cannot express cleanup-before-rerun.
- **`GraphSnapshot`**: the diagnostic value shape is not finalized.
- **`suberror` syntax**: the proposed `ReadError` hierarchy with
  `CrossStore(StoreMismatch)` and `Closed(NotMaterializedAtClose)` is
  conceptual. MoonBit `suberror` syntax is not yet compile-probed.

### Rejected: public previous/cached callback

The compute callback is deliberately zero-argument. The kernel may retain
old values internally for equality cutoff and backdating, but the caller
sees no cached-value parameter. Rationale: observation-dependence (lazy
materialization and batch coalescing make cached transitions non-deterministic
from the caller's perspective), an unenforceable cold/warm equivalence law,
mutable-alias risk when `T` contains owning mutable collections, and the
common `_ =>` tax for callers that never reuse an old value.

---

## Semantic contract

### View purity

A View is a synchronous, lazy, pull-only function. It
performs no I/O, no callbacks, no writes, and no runtime-wide GC. Getter
purity is a correctness condition, not etiquette.

### Equality

`Store::derived[T : Eq]` uses `Eq` for equality cutoff: if
recomputation produces an equal value, `changed_at` is not advanced and
downstream propagation is suppressed. No no-backdate or non-Eq public escape
hatch is selected in the initial candidate. Current `BackdateEq` parity
remains a migration obligation if kernel replacement is commissioned.

### One successful recomputation

Each computation has at most one successful recomputation per revision, and
subscriptions run once without glitches.

### Domain Result vs ReadError

Domain failures (parse errors, validation
failures) remain value-level `Result[V, E]`, cached inside the computed
value. `ReadError` covers graph-mechanism failures only. The current
`ReadError` has `Cycle(CycleError)` and `Disposed(CellId)`
(`incr/types/read_error.mbt`). The proposed hierarchy adds:

- `Cycle` — the cell transitively depends on itself. Recoverable; caught at
  UI/FFI/effect quarantine seams.
- `CrossStore(StoreMismatch { active : RuntimeId, view : RuntimeId, cell : CellId? })`
  — detected before dependency/value/revision mutation. Top-level reads
  without another active Store are allowed.
- `Closed(NotMaterializedAtClose)` — a read after close when the View was
  stale or never materialized at the close revision.

MoonBit `suberror` syntax for this taxonomy is a verification obligation,
not finalized source syntax.

### Batch rollback

A failed batch rolls back staged Store input writes only.
External side effects, mutation through aliased values, and `abort()` are not
rolled back. The current `Runtime::batch` already implements this
(`incr/cells/batch.mbt`). The batch closure must use a polymorphic raise
signature (`() -> Unit raise?`) for rollback to be reachable.

### Close semantics

`store.close()` seals the timeline: it disables writes,
freezes the close revision, stops Effects, and clears mount records. A View
fresh and materialized at the close revision returns its frozen cache. A
stale or never-computed View raises `Closed(NotMaterializedAtClose)`. No
post-close computation occurs. This is logical invalidation; immediate memory
release of externally held closures is not promised.

---

## Ownership and lifecycle

```
View closure ──strong──> ViewState (passive)
ViewState    ──strong──> compute closure
ViewState    ──strong──> upstream passive dependencies
ViewState    ──strong──> StoreCore reference
StoreCore    ──X───────> passive ViewState  (no strong edge)
StoreCore    ──strong──> active Effect records
StoreCore    ──strong──> mount records

Passive graph: derived → dependency only (no reverse edges)
Active SCCs:   every nontrivial SCC contains an active resource
               and a designated breaker (Stop or store.close)
```

The critical asymmetry is that StoreCore does not strongly own passive
ViewState. This prevents retention cycles through the Store. The design
intends dropping all View closures to release the passive graph under RC;
V12.4 must prove that compute captures, cached values, and keyed entries do
not introduce another passive cycle.

Passive edges are strictly derived-to-dependency. No reverse subscriber
edges exist on passive nodes in the target. The current kernel gives every
cell a reverse edge `subscribers : HashSet[CellId]`
(`incr/cells/internal/shared/cell_meta.mbt`); removing these from passive
nodes is a kernel change.

Active reference cycles are permitted only when they contain an explicit
breaker. `Stop` breaks the Effect cycle
(`Stop → Store → mount table → Effect → getter → state → StoreCore`).
`store.close()` breaks the whole-Store cycle. Every nontrivial strong SCC
must contain an active resource and a designated breaker; no passive-only
SCC may exist.

Property tests supplement but do not replace the structural proof. V12.4
requires a written field-level strong-edge ownership table.

---

## Evaluation and scheduling

### Pull verification

On read, the dependency closure is verified
recursively. If all dependencies are unchanged (by `changed_at`), the cached
value is returned without recomputation. If a dependency changed, compute
runs, the new dependency set is recorded, and values are compared for
equality cutoff. The current kernel already implements this
(`incr/cells/internal/kernel/verify.mbt`).

### Durability

A read can skip verification when no input at the cell's
durability level has changed since `verified_at`. The current kernel
implements this (`can_skip_verify_by_durability` in `verify.mbt`). The
redesign must preserve durability from day one.

### Dynamic dependencies

Only getters called by ordinary control flow become dependencies, and the
next evaluation swaps the dependency set after a branch change.

### Mounted Effect scheduling

The mount table holds, per Effect, the
transitive set of input leaves reached by the last run — including through
cached views that returned without re-executing. On an input change, wake
via that set and re-run only what pull confirms changed. After each
successful re-run, atomically swap the snapshot; on failure, retain the
prior snapshot.

### Write restrictions

A setter called during passive compute aborts. A
setter inside an Effect body is allowed but deferred until dispatch
completes. This preserves the single-revision snapshot invariant.

---

## Diagnostics

### `store.graph_snapshot()`

Traverses from mounted Effects through cached dependency metadata without
executing user code or producing side effects. Unmounted passive Views are
absent by design, an intentional scope trade-off required by the retention
architecture.

### `store.trace_graph(() => { ...roots... })`

Allows callers to supply
heterogeneous roots for one-shot diagnostic use. The frame is ephemeral and
discarded after the snapshot. This may materialize caller-supplied Views
that would otherwise be invisible.

### Absent nodes

Unmounted, unpassed, unreachable, and arbitrary thunks are
absent from both diagnostic paths by design. Neither operation creates a
persistent all-Views registry. Under RC without weak references, a registry
would itself become a root and reintroduce the retention problem.

### Event observability

Derived-event listeners exposing ordering, timing,
aborts, and backdating are a separate concern from diagnostic graph
traversal and need their own decision.

---

## Advanced capability parity

The target is not an improvement unless every current advanced capability is
preserved or mapped. The table below states the obligation; exact mapping
design is deferred.

| Current capability | Parity obligation |
|---|---|
| Durability (High/Med/Low skip) | Port directly; orthogonal to retention |
| BackdateEq / `Derived::with_backdate` | Preserve custom backdating as part of equality-cutoff surface |
| DerivedMap / F7 keyed families | Map or preserve; F7 resolution is a precondition |
| Accumulator | Named-handle advanced API; not folded into getter layer |
| Datalog / Relation / MapRelation | Named-handle advanced API; not folded into getter layer |
| AcceptedDerived | Map acceptance semantics to target kernel |
| EagerDerived | Map eager evaluation to target kernel |
| Effect | Preserve push scheduling, deferred writes, cleanup, and stop semantics in the active layer |
| Watch / Observer / Scope lifecycle | Replace passive rooting with View ownership while preserving active attachment and hierarchical teardown use cases |
| Expr | Preserve the declarative expression facade or provide a migration |
| InputView | Preserve read-only input projection without restoring read-mode complexity |
| Freshness / RuntimeContext | Preserve extension traits or document replacements |
| Introspection (`CellInfo`, ids, dependencies, roots) | Map to rooted diagnostics without promising a global registry |
| DerivedEvent / event hooks / `on_change` | Preserve or map listener registries |
| Phase enforcement | Preserve evaluation-strategy composition contract |
| Batch rollback | Preserve staged-write rollback on failure |

No exact parity claim is made for any individual facade. The parity matrix
(V12.3) must cover every current facade and hook before kernel replacement
begins.

---

## Open decisions

- **Write shape.** Whether `Write[T]` is an opaque struct, a capability
  record, or an opaque input token. The setter must declare its write
  semantic (equality-suppressing vs force).
- **Effect cleanup and deferred writes.** Cleanup before re-run, cleanup on
  stop, deferred-write queue ordering, self-trigger limits, nested batches,
  and cancellation during dispatch.
- **F7 keyed retirement.** When a key falls out of the membership set but
  a downstream getter survives, neither forcible retirement nor silent
  retention is acceptable. No keyed policy is selected. Resolving the
  retirement protocol alone does not commission keyed work: reopening also
  requires a named consumer that creates per-key dynamic reactive subgraphs
  under a live push path and a measured success signal for that consumer.
- **Multi-Store composition.** Whether product modules should prohibit
  composition, bridge values, coordinate batches, or share one Store. The
  typed `CrossStore` mismatch failure does not decide this.
- **Event observability.** Derived-event listeners for ordering, timing,
  aborts, and backdating need a separate decision.
- **BackdateEq migration surface:** choose whether `BackdateEq` maps to a
  target trait or a creation-time parameter.
- **Advanced mappings.** How DerivedMap, Accumulator, Datalog,
  AcceptedDerived, and EagerDerived map to the target kernel.
- **Close interleavings.** Interaction between `store.close()` and
  in-flight Effect dispatch, pending batch writes, or concurrent reads.

---

## Evidence gates

| Gate | Scope | Status |
|------|-------|--------|
| V12.3 | Semantic parity matrix: every current facade and hook (`AcceptedDerived`, `Expr`, `InputView`, `Freshness`, `RuntimeContext`, Accumulator, DerivedMap, push cells, Datalog, custom backdating, listener registries, introspection, event ordering) | Not started |
| V12.4 | Field-level strong-edge ownership table + RC argument. Compute captures, cached values, dependency arrays, StoreCore, mount records, Stop, close, deferred-write queues, keyed entries. Property tests supplement, not replace | Not started |
| V12.6 | Effect contract: initial-run failure, cleanup before re-run and on stop, deferred-write ordering, nested batches, cancellation, stop/close idempotence | Not started |
| V12.10 | `ReadError` hierarchy compile probe: `suberror` syntax, exhaustive catches, `CrossStore` catches, `View[T]` raise propagation, detection before mutation | Not started |
| V12.11 | Diagnostics scenarios: mounted cached View, unmounted traced View, heterogeneous root callback, arbitrary thunk, stale View, closed Store | Not started |
| F7 | Keyed retirement resolution | Open |
| V12.1/V12.7 | Release benchmarks on both native (RC) and wasm-gc targets: chain, diamond, many roots, hot + unrelated inputs, 2500-block Markdown, getter churn | Not started |

Compile evidence exists: branch `spike/v12-5-view-alternatives`, commit
`a48bdc9`, confirmed three kernel constraints (opaque values are not
callable; structural closures expose no metadata methods; a setter closure
alone cannot recover its cell). Positive probes passed `moon check`, wasm-gc
release tests (1151/1151), and JS tests (256/256). These facts inform kernel
constraints; they do not constitute a model review or authorize
implementation.

---

## Rejected alternatives

| Alternative | Reason for rejection |
|---|---|
| Public opaque `View[T]` with `read()` | MoonBit has no overloadable call operator for opaque types; `source()` requires `source` to be a real function. Adds `read()` ceremony to every call site |
| Public two-layer (opaque kernel + product getter) | Compile-probe facts describe kernel constraints, not public-interface requirements. The public View captures private kernel state; users never handle opaque state directly |
| Previous/cached callback parameter | Observation-dependence, unenforceable equivalence law, mutable-alias risk, common `_ =>` tax. Incremental reuse belongs in domain-specific interfaces |
| All-Views registry for diagnostics | Under RC without weak references, the registry itself becomes a root and reintroduces the retention problem |
| Passive reverse edges | Forbidden by the View-owns-state placement. Reverse edges exist only in the active layer (mount table), released on Effect stop |
| Cross-Store abort | Current kernel misuses abort dynamically. The target uses typed `CrossStore(StoreMismatch)` detected before mutation; broader composition policy is deferred |
| Post-close lazy compute | Close seals the timeline. Fresh/materialized Views return frozen cache; stale or uncomputed Views raise `Closed`. No new computation occurs |

---

## Next step

V12.4 (ownership proof) is the first priority; it resolves the ownership
model's provisional status. No kernel implementation begins before V12.3 (parity oracle) and its
affected evidence gates pass.

---

No ADR needed: this document is a consolidation of gated research, not a
plan completion or architectural commission. The durable ADR path opens only
if the research track is commissioned or rejected.
