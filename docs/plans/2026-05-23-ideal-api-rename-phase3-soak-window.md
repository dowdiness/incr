# Phase 3 (soak window) — Read Vocabulary Deprecation on Compatibility Handles

**Date:** 2026-05-23
**Status:** Draft design spec (pre-implementation)
**Parent plan:** [2026-05-21-ideal-api-rename-migration.md](2026-05-21-ideal-api-rename-migration.md)
**ADR:** [2026-05-21-public-api-ideal-naming.md](../decisions/2026-05-21-public-api-ideal-naming.md)

## Context

The parent migration plan describes Phase 3 as a single "semantic read flip" —
making `Memo::get` return `Result[T, CycleError]` and removing the bare-T
`get()`. After brainstorming on 2026-05-23, that monolithic Phase 3 was split
into two PRs:

- **Phase 3a (this plan):** rename, don't flip. Add target-vocabulary read
  methods on the compatibility handles `Memo`, `HybridMemo`, `MemoMap`, mark
  the old names as deprecated, migrate in-tree callers, publish a CHANGELOG
  migration guide. Zero behavior change.
- **Phase 3b (future PR):** the actual return-type flip on `Memo::get` /
  `MemoMap::get`. Shipped as a tagged breaking release. Out of scope here.

Phase 3a is the *soak window* preparation. Downstream submodule consumers
(loom, canopy) migrate at their own pace against the additive surface this PR
publishes. Their migration is explicitly **not** coordinated in this PR.

## Theoretical framing

The `get` vs `read` distinction is the API surface for incr's **Monadic
task abstraction** in the "Build Systems à la Carte" sense (Mokhov, Mitchell,
Peyton Jones 2020): compute functions discover dependencies dynamically by
calling other reads, and they can branch on read values, so the dependency
graph cannot be predicted ahead of time. `get` is the in-graph read that
participates in this Monadic discovery — it requires an active tracking
frame and records a dependency. `read` is the permissive read that works in
or out of graph; it records a dependency only when a tracking frame happens
to be active.

`Result[T, CycleError]` as the return type of both shapes is a forced
consequence of the Monadic abstraction plus incr's cycle support. A Monadic
scheduler can discover a cycle only at runtime — and incr, unlike the
build-systems literature which assumes acyclic task graphs, chooses to
report cycles as recoverable errors rather than aborts. This makes
`Result[T, CycleError]` the canonical read return type. Phase 3b's flip on
`Memo::get` is therefore not a naming preference; it aligns the
compatibility surface with the only return type that correctly describes a
Monadic, cycle-tolerant read.

## Goals

1. Every existing compatibility handle (`Memo`, `HybridMemo`, `MemoMap`) gains
   the target-vocabulary read methods (`get_or_abort`, `read`, `read_or_abort`,
   `read_or`, `read_or_else`) on the same receiver — no facade-only forwarding.
2. Every existing legacy read name on those handles gets a `#deprecated`
   annotation pointing at its new spelling.
3. The two names whose semantics will shift in Phase 3b — `Memo::get` and
   `MemoMap::get` — get a *special* deprecation message explicitly naming the
   future return type, so callers cannot accidentally adopt them thinking they
   are stable.
4. In-tree callers (~60–80 sites across `cells/`, `tests/`, doc examples)
   migrate to the new spellings in the same PR.
5. CHANGELOG.md publishes a migration guide downstream consumers can follow.

## Non-goals

- No return-type changes on any method. `Memo::get` still returns `T`.
- No new behavior. Every new public method delegates to existing code paths
  (some currently package-private and used by the `Derived` / `ReachableDerived`
  / `DerivedMap` facades).
- No deletion of legacy method names. They remain compiling, with deprecation
  warnings.
- No coordinated submodule migration. loom and canopy migrate on their own
  schedule against the additive surface.
- No new fallback methods (`read_or` / `read_or_else`) on `HybridMemo` — there
  is no compatibility caller pressure since `HybridMemo` has never had a
  `get_or` / `get_or_else` public surface. Adding them would be net-new API
  smuggled into a soak window.
