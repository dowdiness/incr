# Architecture Overview

This document is the **entry point for understanding the codebase**. It maps packages to responsibilities, sketches data flow, and points to deeper material when needed.

For the verification algorithm, type erasure, push propagation, and storage layout, see [`docs/design/internals.md`](design/internals.md) — that doc is more detailed and is the authoritative description of *how* things work. This doc focuses on *what each piece is*.

---

## Package responsibility map

There are five MoonBit packages in `dowdiness/incr`. Users import only the root facade; everything else is implementation detail.

```
dowdiness/incr           ← Public API facade (root)
├── types/               ← Pure value types, zero dependencies
├── cells/               ← Engine: coordinator + handle types + per-kind lifecycles
│   └── internal/
│       ├── shared/      ← Coordinator-only abstractions (CellOps, CellMeta, …)
│       ├── pull/        ← Pull-engine SoA storage (Signal, Memo)
│       ├── push/        ← Push-engine SoA storage (Reactive, Effect)
│       ├── datalog/     ← Datalog SoA storage (Relation, Rule, …)
│       └── kernel/      ← Graph-mechanics algorithms (verify, propagate, gc, …)
├── pipeline/            ← Experimental trait sketches (Sourceable / Parseable / …)
└── tests/               ← Integration tests against the public API
```

| Package | Responsibility | Depends on |
|---|---|---|
| Root (`incr.mbt`, `traits.mbt`) | Re-exports types, defines `Database` / `Readable` / `Trackable` traits, provides `create_*` helpers and `batch` / `batch_result` / `add_tracked` / `gc_tracked` | `cells`, `types` |
| `types/` | Pure value types: `Revision`, `Durability`, `CellId`, `CycleError`, ID types, `BackdateEq` / `HasChangedAt` traits | none |
| `cells/` | The `Runtime` coordinator (~430 LOC of thin delegators), handle types (`Signal`, `Memo`, `MemoMap`, `HybridMemo`, `TrackedCell`, `Reactive`, `Effect`, `Relation`, `FunctionalRelation`, `Accumulator`, `Scope`, `Observer`), and per-cell-kind lifecycle wiring | `types`, all `cells/internal/*` packages |
| `cells/internal/shared/` | Coordinator-only trait abstractions: `CellOps`, `HasCellMeta`, `Committable`, `CellMeta`, `CellRef`, `SlotSnapshot` | (leaf) |
| `cells/internal/pull/` | Struct-of-arrays storage for pull-mode cells (`PullSignalData`, `MemoData`) | `shared` |
| `cells/internal/push/` | SoA storage for push-mode cells (`PushReactiveData`, `PushEffectData`) | `shared` |
| `cells/internal/datalog/` | SoA storage for Datalog primitives (`RelationData`, `FunctionalRelationData`, `RuleData`) | `shared` |
| `cells/internal/kernel/` | Graph-mechanics algorithms used by the coordinator: pull-verify, push-propagate, batch commit, dispose/GC, dispatch, cycle detection, subscriber diff, fixpoint | `shared`, `pull`, `push`, `datalog` |
| `pipeline/` | Single file, 52 LOC: experimental traits `Sourceable` / `Parseable` / `Checkable` / `Executable`. Used only by `tests/`. Stability and direction are uncommitted — treat as a sketch. | none |
| `tests/` | Integration tests exercising only the public API | root, `pipeline` |

The five `internal/` sub-packages use MoonBit's `internal` directory visibility, which the compiler enforces. The script `scripts/check-engine-isolation.sh` additionally enforces four hand-curated invariants on top of that (one-way kernel imports, leaf status of `shared`, no engine-to-engine sibling imports, no back-edges into `cells/`).

