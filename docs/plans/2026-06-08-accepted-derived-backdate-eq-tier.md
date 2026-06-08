# AcceptedDerived — `BackdateEq` (revision-gated) tier

**Status:** incr-side complete (branch `feat/accepted-derived-backdate-eq`,
944 wasm + 41 js green, Codex pre-PR review PASS). Downstream `loom-mini-cst`
validation pending. Deltas from the original step plan: `assemble` was UNIFIED
(one `same`-parameterized path for both tiers, not a separate BackdateEq
assemble); the fold carries a **`Bool` accept-signal toggle** (not an epoch
`Int` — only its change matters, so no overflow); `accepted_memo_from_candidate`
was DROPPED (no public non-`Eq` candidate constructor to feed it → would be dead
surface); `from_candidate`'s `E : Eq` was relaxed to `E`.
**Date:** 2026-06-08
**Spec:** [docs/design/specs/2026-06-05-committed-derived.md](../design/specs/2026-06-05-committed-derived.md) (open question #3)
**Driver:** MoonDsp `loom-mini-cst` validation (stage 5). `PatternDoc`/`PatternSnapshot`
are not `Eq` but carry a `revision` field → `BackdateEq`-eligible.

## Why

`AcceptedDerived[V, E]` currently requires `V : Eq, E : Eq`. Every confirmed
downstream candidate type (MoonDsp `PatternDoc`/`PatternSnapshot`) is **not `Eq`**
— their reactive pipelines already use `Memo::new_no_backdate` precisely because
there is no `Eq`. So the deferred no-`Eq` variant is the real prerequisite for any
downstream adoption. The engine already models the relaxation: `Memo::new`
(`Eq`) / `new_memo` (`BackdateEq`, revision-based, O(1)) / `new_no_backdate`
(none), all via one comparator threaded into `Memo::_create`.

## Scope decision (Codex-recommended, design-owner-approved)

**This PR ships the `BackdateEq` tier only.** It unblocks `loom-mini-cst`
(revision-bearing types) without weakening the observable contract:
`AcceptedUnchanged` and `accepted_changed_at()` stay meaningful.

**Deferred to a follow-up PR:** the `no_backdate` tier. It makes
`AcceptedUnchanged` structurally unobservable and redefines
`accepted_changed_at()` as "fold advanced this revision" — a different semantic
model that must be introduced deliberately with its own docs + tests. No current
consumer needs it.

## Design (the WHAT — validated by Codex)

One **sameness predicate** `same : (V, V) -> Bool` is the single source of truth.
It drives BOTH the `accepted_transition` status (`AcceptedUnchanged` vs
`AcceptedChanged`) AND the `accepted_cell` backdating, so the two cannot diverge.
For the `BackdateEq` tier, `same = (a, b) => a.backdate_equal(b)`. The existing
`Eq` tier is the special case `same = (a, b) => a == b`.

`E : Eq` is **retained** in all tiers. Downstream errors are `String` (trivially
`Eq`); keeping `E : Eq` preserves the "repeated equal error backdates the current
channel" row and minimizes breakpoints. Only `V` is relaxed.

### Internal mechanism (the three cells `assemble` builds)

`Derived[T]` is `{ priv inner : Memo[T] }`; the `inner` field and
`Memo::_create(rt, compute, label?, backdate_eq : (T,T) -> Bool)` are both
package-reachable from `accepted_derived.mbt`. Cells register with the scope via
`scope.cells.push(inner.id())` (what `Scope::derived` does).

1. **Candidate** `Derived[Result[V,E]]` — built via `Memo::_create` with a
   `Result` comparator, NOT `Derived::fallible` (which is `V:Eq,E:Eq`):
   `(Ok(a),Ok(b)) => same(a,b); (Err(a),Err(b)) => a == b; _ => false`.
   This relaxes the candidate's `V` bound while preserving error-channel
   backdating. (`E : Eq` used on the `Err` arm.)

2. **Accepted projection** `accepted_cell : Derived[V?]` — built via `Memo::_create`
   with an `Option`-lifted comparator:
   `(None,None) => true; (Some(a),Some(b)) => same(a,b); _ => false`.
   Its `changed_at()` answers `accepted_changed_at()`; the lifted `same` keeps it
   aligned with the transition status.

3. **Fold** `EagerDerived[Bool]` — **carries a `Bool` accept-signal, not the
   snapshot.** `Bool : Eq`, so the fold stays on the existing
   `scope.eager_derived` (no eager-tier addition needed). The signal is FLIPPED
   **iff** the transition status is `AcceptedChanged`; on `AcceptedUnchanged` /
   `RetainedDueToError` / `NoAccept` / a `Disposed` read it is unchanged → the
   fold backdates → its downstream `accepted_cell` is not invalidated. Only the
   signal's *change* matters (its value is discarded by `accepted_cell`), so a
   toggle suffices — no counter, hence no overflow. The fold still RUNS every
   committed revision (eager/reachability-driven), so `accepted_slot` and
   `last_status` advance even with no accepted read between a transient success
   and a later error (spec row ~line 410). The snapshot is built by the
   `snapshot()`/`accepted()` accessors from the `Ref` slots, as today — the fold
   never needs to carry a non-`Eq` value.

### Invariant

`accepted_changed_at()` advances **iff** the accepted value changed under `same`
(BackdateEq tier). Mechanism: status `AcceptedChanged` ⟺ signal flip ⟺ `accepted_cell`
re-run ⟺ its `changed_at` advances (its lifted-`same` backdate confirms the value
genuinely differs).

## Public surface added (this PR)

Mirror the existing constructor family, `V : BackdateEq, E : Eq`:

- `AcceptedDerived::accepted_memo(rt, compute, label?)` — owns its candidate.
- `Scope::accepted_memo(self, compute, label?)` — scope-owned convenience.

Naming follows `Memo::new_memo`. A `BackdateEq` companion of `from_candidate`
is **not** shipped: there is no public non-`Eq` `Derived` candidate constructor
to build its argument, so it would be dead/untestable surface (deferred until a
`from_candidate` use case + such a constructor appear). The default `Eq`
constructors (`AcceptedDerived::AcceptedDerived`, `from_candidate`,
`Scope::accepted_derived`) are **unchanged**, except `from_candidate`'s unused
`E : Eq` bound was relaxed to `E`.

## Step order (TDD; gate every code step with `NEW_MOON_MOD=0 moon check` then `moon test`)

1. Feature branch off `main` (never commit to `main`).
2. **Refactor (Eq tier, no behavior change):** thread a `same : (V,V) -> Bool`
   predicate through `accepted_transition` and `assemble`; the existing
   `Eq`-tier constructors pass `(a,b) => a == b`. The candidate/accepted_cell
   stay on the current `Derived::fallible`/`scope.derived` for the Eq tier.
   Gate: full existing suite stays green (pure refactor).
3. **Test-first (black-box), `incr/tests/accepted_derived_test.mbt`:** add a
   `Stamped`-style non-`Eq` fixture (`priv struct` with a `revision` field;
   `impl HasChangedAt`; `impl BackdateEq`; `Revision::initial().next()...` for
   stamps). Add failing tests for the rows below. Red gate.
4. **Test-first (white-box), `incr/cells/accepted_derived_wbtest.mbt`:** fold-key
   + wake-count probes (below). Red gate.
5. **Implement the internal `_create`-comparator path** for candidate +
   accepted_cell (a small private helper in `accepted_derived.mbt`, or
   `Derived::with_backdate(rt, compute, label?, eq)` in `target_facade.mbt` if it
   reads cleaner). Register cells via `scope.cells.push`/`add_cell_ids`.
6. **Implement the `Bool` accept-signal fold** + `accepted_memo` /
   `Scope::accepted_memo` constructors (pass `same = backdate_equal`). Green gate.
7. `moon info && moon fmt`; inspect `git diff -- *.mbti` (only intended additions).
8. **Docs closure:** flip spec open-Q #3 (BackdateEq delivered, no-backdate
   deferred); add the constructors to `docs/api-reference.mbt.md` AcceptedDerived
   section; add a `CHANGELOG.md [Unreleased]` bullet.

