# Architecture Overview

This document is the **entry point for understanding the codebase**. It maps packages to responsibilities, sketches data flow, and points to deeper material when needed.

For the verification algorithm, type erasure, push propagation, and storage layout, see [`docs/design/internals.md`](design/internals.md) — that doc is more detailed and is the authoritative description of *how* things work. This doc focuses on *what each piece is*.

---

## Package responsibility map

The main MoonBit packages in `dowdiness/incr` are mapped below. Users import
only the root facade; everything else is implementation detail, tests, checked
documentation, or historical spike material. `moon.mod` excludes `docs/**` and
`spikes/**` from the published module, but `docs/` is still a package in the
worktree so literate examples can be checked.

```
dowdiness/incr           ← Public API facade (root)
├── types/               ← Pure value types, zero dependencies
├── cells/               ← Engine: coordinator + handle types + per-kind lifecycles
│   └── internal/
│       ├── shared/      ← Coordinator-only abstractions (CellOps, CellMeta, …)
│       ├── pull/        ← Pull-engine SoA storage (inputs + lazy derived values)
│       ├── push/        ← Push-engine SoA storage (Reactive, Effect)
│       ├── datalog/     ← Datalog SoA storage (Relation, Rule, …)
│       └── kernel/      ← Graph-mechanics algorithms (verify, propagate, gc, …)
├── pipeline/            ← Deprecated early pipeline trait sketches (Sourceable / Parseable / …)
├── tests/               ← Integration tests against the public API
└── docs/                ← Checked literate documentation examples
```

| Package | Responsibility | Depends on |
|---|---|---|
| Root (`incr.mbt`, `traits.mbt`) | Re-exports the target facade (`Input`, `Derived`, `ReachableDerived`, `DerivedMap`, `InputField`, `EagerDerived`, `Watch`, `MapRelation`, `RuntimeContext`, `Freshness`, `InputFieldOwner`) plus compatibility handles (`Signal`, `Memo`, `HybridMemo`, `MemoMap`, `TrackedCell`, `Reactive`, `Observer`, `FunctionalRelation`, `Database`, `Readable`, `Trackable`); provides RuntimeContext convenience helpers, compatibility helpers, and batching/lifecycle helpers | `cells`, `types` |
| `types/` | Pure value types: `Revision`, `Durability`, `CellId`, `CycleError`, ID types, `BackdateEq` / `HasChangedAt` traits | none |
| `cells/` | The `Runtime` coordinator (~570 LOC of thin delegators), target facades (`Input`, `Derived`, `ReachableDerived`, `DerivedMap`, `InputField`, `EagerDerived`, `Watch`, `MapRelation`), compatibility handles (`Signal`, `Memo`, `MemoMap`, `HybridMemo`, `TrackedCell`, `Reactive`, `Observer`, `FunctionalRelation`), Datalog/effect/accumulator/scope handles, and per-cell-kind lifecycle wiring | `types`, all `cells/internal/*` packages |
| `cells/internal/shared/` | Coordinator-only trait abstractions: `CellOps`, `HasCellMeta`, `Committable`, `CellMeta`, `CellRef`, `SlotSnapshot` | (leaf) |
| `cells/internal/pull/` | Struct-of-arrays storage for pull-mode cells (`PullSignalData`, `MemoData`) | `shared` |
| `cells/internal/push/` | SoA storage for push-mode cells (`PushReactiveData`, `PushEffectData`) | `shared` |
| `cells/internal/datalog/` | SoA storage for Datalog primitives (`RelationData`, `FunctionalRelationData`, `RuleData`) | `shared` |
| `cells/internal/kernel/` | Graph-mechanics algorithms used by the coordinator: pull-verify, push-propagate, batch commit, dispose/GC, dispatch, cycle detection, subscriber diff, fixpoint | `shared`, `pull`, `push`, `datalog` |
| `pipeline/` | Single file: deprecated early traits `Sourceable` / `Parseable` / `Checkable` / `Executable`. Too stringly-typed for shared build-system use; retained only for source compatibility. | none |
| `tests/` | Integration tests exercising only the public API | root |
| `docs/` | Checked literate examples for documentation. Excluded from the published module; imports the root facade only for test blocks. Historical `spikes/**` packages are also excluded and intentionally omitted from this map. | root |