- `Signal::get` is unchanged. Inputs cannot cycle; the read-vocabulary flip
  applies only to derived target types.

## Architecture

### Additive surface — `Memo`

| New canonical name | Body delegates to | Semantics |
|---|---|---|
| `Memo::get_or_abort(self) -> T` | existing `Memo::get` body (verbatim move) | strict aborting (in-graph) |
| `Memo::read(self) -> Result[T, CycleError]` | existing `Memo::get_result` body | permissive `Result` |
| `Memo::read_or_abort(self) -> T` | `match self.read() { Ok(v) => v, Err(e) => abort(e.format_path()) }` | permissive aborting |
| `Memo::read_or(self, fb) -> T` | existing `Memo::get_or` body | permissive, fallback on cycle |
| `Memo::read_or_else(self, f) -> T` | existing `Memo::get_or_else` body | permissive, fallback fn on cycle |

`Memo::read_or_abort` is the only one not present today even as
package-private; it's a 4-line wrapper around `Memo::read`.

### Additive surface — `HybridMemo`

`HybridMemo`'s entire current public read surface is `HybridMemo::get(self) -> T`.
Internally it already has `get_strict_result`, `read_result`, and
`read_permissive` as package-private methods (used by the `ReachableDerived`
facade). The additions promote those to public:

| New canonical name | Body delegates to | Semantics |
|---|---|---|
| `HybridMemo::get_or_abort(self) -> T` | existing `HybridMemo::get` body | strict aborting |
| `HybridMemo::read(self) -> Result[T, CycleError]` | existing pkg-private `read_result` | permissive `Result` (incl. event-broadcast drain) |
| `HybridMemo::read_or_abort(self) -> T` | `match self.read() { Ok(v) => v, Err(e) => abort(e.format_path()) }` | permissive aborting (drain inherited from `self.read()`) |

⚠ **Do NOT delegate `HybridMemo::read_or_abort` to the existing pkg-private
`HybridMemo::read_permissive`** ([cells/hybrid_memo.mbt:179](../../cells/hybrid_memo.mbt)).
`read_permissive` calls `read_result_inner` directly, skipping the trailing
event-broadcast drain that `read_result` performs ([cells/hybrid_memo.mbt:109-122](../../cells/hybrid_memo.mbt)).
The new `read_or_abort` must go through `read` so the drain runs. The existing
`read_permissive` is the latent drain-skip pattern that the `ReachableDerived`
facade already lives with — we are intentionally not propagating it to the
public `HybridMemo` surface. A follow-up could fix `read_permissive` or
delete it; out of scope here.

No `HybridMemo::read_or` / `HybridMemo::read_or_else`. See non-goals.

### Additive surface — `MemoMap`

| New canonical name | Body delegates to | Semantics |
|---|---|---|
| `MemoMap::get_or_abort(self, k) -> V` | existing `MemoMap::get_tracked` body | strict aborting |
| `MemoMap::read(self, k) -> Result[V, CycleError]` | existing `MemoMap::get_result` body | permissive `Result` |
| `MemoMap::read_or_abort(self, k) -> V` | existing `MemoMap::get` body (incl. event-broadcast drain) | permissive aborting |
| `MemoMap::read_or(self, k, fb) -> V` | existing `MemoMap::get_or` body | permissive fallback |
| `MemoMap::read_or_else(self, k, f) -> V` | existing `MemoMap::get_or_else` body | permissive fallback fn |
| `MemoMap::has_cached(self, k) -> Bool` | existing `MemoMap::contains` body | cache predicate |
| `MemoMap::cache_len(self) -> Int` | existing `MemoMap::length` body | cache size |
| `MemoMap::sweep_cache(self) -> Int` | existing `MemoMap::sweep` body | sweep disposed |
| `MemoMap::clear_cache(self) -> Unit` | existing `MemoMap::clear` body | clear all |

### Deprecation annotations

Two flavors:

**Flavor A — pure rename** (no future semantic shift). For: `Memo::get_result`,
`Memo::get_or`, `Memo::get_or_else`, `HybridMemo::get`,
`MemoMap::get_tracked`, `MemoMap::get_result`, `MemoMap::get_or`,
`MemoMap::get_or_else`, `MemoMap::contains`, `MemoMap::length`,
`MemoMap::sweep`, `MemoMap::clear`.

Form (`#alias` lives on the **new canonical** method, with the **old name** as
the alias target, per spike precedent at
[spikes/ideal_api_rename_phase0/provider/probes.mbt:13](../../spikes/ideal_api_rename_phase0/provider/probes.mbt)
+ [spikes/ideal_api_rename_phase0/consumer/probes.mbt:42](../../spikes/ideal_api_rename_phase0/consumer/probes.mbt)):

```moonbit
#alias(get_result, deprecated="Memo::get_result is deprecated; use Memo::read")
pub fn[T] Memo::read(self : Memo[T]) -> Result[T, CycleError] {
  // body — delegates to existing pkg-private read_result
  self.read_result()
}
```

The deprecated old spelling `Memo::get_result` is then automatically generated
as an alias by the `#alias` mechanism. There is no separate definition of the
old name; you do not write a forwarder body for it.

**Flavor B — semantic-shift names.** For: `Memo::get`, `MemoMap::get`. These
spellings will be reused in Phase 3b with a different return type. The
deprecation message must explicitly name the future return type so a caller
reading it cannot conclude "switch to read_or_abort, problem solved" without
also understanding the spelling is recycled:

```moonbit
#deprecated("Memo::get returns T today but will return Result[T, CycleError] in the next breaking release. Migrate to Memo::get_or_abort for the current aborting semantics, or to Memo::read for permissive Result reads. See CHANGELOG.md.")
pub fn[T] Memo::get(self : Memo[T]) -> T {
  match self.get_strict_result() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}
```

`MemoMap::get` is annotated identically with parallel message.

**Annotation form — confirmed.** Codex review (2026-05-23) verified:

- Bare `#deprecated("msg")` compiles on public methods today
  ([cells/observer.mbt:223](../../cells/observer.mbt)).
- Warning *emission* on call sites is verified for a public *function* via
  `gc_tracked` ([traits.mbt:417](../../traits.mbt) called from
  [tests/tracked_struct_test.mbt:174](../../tests/tracked_struct_test.mbt)).
- Warning emission on a public *method* via bare `#deprecated` cannot be
  verified from current repo state because every existing call site suppresses
  with `#warnings("-deprecated")` (e.g.
  [tests/runtime_read_compat_test.mbt:2](../../tests/runtime_read_compat_test.mbt)).

**Pre-implementation spike (required, ~10 minutes):** before applying the
deprecation pass in commit 3, add a temporary throwaway method on `Memo` with
bare `#deprecated("test")`, call it from a fresh test file *without* a
`#warnings("-deprecated")` suppression, run `rtk moon check`, confirm the
warning is emitted. Then delete the throwaway. If the warning is NOT emitted,
the fallback is to redefine `Memo::get` as `#alias(get_or_abort)` with a
deprecation message in the alias attribute — this is misleading because
`get_or_abort` is not a synonym for the future shifted `get`, but it is the
only currently-available channel for a warning. We pay that cost if and only
if the spike confirms bare `#deprecated` doesn't emit warnings on methods.

### In-tree caller migration

Every internal `.get()` / `.get_result()` / `.get_or()` / etc. call site
migrates to the new spelling. Inventory (approximate):

