# Analysis: incr vs Salsa (rust-analyzer's incremental query engine)

> Companion to [comparison-with-alien-signals.md](comparison-with-alien-signals.md)
> (the UI-reactivity axis) and [internals.md](internals.md) (incr's own
> verification/backdating mechanics). This note covers the *compiler/IDE
> incrementality* axis: where incr sits relative to Salsa, the engine behind
> rust-analyzer. Salsa facts here describe its stable design model, not a
> specific API version; incr facts cite types in the current `.mbti`.

## Where each engine sits in its stack

rust-analyzer is built from two layers that incr fuses into one:

| Concern | rust-analyzer | incr / canopy |
|---|---|---|
| Lossless syntax tree (position-independent data) | **rowan** green tree + positioned red `SyntaxNode` | loom `CstNode` (green) + `SyntaxNode` (red) |
| Incremental semantic computation | **Salsa** (memoized queries) | **incr** (`Input` / `Derived` / `DerivedMap`) |
| UI reactivity (drive the editor on change) | the **LSP client** (separate process) | **incr** again (push: `ReachableDerived` + `Watch`/`Observer`) |

The red-green split is the same in both: a position-independent green tree
(relative widths, structurally interned, reused across edits) plus an ephemeral
positioned facade computed on demand. Position-independence is what lets an
unchanged subtree be reused even when it *moved* — the green node is byte-identical
regardless of absolute offset. **Neither project computes semantics as folds over
the green tree**; both push that to the query engine. So the comparison that
matters is incr ↔ Salsa.

## The shared core: both are red-green / firewall engines

Both implement the demand-driven incremental algorithm Salsa popularized:

| Mechanism | Salsa | incr |
|---|---|---|
| Global **revision** counter, bumped on input change | ✓ | ✓ `advance_revision(_, Durability)` |
| **Durability** levels to skip validation sweeps | ✓ (low/med/high) | ✓ `get_durability`, durability-tagged revisions |
| Per-cell **`changed_at` / verified-at** tracking | ✓ | ✓ `get_changed_at -> Revision` |
| **Backdating** (re-exec, equal result → keep old `changed_at`) | ✓ | ✓ `BackdateEq` |
| **Cycle** detection | ✓ | ✓ `CycleError` |
| Demand-driven **pull** (compute only what is read) | ✓ (only mode) | ✓ `PullState` |

`incr.Input` ≈ Salsa `#[input]`; `incr.Derived` ≈ a memoized `#[tracked]` query;
`incr.DerivedMap[K,V]` ≈ a per-key tracked query. The firewall property — "a
change that doesn't change the output stops propagating" — is identical in spirit.

## Three divergences — all traceable to one cause

### 1. Pull-only vs. pull + push + Datalog

Salsa has one propagation mode: pull. incr threads **three** state objects through
its runtime — `PullState`, `PushState`, `DatalogState`:

- **Pull** — the Salsa-equivalent lazy memo (`Derived`).
- **Push** — *eager reactive propagation* (`add_subscriber`, `propagate_changes`,
  `fire_on_change`). Salsa has nothing like this; consumers must pull.
  `ReachableDerived` + `Watch`/`Observer` ride this layer.
- **Datalog** — a *relational, insert-only* fact layer. Salsa is purely functional
  memoization. incr's Datalog state is **insert-only across revisions (no
  retract)**, which is why some loom features (e.g. `callers`/`visible_from`) are
  modeled as a `Memo`, not as Datalog relations.

### 2. GC-by-roots vs. LRU eviction

Salsa bounds memory with **LRU eviction** — drop a memoized value, recompute on
demand if pulled again (correctness-neutral). incr uses **mark-sweep GC with
explicit roots** (`add_gc_root`, `gc_sweep`): a long-lived `Derived` that nothing
roots is *collected*, so it must be anchored by a `Watch`/`Observer` — and the
anchor must be *primed* (its `gc_dependencies` are empty until the closure runs
once). "Recompute if evicted" is wrong when the cell *is* live UI state.

### 3. Single-runtime vs. multi-runtime

incr carries `RuntimeId` + cross-runtime guards (isolated reactive graphs). Salsa
is one database per program.

### The cause: what each engine drives

- **rust-analyzer is an LSP *server*.** The editor is a separate process;
  reactivity flows over LSP notifications, *outside* Salsa. So Salsa only answers
  "what's the value here, now?" on demand → pull suffices, and LRU is fine because
  a re-pull just recomputes.
- **canopy is an *in-process projectional editor*.** The UI lives in the *same*
  reactive graph, so incr must (a) **push** to drive visible widgets and (b) use
  **rooted GC** so a cell a widget depends on is deterministically retained.
  Datalog and multi-runtime are further reach for relational projections and
  isolated editor instances.

In one line: **incr is Salsa's pull core plus a reactive UI runtime, fused into
one graph, because canopy's UI shares that graph whereas rust-analyzer's UI is a
separate client.**

## Backdating in depth — incr generalizes Salsa along three axes