The five `internal/` sub-packages use MoonBit's `internal` directory visibility, which the compiler enforces. The script `scripts/check-engine-isolation.sh` additionally enforces four hand-curated invariants on top of that (one-way kernel imports, leaf status of `shared`, no engine-to-engine sibling imports, no back-edges into `cells/`).

Naming note: this page is target-first for user-facing APIs. The older names
remain available as compatibility handles while migration continues. The
accepted naming target is recorded in
[ADR 2026-05-21](decisions/2026-05-21-public-api-ideal-naming.md): `Signal ->
Input`, `Memo -> Derived`, `HybridMemo -> ReachableDerived`, `Reactive ->
EagerDerived`, `MemoMap -> DerivedMap`, `TrackedCell -> InputField`, `Observer
-> Watch`, `FunctionalRelation -> MapRelation`, `Readable -> Freshness`,
`Trackable -> InputFieldOwner`, and `Database -> RuntimeContext`.

---

## Main data flow

`incr` mixes **three** computation modes, all coordinated by a single `Runtime`:

```
        ┌───────────────────────────────┐
        │      Runtime (coordinator)    │
        │  revision, batch, phase, GC   │
        └────┬───────────┬──────────┬───┘
             │           │          │
       ┌─────▼──────┐ ┌──▼─────┐ ┌──▼──────────┐
       │  PULL      │ │  PUSH  │ │  DATALOG    │
       │ Input      │ │EagerD. │ │ Relation    │
       │ Derived    │ │ Effect │ │ Rule        │
       │ DerivedMap │ │        │ │ Fixpoint    │
       │ReachableD.*│ │        │ │ MapRelation │
       │InputField  │ │        │ │             │
       └────────────┘ └────────┘ └─────────────┘
       lazy verify   push prop.   bottom-up fix
       on read       on input     point loop
```
\* `ReachableDerived` wraps the hybrid memo engine: recomputation is pull-driven
(lazy verification on read), but the underlying memo is push-reachable from
downstream `EagerDerived`/`Effect` subscribers — though so is a plain `Derived`
today (see Hybrid mode below). A `Watch` on a terminal target also keeps that
watched value alive across `gc()`.

**Pull mode (Input → Derived):**

1. `input.set(v)` writes to the input cell and bumps `current_revision`
   (deferred during a batch).
2. A strict guarded `derived.get()` inside the graph or permissive
   `derived.read()` outside the graph walks the dependency graph backwards when
   needed. A node is *verified* if its `verified_at >= current_revision`;
   otherwise its dependencies are checked, and the node either reuses its
   cached value (backdating) or recomputes.
3. The durability fast-path lets a derived value skip the dep walk entirely if
   no input at its durability level changed since last verification.

**Push mode (EagerDerived / Effect):**

1. `eager.read()` returns an eagerly maintained cached value; input changes
   trigger immediate level-by-level propagation through downstream push nodes.
2. `Effect` is a sink — runs side-effecting closures at the appropriate level.

**Hybrid mode (`ReachableDerived` / compatibility `HybridMemo`):**

`ReachableDerived` is a pull-derived facade whose underlying hybrid memo uses
the same revision check as `Derived` — there is no separate dirty flag. **Today
it is behaviorally identical to `Derived`:** both participate in
`push_reachable_count`, so a live `EagerDerived`/`Effect` subscriber downstream
keeps either one (and its upstream cells) alive across `gc()`, and the
`is_hybrid` flag is read by no behavioral branch. The type is currently a
boundary marker for the push/pull seam, not a distinct behavior. See
[ADR 2026-05-30](decisions/2026-05-30-reachable-derived-differentiate-or-collapse.md)
for the decision to either differentiate it into a genuine eager-when-reachable
memo or collapse it into `Derived`.

**Datalog mode (`Relation`, `Rule`, fixpoint):**

`rt.fixpoint()` runs declarative rules to a fixed point, semi-naive in nature.
`MapRelation[K, V]` is the target key-indexed projection facade over the
compatibility `FunctionalRelation[K, V]`.

**Batching:**

`batch` and `batch_result` defer all `set` operations and revision bumps to the end of the block, with rollback on raised errors. See the [Cookbook](cookbook.mbt.md) for revert detection semantics.

---

## Key types and their roles

