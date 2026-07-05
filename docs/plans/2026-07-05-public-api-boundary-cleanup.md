# Public API Boundary Cleanup + `Expr[T]` Track

**Status:** Active

**Date:** 2026-07-05

**Origin:** Full public-API design review of the v0.13.0 surface (session
2026-07-05). Verdict: *Good core, weak boundary* — the core API
(`Runtime` / `Input` / `Derived` / `Scope` / `Watch`, `Result`-based read
channel) stays as is; the work below cleans the boundary before the first
external consumer arrives, then adds the `Expr[T]` formula layer as the
follow-on track.

**Semver context:** minor-as-breaking policy while the library has no
external users (see CHANGELOG v0.13.0 preamble). Breaking changes are
bundled into a single release (0.14.0) to pay the downstream re-pin chain
(incr publish → loom PR → canopy PR) once.

## Ratified decisions (2026-07-05, user-decided)

| Gate | Decision |
|------|----------|
| G1 — `Runtime::input` | **Keep.** No `Runtime::derived` counterpart is added either; the asymmetry is accepted. Canonical creation layers: direct constructors / `Scope::*` / `create_*` (Ctx) / `rt.input`. |
| G2 — `Scope::watch(derived)` | **Add** (Phase 0). Folds watch creation + scope registration + priming read into one call to close the delayed-GC-abort trap. |
| G3 — multi-arity `_no_backdate` variants | **Keep until `Expr[T]` lands.** `Derived::map2_no_backdate` / `map3_no_backdate` / `Input::derived2_no_backdate` / `derived3_no_backdate` stay; revisit (deprecate/delete) when Track E ships E2. `map`/`map2`/`map3` (Eq versions) are positioned as the interim algebra sugar until `Expr[T]`. |

## Phase 0 — non-breaking preparation (one PR)

1. **Deprecated aliases.** Add `#deprecated` to `Input::new`, `Runtime::new`,
   `Relation::new`; the `Type::Type` constructor forms are canonical.
   Do NOT touch `Scope::new` / `Effect::new` / `Accumulator::new` here —
   their `Type::Type` replacements do not exist yet (Phase 2 handles
   `Effect` / `Accumulator`; `Scope::new` stays, see Phase 2 rationale).
2. **`Scope::watch`.** New method: creates `derived.watch()`, registers it
   with the scope, performs one priming read, then returns the watch.
   Invariant: on return the watch is a GC root AND upstream
   `gc_dependencies` are recorded (safe against a `Runtime::gc()` that runs
   before the first consumer read).
   Tests first (blackbox, `incr/tests/`): attachment built via
   `Scope::watch` survives `rt.gc()` before first consumer read; contrast
   test documents the bare-watch-without-priming failure mode.
3. **Docs canonicalization.** All examples in getting-started / concepts /
   cookbook / api-reference / target_api_examples use canonical creation
   forms; zero occurrences of deprecated forms. Add a one-table "choosing
   a backdate variant" guide to api-reference
   (Eq → default / non-Eq → `_no_backdate` / `BackdateEq` →
   `with_backdate` / `Result` → `fallible`).
4. **Verification.** `moon check && moon test` (workspace); `moon info`
   then inspect `git diff '*.mbti'` — the diff must be exactly
   "deprecated attributes + `Scope::watch`". Rewrite in-workspace callers
   until deprecation warnings are zero.

## Phase 1 — types package cleanup (breaking, one PR; do not publish until Phase 2 merges)

1. **Delete ghost types.** Remove `MemoId[T]`, `ReactiveId[T]`,
   `FunctionalRelationId[K, V]` from `@incr/types` (leftovers of handles
   removed in v0.12/v0.13). Precondition: `moon ide find-references`
   confirms zero references each.
2. **Trim root re-exports.** Drop `InputId` / `RelationId` from the root
   facade (`incr.mbt`); no public root API consumes them. Keep them in
   `types` only if kernel/cells reference them (find-references); delete
   otherwise.
3. **Close invariant-bearing types.**
   - `InternTable[T]`: `pub(all)` → `pub` (fields private). Existing
     methods (`new`/`intern`/`get`/`len`) already cover the public
     surface.
   - `Revision`: `pub(all)` → `pub`, add a `value()` accessor if needed;
     kernel/cells construction goes through `Revision::initial`/`next` or
     a named constructor.
   - `InternId`: same treatment (`index()` accessor).
   - `CycleError::new`: attempt to remove from the public surface (tests
     move to whitebox). If MoonBit visibility cannot keep cells-side
     construction while hiding it externally, record the limitation and
     keep it with a library-internal doc comment.
   - **Do not touch** `CellId` / `RuntimeId` / `ListenerId` /
     `AccumulatorId`: their `pub(all)` is forced by cross-package
     construction; closing them is a separate named-constructor track,
     out of scope here.
4. **Tests & interface check.** Pin the surviving contracts with blackbox
   tests before each removal (InternTable intern→get round-trip; Revision
   monotonicity). `moon info` → `git diff '*.mbti'` must show shrinkage
   only — stop on any other diff (e.g. trait-bound changes). Run
   `scripts/check-engine-isolation.sh` and
   `scripts/check-workspace-boundaries.sh` (with selftest).

## Phase 2 — error-channel and constructor consistency (breaking, one PR, same release as Phase 1)

1. **`Input::get_result` / `InputField::get_result`** →
   `Result[T, ReadError]` (currently `CycleError`), aligning with the
   Honest Read-Error Ownership spec (2026-05-28). Failing tests first.