Backdating is the optimization that *stops* propagation: when a `Derived`
re-executes (a dependency changed) but produces "the same" result, the engine
keeps the old `changed_at` so downstream cells skip recomputation. incr names the
two outcomes explicitly: `DerivedRebuildDisposition { RecomputedChanged |
RecomputedBackdated }` (in `cells/internal/kernel`). That is exactly Salsa's
backdate path. incr then generalizes it three ways Salsa cannot express.

### Axis 1 — equality is a trait, not the value's `Eq`

Salsa backdates on the value type's `PartialEq`/`Eq` (`new == old`). incr uses a
dedicated trait (`incr/types`):

```moonbit
pub(open) trait BackdateEq : HasChangedAt {
  fn backdate_equal(Self, Self) -> Bool = _   // overridable; default provided
}
pub(open) trait HasChangedAt {
  fn changed_at(Self) -> Revision
}
```

Two things Salsa's value-`Eq` cannot do:

- **Custom "equal enough."** `backdate_equal` can be *looser* than `==` (ignore an
  incidental field, compare only the semantically relevant part), so propagation
  stops in more cases than structural equality permits.
- **Version-aware backdating.** The `HasChangedAt` supertrait means the value
  carries its own `changed_at` — backdating can decide by **version/identity**, not
  just deep structure.

**Hazard this introduces:** if `backdate_equal` is always-true (e.g. a `Unit`
payload, or a careless override), every recompute backdates → downstream is
*never* invalidated → silent staleness. A `Derived` that folds/aggregates must
therefore carry a *per-revision-changing key or token* in its value; do not let an
information-free value flow through `BackdateEq`. Salsa's value-`Eq` makes this
hard to hit by accident; incr's custom predicate makes it the author's
responsibility.

### Axis 2 — an explicit no-backdate tier

```moonbit
Memo::new_memo(rt, f)        // T : BackdateEq → backdating ON
Memo::new_no_backdate(rt, f) // no bound       → always RecomputedChanged
```

A clean per-cell choice between "stop propagation when equal" and "always treat as
changed." Salsa's opt-out is coarser and rarely used.

### Axis 3 — `AcceptedDerived`: backdating × fallibility (no Salsa equivalent)

This is the real departure. Over a fallible computation `() -> Result[V, E]`,
`AcceptedDerived[V, E]` (in `incr/cells`) splits two things Salsa conflates:

- `current : Result[V, E]` — what was just computed (may be `Err`)
- `accepted : V?` — the last *good* value downstream consumes
- `accepted_changed_at : Revision` — when the accepted value last changed
- `watch_accepted : Watch[V?]` — push stream of accepted values only

…with a **four-way** disposition (vs Salsa's two):

```moonbit
pub(all) enum AcceptStatus {
  NoAccept            // nothing accepted yet
  AcceptedChanged     // new good value, differs from last → changed_at bumped
  AcceptedUnchanged   // new good value, backdate-equal to last → backdated
  RetainedDueToError  // computation returned Err → keep last good, do NOT propagate
}
```

`AcceptedUnchanged` is ordinary backdating. `RetainedDueToError` is new: an `Err`
does **not** overwrite the accepted value or fire a change; downstream keeps the
last good value and `accepted_changed_at` stays put. Salsa has no built-in
"keep last successful output on error" — an `Err` there is just a different value
that propagates.

**Why incr needs this and Salsa doesn't:** the projectional-editor requirement.
Mid-keystroke the source is transiently unparseable/untypeable → the parse or
typecheck `Derived` returns `Err`. canopy must keep showing the *last good
projection*, not blank the screen on every momentarily-invalid edit.
`RetainedDueToError` encodes that in the engine. rust-analyzer doesn't need it as
an engine feature: it emits error nodes + diagnostics and lets the *client* decide
what to display. (This is the same root cause as the pull-vs-push and
GC-roots-vs-LRU splits.) loom's "advance the projection-identity baseline only
after semantic lowering succeeds" sits directly on top of `AcceptedDerived`.

### Observable decisions (a smaller, real difference)

incr exposes the backdating decision as *data* — `DerivedRebuildDisposition`,
`AcceptStatus`, `AcceptedSnapshot`, a `backdated : Bool` flag — so editor code can
*reason about* "did this stay the same / did we fall back to last-good," not just
benefit from it silently. Salsa's backdating is an internal optimization with no
public surface.

## Bottom line

Salsa backdates on value-`Eq` with two outcomes (changed / backdated). incr
backdates on a customizable, version-aware `backdate_equal`, adds an explicit
no-backdate tier, and — uniquely — a `RetainedDueToError` "keep last-good"
disposition over `Result[V, E]`. Every generalization exists because canopy's
editor must survive transient parse/type errors *inside* the incremental graph,
whereas rust-analyzer pushes that concern out to a separate LSP client. The data
layer (rowan/`CstNode` green-tree reuse) and the firewall (revisions + durability
+ backdating) are shared heritage; the push runtime, rooted GC, Datalog state, and
the `AcceptedDerived` acceptance model are where the in-process editor diverges.