| Type | Role | Created via |
|---|---|---|
| `Runtime` | Owns all dependency state, revision counter, batch frames, GC roots, lifecycle dispatch tables | `Runtime(on_change?)` or `Runtime::new(on_change?)` |
| `Input[T]` | Externally settable input cell | `Input(rt, value, durability?, label?)` or `scope.input(...)` |
| `Derived[T]` | Lazy pull-derived value with strict guarded `get()` and permissive `read()` `Result` APIs | `Derived(rt, compute, label?)` or `scope.derived(...)` |
| `DerivedMap[K, V]` | Lazy per-key derived values with target cache helpers | `DerivedMap(rt, compute, label?)` or `scope.derived_map(...)` |
| `ReachableDerived[T]` | Lazy derived value with strict guarded `get()` and permissive `read()` APIs; push-reachable from downstream `EagerDerived`/`Effect`; no dirty flag — behaviorally identical to `Derived` today (see [ADR 2026-05-30](decisions/2026-05-30-reachable-derived-differentiate-or-collapse.md)) | `ReachableDerived(rt, compute, label?)` or `scope.reachable_derived(...)` |
| `InputField[T]` | Field-level input cell for structs implementing `InputFieldOwner` | `InputField(rt, value, durability?, label?)` or `scope.input_field(...)` |
| `EagerDerived[T]`, `Effect` | Push-mode primitives | `EagerDerived(rt, compute)`, `Effect::new` |
| `Relation[T]`, `MapRelation[K,V]`, `Rule` | Datalog primitives, driven by `rt.fixpoint()` | `Relation::new`, `MapRelation(rt)`, `rt.new_rule(...)`, … |
| `Accumulator[T]` | Side-channel collector pushed to from memo computes; consumers currently read via compatibility `Memo::accumulated` and are correctly invalidated. See [ADR](decisions/2026-04-20-accumulator-api.md). | `Accumulator::new` or `create_accumulator` |
| `Scope` | Lifecycle group: cells/accumulators registered to a scope are disposed when the scope is disposed | `Scope::new`, target `scope.input` / `scope.derived` helpers, or compatibility `create_scope` |
| `Watch[T]` | Persistent attachment that keeps a derived/eager value alive past `gc()` sweeps and returns `Result` reads | `derived.watch()` / `reachable.watch()` / `eager.watch()` |
| Compatibility handles | Older source-compatible names: `Signal`, `Memo`, `MemoMap`, `HybridMemo`, `TrackedCell`, `Reactive`, `Observer`, `FunctionalRelation`; keep using them for low-level introspection and APIs not yet surfaced on target facades | Compatibility constructors and helpers (`Signal::new`, `Memo::new*`, `create_signal`, `create_memo`, …) |
| `CellId`, `CellInfo`, `CycleError`, `Revision`, `Durability` | Plain value types | constructors in `types/` |
| Traits `RuntimeContext`, `Freshness`, `InputFieldOwner` | Target extension points (see below) | — |
| Compatibility traits `Database`, `Readable`, `Trackable` | Older helper/introspection extension points retained during migration | — |

---

## Important invariants

These are user-visible properties the library upholds. Internal implementation invariants are in [`internals.md`](design/internals.md).

- **Revision monotonicity.** `current_revision` only increases. Same-value `set()` on an `Input[T : Eq]` or `InputField[T : Eq]` is a no-op and does not bump it.
- **Lazy pull, eager push.** A `Derived` value recomputes only when read; an `EagerDerived` value propagates immediately when upstream inputs change (or at batch commit if inside one).
- **Pull mode verifies traces, not dirty flags.** A pull-derived value records the dependencies read by its last successful compute. On the next read, the runtime verifies that recorded trace; it does not rely on an eagerly propagated dirty bit as the source of truth.
- **Backdating preserves `changed_at`.** When a derived value recomputes to a value equal (by `Eq` or compatibility `BackdateEq`) to its previous result, its `changed_at` is *not* bumped — downstream consumers see no change and skip work.
- **Durability shortcut.** Derived values whose inputs are all `High` durability skip the full verify walk when no `High` input has changed.
- **Cycle detection returns `Result`.** Target `Derived::get()` / `read()` and `DerivedMap::get(key)` / `read(key)` surface cycles as `Err(CycleError)`; strict `get` methods still abort when called without an active tracked context. `_or_abort` shortcuts abort on cycle. Compatibility `Memo::get_result()` exposes the same error value. `CycleError` is pure (no `Runtime` reference) and can be formatted standalone.
- **Cross-runtime reads are illegal.** Reading a cell from a runtime other than the one owning the surrounding compute aborts.
- **Batch atomicity.** A `batch` that raises rolls back all writes inside it (state and revision counter included). `abort()` is *not* catchable and leaves the runtime in an undefined state.
- **Top-frame restriction on `Accumulator::push`.** Pushes are only legal inside a compatibility `Memo` or `HybridMemo` compute; pushing from elsewhere raises `Failure`. See the [Accumulator ADR](decisions/2026-04-20-accumulator-api.md).