2. **`Accumulator` constructor.** Add positional
   `Accumulator::Accumulator(Runtime, label?)`; remove
   `Accumulator::new(rt~)`. Update `create_accumulator` /
   `Scope::accumulator` internals. Also add `Effect::Effect(Runtime, f)`
   and deprecate `Effect::new`. `Scope::new` is deliberately kept: it is
   the pervasive documented form and the rename value does not cover the
   churn — record this rationale in the CHANGELOG.
3. **`DerivedMap` bound.** Add `V : Eq` to `DerivedMap::DerivedMap`,
   `Scope::derived_map`, `create_derived_map` — closes the
   constructible-but-unreadable gap. Precondition: confirm
   `DerivedMap::fallible` still typechecks (its reads need
   `Result[V, E] : Eq`); drop this item with a note if it does not.
4. **No `_no_backdate` deletions** (G3: kept until `Expr[T]`; the
   CHANGELOG notes the mapN family is interim algebra sugar pending
   Track E).
5. **Verification.** Same loop as Phase 1, plus update the literate docs
   (`*_examples.mbt.md`) in the same PR, plus one
   `moon bench --release` pass to confirm the `get_result` change does
   not move read-path numbers (two-of-two rule near any threshold).

## Release 0.14.0

1. CHANGELOG `[Unreleased]`: Removed / Changed / Added sections in the
   v0.13.0 style — every removed or changed name lists its replacement.
2. `bash scripts/bump-version.sh 0.14.0` (atomic version + member pins +
   boundary re-check). No manual pin edits.
3. `moon publish` only after explicit user approval (irreversible).
   Verify `moon.mod` repository URL first.
4. Downstream re-pin chain (same shape as #345): incr publish → loom pin
   bump PR (replace any deprecated forms there) → loom submodule pointer
   + canopy pin bump PR. CI fully green at each step before merging.
5. Update the developer `incr` skill: historical-mapping additions
   (`Input::new` etc.), `Scope::watch` as the recommended anchor form
   (the skill's "Watch is not registered through Scope" note is already
   stale against `Scope::add_watch`).

## Track E — `Expr[T]` Formula API (starts after 0.14.0 re-pin chain completes)

Motivation: an algebra-shaped construction API. The mapN family cannot
grow into one (each `mapN` is sugar over a dynamically-traced closure and
gives the engine no static structure; the backdate axis cannot be folded
into a flag because the `Eq` bound is part of the signature). `Expr[T]`
provides operator composition, a single-materialized-cell guarantee, and
a future lowering path to the package-private static/applicative fast
path.

Grounding documents:
[`Expr[T]` spec](../design/specs/2026-05-25-expr-formula-api.md)
(Proposed) and the
[static-derived ADR](../decisions/2026-06-01-static-derived-public-surface.md)
(reopen trigger #1 is exactly this track).

- **E1 — spec refresh (docs-only PR).** The spec predates the
  v0.12/v0.13 compat removal: drop the compat-handle sections; re-verify
  the source-lift bound table against the 0.14 `.mbti` (including the
  `DerivedMap` `V : Eq` change); add an operator-dispatch section
  (verify `impl[T : Add] Add for Expr[T]` compiles — unverified — and
  define the method-form fallback if not). Raise Proposed → Accepted via
  a new ADR in `docs/decisions/`.
- **E2 — v1 implementation (minor release, dynamic backend).** Per spec:
  `Expr[T]` in the cells package; `.expr()` lifts on all facades;
  `Expr::constant(rt, v, label?)` (no `Expr::pure` — same-runtime
  invariant); operator composition with immediate
  `assert_same_runtime`; `.derived(label?)` materialization allocating
  exactly one cell (pin with a blackbox test counting cells via runtime
  introspection). Backend is ordinary dynamic `Derived` — the static
  path is not touched. Tests first; literate `.mbt.md` examples and a
  getting-started pointer in the same PR.
  **On completion, revisit G3**: decide whether to deprecate the
  multi-arity `_no_backdate` variants (and optionally the mapN family)
  now that `Expr` covers declarative composition.
- **E3 — measurement (docs-only).** Dated `docs/performance/` snapshot:
  closure-form vs materialized-`Expr` warm reads must be equivalent
  (`Expr` cost is construction-time only).
- **E4 — static lowering (conditional, separate decision).** E2 landing
  formally fires the ADR's reopen trigger #1, but proceed only if E3 +
  real consumers (e.g. typed-spreadsheet formulas) show demand for
  lowering pure fixed-source expression graphs. Requires a fresh
  design/spec pass satisfying the ADR's hard requirements (same-runtime
  validation, duplicate-dependency normalization, no accumulator
  support, unchanged inside/outside read semantics, …). If not pursued,
  append the fired-trigger/decline rationale to the ADR.

Track E inherits the spec's non-goals: no operators directly on
`Input[T]`, no implicit literal conversion, no standalone expression read
API, no indexing syntax in v1.

## Out of scope

- Closing `CellId` / `RuntimeId` / `ListenerId` / `AccumulatorId`
  `pub(all)` fields (language-forced; separate named-constructor track).
- `EagerDerived` `Result` read channel (waiting for demonstrated need).
- `batch_result`'s wide `Error` type (blocked on the generic `raise?`
  typing limitation; document instead).
- Datalog surface (`Relation` / `new_rule` / `fixpoint`) pruning — kept
  as one of the four execution modes despite thin usage.

## Rollback

Phases 1–2 precede any publish, so a revert of the offending PR is a
complete rollback (no downstream impact). Phase 0's deprecation
attributes are harmless to ship standalone if later phases are delayed.
Codex design validation runs before Phase 0 execution begins (plan-level
"is this correct / what breaks" pass), and each phase PR gets a Codex
pre-PR review.