| File | Pattern | Approx count |
|---|---|---|
| `cells/custom_eq_test.mbt` | `memo.get()` (bare-T) | 5 |
| `cells/cycle_test.mbt` | `.get_result()` | ~15 |
| `cells/cycle_path_test.mbt` | `.get_result()` | 5 |
| `cells/verify_path_test.mbt` / `verify_wbtest.mbt` | `.get_result()` | 4 |
| `cells/introspection.mbt` doc comment | `memo.get()` example | 1 docstring |
| `cells/memo_map.mbt` doc comment | `by_id.get(1)` example | 1 docstring |
| `tests/tracked_struct_test.mbt` | `.get_result()` | 1 |
| `types/cycle_error.mbt` doc | `memo.get_result()` example | 1 docstring |
| `cells/memo_test.mbt` / `memo_map_test.mbt` / `memo_raise_wbtest.mbt` / `subscriber_*.mbt` etc. | various | ~30+ |

| `tests/integration_test.mbt` | various Memo/MemoMap reads | several (Codex gap, ≥2) |
| `cells/push_reachable_wbtest.mbt` | `.get()` on derived | 1+ (Codex gap) |
| `cells/hybrid_wbtest.mbt` | `.get()` on HybridMemo | 1+ (Codex gap) |

Estimated 60–80 sites total (revised after Codex caller-inventory pass — three
additional files identified that the initial sweep missed). All mechanical
sed-safe renames.

**Docstring migration** — `///` doc examples migrate too (e.g.,
`cells/introspection.mbt:59`, `cells/memo_map.mbt:18`, `types/cycle_error.mbt:22`).
The whole point of the soak window is that downstream readers learn the new
vocabulary from current docs.

**Out-of-scope for caller migration:**

- `docs/target_api_examples.mbt.md` and `docs/api_reference_examples.mbt.md`
  — already on target facade names from Phase 2 PR #77.
- The `Derived` / `ReachableDerived` / `DerivedMap` facade bodies themselves
  — they already use the package-private wired names directly.

## Verification

### `.mbti` diff (the gate)

Expected `git diff cells/pkg.generated.mbti` is purely additive (~17
`pub fn` lines, zero `-` lines):

```
+ pub fn[T] Memo::get_or_abort(Self[T]) -> T
+ pub fn[T] Memo::read(Self[T]) -> Result[T, @types.CycleError]
+ pub fn[T] Memo::read_or_abort(Self[T]) -> T
+ pub fn[T] Memo::read_or(Self[T], T) -> T
+ pub fn[T] Memo::read_or_else(Self[T], (@types.CycleError) -> T) -> T
+ pub fn[T : Eq] HybridMemo::get_or_abort(Self[T]) -> T
+ pub fn[T : Eq] HybridMemo::read(Self[T]) -> Result[T, @types.CycleError]
+ pub fn[T : Eq] HybridMemo::read_or_abort(Self[T]) -> T
+ pub fn[K : Hash + Eq, V : Eq] MemoMap::get_or_abort(Self[K, V], K) -> V
+ pub fn[K : Hash + Eq, V : Eq] MemoMap::read(Self[K, V], K) -> Result[V, @types.CycleError]
+ pub fn[K : Hash + Eq, V : Eq] MemoMap::read_or_abort(Self[K, V], K) -> V
+ pub fn[K : Hash + Eq, V : Eq] MemoMap::read_or(Self[K, V], K, V) -> V
+ pub fn[K : Hash + Eq, V : Eq] MemoMap::read_or_else(Self[K, V], K, (@types.CycleError) -> V) -> V
+ pub fn[K : Hash + Eq, V] MemoMap::has_cached(Self[K, V], K) -> Bool
+ pub fn[K, V] MemoMap::cache_len(Self[K, V]) -> Int
+ pub fn[K : Hash + Eq, V] MemoMap::sweep_cache(Self[K, V]) -> Int
+ pub fn[K, V] MemoMap::clear_cache(Self[K, V]) -> Unit
```

`#alias` and `#deprecated` attributes do not render in `.mbti`, so existing
lines are byte-identical to current `main`.

The top-level `pkg.generated.mbti` is unchanged. Methods auto-surface via the
`pub using @cells { type Memo }` re-export.

### CI guard

Add `scripts/check-mbti-additive.sh` (~20 lines) — invoked from CI — that
asserts `git diff origin/main -- cells/pkg.generated.mbti` contains zero
`^-` deletion lines. This guard is deleted in the Phase 3b PR.