Naming note: this page describes the current codebase. The accepted ideal
public API naming target is recorded in
[ADR 2026-05-21](decisions/2026-05-21-public-api-ideal-naming.md):
`Signal -> Input`, `Memo -> Derived`, `HybridMemo -> ReachableDerived`,
`Reactive -> EagerDerived`, `MemoMap -> DerivedMap`, `TrackedCell ->
InputField`, `Observer -> Watch`, `FunctionalRelation -> MapRelation`,
`Readable -> Freshness`, `Trackable -> InputFieldOwner`, and `Database ->
RuntimeContext`.

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
       │ Signal     │ │Reactive│ │ Relation    │
       │ Memo       │ │ Effect │ │ Rule        │
       │ MemoMap    │ │        │ │ Fixpoint    │
       │HybridMemo* │ │        │ │FunctionalR. │
       │TrackedCell │ │        │ │             │
       └────────────┘ └────────┘ └─────────────┘
       lazy verify   push prop.   bottom-up fix
       on .get()     on .set()    point loop
```
\* `HybridMemo` participates in both engines: recomputation is pull-driven (lazy revision check on `get`), but the memo is push-reachable from downstream `Reactive`/`Effect` subscribers so live observers keep upstream cells alive across `gc()`.

**Pull mode (Signal → Memo):**

1. `signal.set(v)` writes to the signal cell and bumps `current_revision` (deferred during a batch).
2. The next `memo.get()` walks the dependency graph backwards. A node is *verified* if its `verified_at >= current_revision`; otherwise its dependencies are checked, and the node either reuses its cached value (backdating) or recomputes.
3. The durability fast-path lets a memo skip the dep walk entirely if no input at its durability level changed since last verification.

**Push mode (Reactive / Effect):**

1. `reactive.set(v)` triggers immediate level-by-level propagation through downstream push nodes.
2. `Effect` is a sink — runs side-effecting closures at the appropriate level.

**Hybrid mode (`HybridMemo`):**

`HybridMemo` is a pull memo whose recomputation trigger is the same revision check as `Memo` — there is no separate dirty flag. What makes it hybrid is *reachability*, not invalidation: it participates in `push_reachable_count` so that a live `Reactive`/`Effect` observer downstream keeps the memo and its upstream cells alive across `gc()`. Use it on the boundary between push-reactive subscribers and pull-derived values.

**Datalog mode (`Relation`, `Rule`, fixpoint):**

`rt.fixpoint()` runs declarative rules to a fixed point, semi-naive in nature. `FunctionalRelation[K, V]` is a key-indexed projection.

**Batching:**

`batch` and `batch_result` defer all `set` operations and revision bumps to the end of the block, with rollback on raised errors. See the [Cookbook](cookbook.md) for revert detection semantics.

---

## Key types and their roles

| Type | Role | Created via |
|---|---|---|
| `Runtime` | Owns all dependency state, revision counter, batch frames, GC roots, lifecycle dispatch tables | `Runtime::new(on_change?)` |
| `Signal[T]` | Externally settable input cell | `Signal::new` or `create_signal(db, ...)` |
| `Memo[T]` | Memoized pull-derived value, three backdating strategies (`new` / `new_memo` / `new_no_backdate`) | `Memo::new*` or `create_memo` |
| `MemoMap[K, V]` | Lazy per-key memos | `MemoMap::new` or `create_memo_map` |
| `HybridMemo[T]` | Pull memo that is push-reachable from downstream `Reactive`/`Effect`; no dirty flag — same lazy revision check as `Memo` | `HybridMemo::new` or `create_hybrid_memo` |
| `TrackedCell[T]` | Like `Signal[T]`, intended as a struct field (`Trackable` rolls them up) | `TrackedCell::new` or `create_tracked_cell` |
| `Reactive[T]`, `Effect` | Push-mode primitives | `Reactive::new`, `Effect::new` |
| `Relation[T]`, `FunctionalRelation[K,V]`, `Rule` | Datalog primitives, driven by `rt.fixpoint()` | `Relation::new`, `rt.new_rule(...)`, … |
| `Accumulator[T]` | Side-channel collector pushed to from memo computes; consumers read via `Memo::accumulated` and are correctly invalidated. See [ADR](decisions/2026-04-20-accumulator-api.md). | `Accumulator::new` or `create_accumulator` |
| `Scope` | Lifecycle group: cells/accumulators registered to a scope are disposed when the scope is disposed | `Scope::new` or `create_scope` |
| `Observer[T]` | Persistent attachment that keeps a memo/reactive alive past `gc()` sweeps | `memo.observe()` / `reactive.observe()` |
| `CellId`, `CellInfo`, `CycleError`, `Revision`, `Durability` | Plain value types | constructors in `types/` |
| Traits `Database`, `Readable`, `Trackable` | User-facing extension points (see below) | — |

---

## Important invariants

These are user-visible properties the library upholds. Internal implementation invariants are in [`internals.md`](design/internals.md).

- **Revision monotonicity.** `current_revision` only increases. Same-value `set()` on a `Signal[T : Eq]` is a no-op and does not bump it.
- **Lazy pull, eager push.** A `Memo` recomputes only when read; a `Reactive` propagates immediately on set (or at batch commit if inside one).
- **Backdating preserves `changed_at`.** When a memo recomputes to a value equal (by `Eq` or `BackdateEq`) to its previous result, its `changed_at` is *not* bumped — downstream consumers see no change and skip work.
- **Durability shortcut.** Memos whose inputs are all `High` durability skip the full verify walk when no `High` input has changed.
- **Cycle detection returns `Result`.** `get_result()` surfaces cycles as `Err(CycleError)`; `get()` aborts on cycle. `CycleError` is a pure value (no `Runtime` reference) and can be formatted standalone.
- **Cross-runtime reads are illegal.** Reading a cell from a runtime other than the one owning the surrounding compute aborts.
- **Batch atomicity.** A `batch` that raises rolls back all writes inside it (state and revision counter included). `abort()` is *not* catchable and leaves the runtime in an undefined state.
- **Top-frame restriction on `Accumulator::push`.** Pushes are only legal inside a `Memo` or `HybridMemo` compute; pushing from elsewhere raises `Failure`. See the [Accumulator ADR](decisions/2026-04-20-accumulator-api.md).

---

## Extension points

Three traits define the current supported extension surface:

- **`Database`** — implement it on your own struct to encapsulate a `Runtime`. All `create_*` helpers and `batch` / `batch_result` accept any `Database`. This is the current production idiom; the ideal target name is `RuntimeContext`, and custom struct constructors are the target primary construction surface.
- **`Readable`** — implemented for all cell-like handles, exposes `is_up_to_date(self) -> Bool`. Useful for writing generic introspection helpers.
- **`Trackable`** — implement it on a tracked struct to expose its constituent `CellId`s as a single unit, enabling `add_tracked(scope, t)` for bulk lifecycle management.

The library does **not** offer:

- A way to define new cell *kinds* from user code. The taxonomy (`PullSignal`, `Memo`, `Reactive`, `Effect`, `Relation`, `FunctionalRelation`, `Rule`, `HybridMemo`) is closed and lives inside `cells/`.
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

- **`pipeline/` is uncommitted.** The four traits in that package are not used internally and have no roadmap item. Treat as exploratory.
- **`gc_tracked(rt, t)` is a deprecated no-op.** Use `add_tracked(scope, t)`. The `#deprecated` attribute on the function in `traits.mbt` confirms (search for `pub fn[T : Trackable] gc_tracked`).
- **Hand-maintained `docs/api-reference.md`.** It has drifted from `.mbti` at least once (caught in the most recent audit). Treat the `.mbti` files as authoritative when they disagree.
- **No `mbt check` blocks across the user-facing docs at the time of this writing.** Examples are illustrative; drift catches only show up in integration tests under `tests/`. Migration toward `.mbt.md` literate examples is a recommended follow-up.
- **No CI in this submodule.** Verification is delegated to the parent `canopy` repo; running `moon check && moon test` locally before pushing is the operative discipline.

---

## Where to read next

- **Algorithms (verify, push propagate, backdating, type erasure, SoA layout):** [`docs/design/internals.md`](design/internals.md)
- **Design philosophy (progressive disclosure, type-driven constraints, naming):** [`docs/design/api-design-guidelines.md`](design/api-design-guidelines.md)
- **Significant decisions:** [`docs/decisions/`](decisions/)
- **Performance baselines:** [`docs/performance/`](performance/)
- **What's planned vs done:** [`docs/roadmap.md`](roadmap.md) and [`docs/todo.md`](todo.md)