---

## Extension points

Target traits define the preferred extension surface:

- **`RuntimeContext`** — implement it on your own struct to encapsulate a `Runtime`. Convenience helpers such as `create_input`, `create_derived`, `create_reachable_derived`, `create_eager_derived`, and `create_derived_map` accept any `RuntimeContext`; direct constructors and `Scope` methods are the primary target construction surface.
- **`Freshness`** — implemented for target readable handles, exposes `is_fresh(self) -> Bool`. Useful for generic freshness checks.
- **`InputFieldOwner`** — implement it on a struct with `InputField` fields to expose its constituent `CellId`s as a single unit, enabling `add_input_fields(scope, owner)` for bulk lifecycle management.

Compatibility traits remain available:

- **`Database`** — older context trait used by compatibility helper functions such as `create_signal`, `create_memo`, `create_memo_map`, `batch`, and `batch_result`.
- **`Readable`** — older freshness trait with `is_up_to_date(self) -> Bool`.
- **`Trackable`** — older field-owner trait for structs with `TrackedCell` fields, used by `add_tracked(scope, tracked)`.

The library does **not** offer:

- A way to define new cell *kinds* from user code. The engine taxonomy (`PullSignal`, `Memo`, `Reactive`, `Effect`, `Relation`, `FunctionalRelation`, `Rule`, `HybridMemo`) is closed and lives inside `cells/`; target facades wrap those engine kinds rather than extending the taxonomy.
- A way to plug in a custom verification algorithm or scheduling policy.

---

## Non-goals

These are inferred from the code's structure and the consistent direction of recent design decisions (see `docs/decisions/`):

- **Multi-runtime sharing.** Cells are bound to one `Runtime`; cross-runtime reads abort by design.
- **Concurrency / parallel verification.** Single-threaded; no synchronization primitives. The `Runtime` is not `Sync`-safe.
- **Persistent caching across runs.** State lives in process memory; there is no on-disk format for memo caches.
- **A general reactive UI framework.** Push primitives exist but the library is not optimized for shallow-wide UI graphs the way alien-signals is. See [`comparison-with-alien-signals.md`](design/comparison-with-alien-signals.md).
- **Garbage collection at the level of allocator finalization.** `Runtime::gc()` sweeps unreachable cell slots after explicit disposal; it is not a tracing GC.

---

## Known limitations

Items the audit verified against current code; if any of these is wrong, the code has moved and this doc should be updated.

- **`pipeline/` is deprecated.** The four traits in that package are too stringly-typed for shared build-system use and are not used internally. Define application-local build traits with concrete key, diagnostic, syntax, and artifact types instead.
- **`gc_tracked(rt, t)` is a deprecated no-op.** For target field owners, use `add_input_fields(scope, owner)`. For compatibility `TrackedCell` owners, use `add_tracked(scope, tracked)`. The `#deprecated` attribute on `gc_tracked` in `traits.mbt` confirms this.
- **Hand-maintained `docs/api-reference.mbt.md`.** It has drifted from `.mbti` at least once (caught in the most recent audit). Treat the `.mbti` files as authoritative when they disagree.
- **Most prose examples are still illustrative.** The target-API examples in [`target_api_examples.mbt.md`](target_api_examples.mbt.md) are checked by `moon check`, but many longer ` ```moonbit` snippets in prose docs are still unchecked. Continue migrating high-value examples to `.mbt.md` literate tests as APIs stabilize.
- **No CI in this submodule.** Verification is delegated to the parent `canopy` repo; running `moon check && moon test` locally before pushing is the operative discipline.

---

## Where to read next

- **Algorithms (verify, push propagate, backdating, type erasure, SoA layout):** [`docs/design/internals.md`](design/internals.md)
- **Design philosophy (progressive disclosure, type-driven constraints, naming):** [`docs/design/api-design-guidelines.md`](design/api-design-guidelines.md)
- **Significant decisions:** [`docs/decisions/`](decisions/)
- **Performance baselines:** [`docs/performance/`](performance/)
- **What's planned vs done:** [`docs/roadmap.md`](roadmap.md) and [`docs/todo.md`](todo.md)