### Commands (run in order)

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/loom/incr
moon check                                      # type-check
moon info && moon fmt                           # regenerate .mbti + format
git diff cells/pkg.generated.mbti               # must match expected diff above
git diff pkg.generated.mbti                     # must be empty
moon test                                       # full suite passes — migrated callers exercise new names
moon check docs/target_api_examples.mbt.md
moon check docs/api_reference_examples.mbt.md
moon test docs/target_api_examples.mbt.md
moon test docs/api_reference_examples.mbt.md
moon bench --release                            # smoke — no perf regression
bash scripts/check-mbti-additive.sh             # new CI guard
```

### Regression test — rename equivalence

Add `cells/memo_rename_test.mbt` with one trivial test per rename pair (~14
tests), each asserting the new name returns identical observable behavior to
the old name on a representative graph. Locks in equivalence before Phase 3b
can drift either side.

Example pattern:

```moonbit
test "rename equivalence: Memo::read == Memo::get_result" {
  let rt = Runtime()
  let s = Signal(rt, 10)
  let m = Memo(rt, () => s.get() * 2)
  @incr.observed(rt, fn() {
    assert_eq(m.read(), m.get_result())
  })
}
```

## CHANGELOG entry

Append to `CHANGELOG.md`:

```markdown
## Unreleased

### Read vocabulary deprecation (soak window)

The read methods on `Memo`, `HybridMemo`, and `MemoMap` are being renamed to
align with the target facade vocabulary (`Derived`, `ReachableDerived`,
`DerivedMap`). The next breaking release will additionally change `Memo::get`
and `MemoMap::get`'s return type to `Result[T, CycleError]` matching the
target facades. **Migrate during this soak window** to avoid silent semantic
shifts later.

#### Rename table

| Old name | New name | Migration note |
|---|---|---|
| `Memo::get(self) -> T` | `Memo::get_or_abort(self) -> T` | ⚠ `Memo::get` will return `Result` in the next breaking release |
| `Memo::get_result(self)` | `Memo::read(self)` | Pure rename |
| `Memo::get_or(self, fb)` | `Memo::read_or(self, fb)` | Pure rename |
| `Memo::get_or_else(self, f)` | `Memo::read_or_else(self, f)` | Pure rename |
| `HybridMemo::get(self) -> T` | `HybridMemo::get_or_abort(self) -> T` | Pure rename |
| `MemoMap::get(self, k) -> V` | `MemoMap::read_or_abort(self, k) -> V` | ⚠ `MemoMap::get` will return `Result` in the next breaking release |
| `MemoMap::get_tracked(self, k)` | `MemoMap::get_or_abort(self, k)` | Pure rename |
| `MemoMap::get_result(self, k)` | `MemoMap::read(self, k)` | Pure rename |
| `MemoMap::get_or(self, k, fb)` | `MemoMap::read_or(self, k, fb)` | Pure rename |
| `MemoMap::get_or_else(self, k, f)` | `MemoMap::read_or_else(self, k, f)` | Pure rename |
| `MemoMap::contains(self, k)` | `MemoMap::has_cached(self, k)` | Pure rename |
| `MemoMap::length(self)` | `MemoMap::cache_len(self)` | Pure rename |
| `MemoMap::sweep(self)` | `MemoMap::sweep_cache(self)` | Pure rename |
| `MemoMap::clear(self)` | `MemoMap::clear_cache(self)` | Pure rename |

#### What is NOT changing in this release

- Behavior: every new name delegates to the same internal code path as the old name.
- Return types: `Memo::get` and `MemoMap::get` still return bare values today.
- `Signal::get` (target name `Input::get`) is unchanged. Inputs cannot cycle.
- `Runtime::read*` is unchanged; already marked legacy compatibility in PR
  #70. The deeper rationale: tracking is a **handle concern**, not a
  **runtime concern**. `Runtime::read(memo)` confused those layers by
  letting the runtime perform a read on behalf of a handle, which prevents
  the runtime from being self-tracking in any disciplined way. Handle-owned
  reads (`Memo::get`, `Memo::read`, etc.) make the participation in Monadic
  dep tracking visible at the call site, which is the right layer for that
  decision.