## Test inventory (write these red first)

Black-box (`accepted_derived_test.mbt`), `Stamped`-style non-`Eq` `V`:
- first `Ok` → `Some(v)`, `AcceptedChanged` (rows 107/110).
- two successes with the SAME revision but different payload → `AcceptedUnchanged`,
  accepted value retained, `accepted_changed_at()` does NOT advance (row 109).
- success with a NEW revision → `AcceptedChanged`, accepted replaced, `accepted_changed_at()` advances (row 110).
- `Err` after a success → `RetainedDueToError`, accepted retained, current = `Err` (row 108).
- repeated equal `Err` → current channel backdates (no accepted-watcher wake; `E:Eq` arm) (row 407).
- transient success then later `Err` with NO accepted read in between → `accepted` still `Some(v)` (row 410).
- `Scope::accepted_memo` matches the top-level constructor on the same rows.

Wake-count behavior (covered black-box by the in-graph accepted-consumer test
rather than a separate wbtest):
- accepted-only consumer wake-count: does NOT wake on current-only `Err` churn; DOES wake on a real (new-revision) accepted change.
- fold runs (slot advances) every committed revision even with no accepted read (transient-success probe).
- the accept-signal flips iff `AcceptedChanged` (drives `accepted_changed_at`).

## What could make this wrong (risk list)

1. `same` diverging between transition status and `accepted_cell` backdating —
   guard by threading ONE predicate from ONE source into both.
2. A too-stable fold value (e.g. `Unit`) suppressing `accepted_cell` invalidation
   after a real accept — the accept-signal must flip on `AcceptedChanged`.
3. Accidentally routing the candidate through `Derived::fallible` and
   re-imposing `V : Eq`.
4. Wrong `Option`-lifted comparator on `accepted_cell` breaking
   `accepted_changed_at()` (e.g. `(None,None) => false`).
5. Forgetting `scope.cells.push(inner.id())` for the hand-built cells → broken
   lifecycle / GC reachability / disposal (the gc anchor chain
   `accepted_cell → fold → candidate` must stay rooted).
6. `moon info` widening a trait bound on an existing symbol — check `git diff *.mbti`.