#### Future breaking release

A subsequent release will change `Memo::get` from `T` to `Result[T, CycleError]`
(strict, in-graph) and `MemoMap::get` from `V` to `Result[V, CycleError]`.
These changes will land in a single PR clearly tagged as breaking, with a
major-version bump.

See [ADR 2026-05-21: Ideal Public API Naming](docs/decisions/2026-05-21-public-api-ideal-naming.md)
and [the rename plan](docs/plans/2026-05-21-ideal-api-rename-migration.md)
§"Phase 3" for full context.
```

## PR sequencing

Single PR, three commits, forced ordering:

1. **`feat(incr): add target-vocabulary read methods on Memo/HybridMemo/MemoMap`**
   Adds the 17 new `pub fn` lines. No caller changes. No deprecations.
   `.mbti` grows by 17 lines.

2. **`refactor(incr): migrate in-tree callers to target-vocabulary read methods`**
   Mechanical sed-style rename across the ~60–80 call sites plus docstrings.
   `cells/memo_rename_test.mbt` added here.

3. **`feat(incr): mark old read names as #deprecated, add CHANGELOG soak-window guide`**
   Adds `#deprecated` / `#alias` annotations. Appends CHANGELOG.md entry.
   Adds `scripts/check-mbti-additive.sh`.

Ordering is forced: commit 2 cannot precede commit 1 (callers reference names
that don't exist). Commit 3 cannot precede commit 2 (deprecating names while
in-tree code still uses them turns `moon check` into deprecation-warning soup,
masking real warnings).

## Codex design validation gate

Before any implementation edit, send this spec to Codex via `mcp__codex__codex`
asking specifically:

- **(a) Semantic equivalence.** Does every rename in the table preserve
  observable behavior? Specifically: does `MemoMap::read(k)` returning
  `self.get_result(k)`'s output (which calls `read_result` permissively) match
  what consumers of `MemoMap::get_result` expect? Are there subtle differences
  between `read_permissive` (HybridMemo) and `match read_result { Ok => v,
  Err => abort }` worth flagging?
- **(b) Annotation form validity.** Is bare `#deprecated("...")` (without
  `#alias`) a valid MoonBit 0.9.2 attribute on a public method, and does it
  emit a warning at call sites? If not, what is the canonical fallback for
  "deprecate but no canonical new spelling on the same receiver"?
- **(c) Inventory gaps.** Are there call sites in `tests/`, `spikes/`,
  `docs/*.mbt.md`, or under `_build/` that the inventory missed?
- **(d) Naming choice on cache methods.** Are `has_cached` / `cache_len` /
  `sweep_cache` / `clear_cache` the right target spellings, or should they be
  defended differently (e.g., target-facade-only with no `MemoMap` synonym)?
  The parent plan's "Wrapper/facade forwarding targets" table lists these as
  facade methods. Adding them on `MemoMap` itself is a *promotion* of the
  facade vocabulary to the compatibility handle, which the parent plan does
  not explicitly authorize.

### Event-broadcast drain placement (Memo / MemoMap)

Two drain placements in current code, with different correction patterns
post-rename:

**Memo path — no re-plumbing needed.** The drain already lives in pkg-private
`Memo::read_result` ([cells/memo.mbt:217-232](../../cells/memo.mbt)); the
public `Memo::get_result` ([cells/memo.mbt:200](../../cells/memo.mbt)) is a
pure 1-line forward to `read_result`. After the rename, `Memo::read` takes
over the same role — forwards to `read_result`. The deprecated
`Memo::get_result` becomes an `#alias` of `Memo::read` (no body, generated by
the alias mechanism). Drain runs exactly once per read, identically to today.

**MemoMap path — drain moves to new canonical.** The drain is currently inline
in the public `MemoMap::get` body ([cells/memo_map.mbt:57-63](../../cells/memo_map.mbt)),
not in a pkg-private helper. After the rename:
- `MemoMap::read_or_abort(self, k)` body owns the drain (lifts the current
  `MemoMap::get` body verbatim).
- `MemoMap::get(self, k)` becomes a 1-line forwarder `self.read_or_abort(k)`
  (no drain) — but is `#deprecated`-annotated (Flavor B) rather than
  `#alias`-generated, because `MemoMap::get` is a semantic-shift name (Flavor
  B, see below).
- Drain runs exactly once per read, identically to today.

In short: the Memo side is mechanically a no-op (alias generation handles it);
the MemoMap side does need an explicit body move because Flavor B
(`MemoMap::get`) keeps a hand-written deprecated body.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| `#deprecated` attribute syntax wrong → no warnings emitted | Codex gate (b); if invalid, fallback to `#alias` form with text-only future-shift warning |
| In-tree caller migration misses a site → deprecation warnings spam test output | Run `moon test` after commit 2; grep `deprecated` in output; fix |
| `.mbti` diff has unexpected `-` lines from `moon info` regeneration quirk | `scripts/check-mbti-additive.sh` gate; manual `git diff` review before each commit |
| Downstream consumers (loom, canopy) read the CHANGELOG too late and adopt deprecated names anyway | Out of scope for this PR; their migration is on their schedule. The deprecation warnings at compile time are the mitigation |
| `HybridMemo::read_or_abort` semantics surprise — promotes pkg-private `read_permissive` which never checked tracking context | Documented in method docstring; same semantic as `ReachableDerived::read_or_abort` which downstream already depends on |
| ~~Naming `has_cached` / `cache_len` etc. on `MemoMap` adds compatibility surface the parent plan didn't authorize~~ | **Resolved (Codex 2026-05-23):** parent plan §line 94 explicitly authorizes these as same-receiver alias candidates; ADR §line 87 wants cache names to say cache. Risk dismissed. |

## Out of scope (explicit non-goals, recap)

- The return-type flip on `Memo::get` / `MemoMap::get` (Phase 3b).
- Downstream submodule (loom, canopy) caller migration.
- Facade type changes — `Derived`, `ReachableDerived`, `DerivedMap` are not
  touched.
- `Runtime::read*` is already legacy-marked in PR #70; not touched here.
- `Signal::get` — Inputs do not have the read-vocabulary problem.
- New `HybridMemo::read_or` / `read_or_else` — net-new surface, deferred.

## Codex review (2026-05-23) — resolved questions

Run via `mcp__codex__codex` after spec draft. Verdict: NEEDS REVISION; all
findings folded into the revised spec above.

| # | Finding | Disposition |
|---|---|---|
| 1 | `#alias` direction was backwards in Flavor A example | Fixed — annotation now lives on new canonical method, alias target is old name |
| 2 | `HybridMemo::read_or_abort` must NOT delegate to `read_permissive` (skips drain) | Fixed — body now `match self.read() { ... }` |
| 3 | Bare `#deprecated` valid; warning emission on methods cannot be verified from repo state | Pre-implementation spike added before commit 3 |
| 4 | Cache renames ARE authorized (parent plan line 94, ADR line 87) | Risk row updated, no longer flagged |
| 5 | Three additional caller files missed: `tests/integration_test.mbt`, `cells/push_reachable_wbtest.mbt`, `cells/hybrid_wbtest.mbt` | Added to inventory |
| 6 | `Memo::get_result` doesn't contain drain inline — drain is in pkg-private `read_result` already | Memo path correction noted; no re-plumbing needed. MemoMap path retains drain move |

Open question still requiring confirmation during implementation:

- **`memo_rename_test.mbt` scaffold.** Some renames apply to in-graph (strict)
  reads, others to outside-graph reads. The test file should use
  `@incr.observed` for outside-graph cases and a wrapping `Memo`/observer for
  in-graph cases. Decide per-test during implementation.
