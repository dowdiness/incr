# Plan 016 — Incr Next usability and distribution evidence

**Reader:** Implementers and reviewers of external usability, documentation, and distribution evidence.

**Decision:** Commission K2 to answer one question: can an independent consumer without repository knowledge or testkit/private APIs correctly use Incr Next through its public interface and executable docs, then prepare it as an unpublished distributable package?

**Keep until:** K2 is accepted, rejected, or replaced and its disposition is recorded.

**Disposition:** Active handoff, commissioned; no implementation accepted.

**Status:** `IN PROGRESS (COMMISSIONED; IMPLEMENTATION NOT ACCEPTED)`

**Decision record:** This commission updates the existing [2026-08-17 sibling-product ADR](../docs/decisions/2026-08-17-incr-next-pre-1-0-sibling-product.md) to record that its separate K2 gate has fired. It creates no new ADR; closure/disposition updates or adds an ADR as appropriate.

## 1. Commission boundary

Commission only these K2 slices, in order:

- **K2.1 consumer probe:** an independent public-interface consumer and friction ledger.
- **K2.2 executable docs:** source-backed documentation demonstrated by executable examples.
- **K2.3 distribution dry-run:** an unpublished candidate package prepared and consumed outside the repository source tree.
- **K2.4 disposition:** choose a follow-up and record closure.

This plan excludes new semantics; Mount; Program/Port/Formula; public debug/explain; public or automatic eviction/LRU; parallel evaluation; current-Incr compatibility or migration; Canopy production; and publication or registry mutation. Publication and Canopy production are not authorized.

## 2. Working discipline

This commission PR changes documentation only. Its merge is the explicit commission for later K2 evidence PRs; it accepts no implementation. Begin no K2 implementation before that merge. For each later slice, fetch `origin/main`, create an isolated worktree whose HEAD contains that base, record the exact base, and verify a clean tree before edits. Build the consumer and tests before prose. Accept each slice independently before starting its successor.

Classify each friction as **example design or knowledge**, **documentation gap**, **MoonBit syntax**, **genuine public API defect**, or **semantic contract defect**. One consumer report never authorizes an API change. A public API change becomes a candidate only after multiple independent consumer observations support the same diagnosis. A semantic change requires an explicit K0 contract-change record and separate authorization. A nonsemantic public API change requires a plan amendment or separate evidence PR and full K2 reacquisition.

Apply Existing API First before any new definition. Inspect project APIs and the MoonBit core APIs that fit the concrete data shape; record reused and rejected candidates and justify any new helper or remaining mutation. Keep the consumer functional-core/imperative-shell: deterministic values, reads, transitions, and expected outcomes in the core; module setup, callbacks, process/archive commands, and target execution in the shell.

## 3. K2.1 consumer probe

Create this standalone probe module, with no edits to the product module:

```text
incr_next_consumer_probe/{moon.mod,moon.pkg,main.mbt}
```

Its only non-core dependency/import is `dowdiness/incr_next`. It must not import current `incr`, `incr_next_testkit`, private or test-only packages, Canopy, research, or evidence providers.

Use a small Unit-keyed consumer:

- `Source[Int]` values `left` and `right`, plus `Source[Bool]` `select_right`.
- A selected Query dynamically reads one source; a doubled Query reads the selected Query; a root read demands the doubled View.
- Exercise an atomic transaction touching multiple Sources.
- Close the Region and show a surviving View returns `ReadError::ClosedRegion`.
- Cover `Store`, `Region`, `Source`, `Query`, `View`, `QueryContext`, and `Transaction`.

Pin this minimum behavior matrix:

| Step | Committed values | Expected selected | Expected doubled |
|---|---|---:|---:|
| Initial | `left = 2`, `right = 11`, `select_right = false` | 2 | 4 |
| Atomic switch | stage `left = 3`, `right = 13`, `select_right = true` in one Transaction | 13 | 26 |
| Switch back | stage `left = 5`, `right = 17`, `select_right = false` in one Transaction | 5 | 10 |
| Close | close the Region; retain the doubled View | `ReadError::ClosedRegion` | `ReadError::ClosedRegion` |

The Query callbacks propagate every failed tracked read unchanged. The example stages each multi-Source edit through one Transaction and performs no root read until the transaction returns; it exposes no application-side intermediate publication path.

Explicitly omit cycle, type-owned cutoff, cross-Region, proof loss, counters/work, and private instrumentation: K1 owns those semantics.

Acceptance requires import boundaries; the behavior matrix above; transparent structural errors; public interface only; zero delta in current `incr/`, production `incr_next/`, both K0 contracts, and every pre-existing generated `.mbti` unless a separately authorized friction response restarts K2; and successful default, native, JS, and wasm-gc checks and tests. A generated interface belonging only to the new consumer is not a protected product-interface delta.

### Friction ledger

The ledger records evidence; it never authorizes API changes.

| Operation | Current form | Friction | Classification | Evidence | API change needed |
|---|---|---|---|---|---|
| Store/Region | `@incr_next.Store::Store()` then `store.region()` | Expected setup failures remain explicit `Result` values; this fixed probe unwraps only setup invariants. | Example design or knowledge | `incr_next_consumer_probe/main.mbt`; default/native/JS/wasm-gc check, test, and run | No; not authorized |
| Source | `region.source(value)` and `source.view()` | The public constructor and stable View are direct once Region ownership is understood. | Example design or knowledge | Consumer import scan contains only `@incr_next`; behavior matrix passes | No; not authorized |
| Nested read + `ReadError` | Branch with `match ctx.read(flag.view())`; transform with `Result::map` | A dynamic branch needs an explicit match to preserve `Err(error)` unchanged; a value-only transform can reuse `Result::map`. | Example design or knowledge | Selected and doubled callbacks in `main.mbt`; all four targets pass | No; not authorized |
| Transaction | One `store.transaction` callback with three checked `tx.set` calls | Every staged write result must be propagated, and the successful returned `Revision` must be consumed explicitly with `ignore`. | MoonBit syntax | Initial compile rejected an implicitly ignored `Revision`; corrected consumer passes all targets | No; not authorized |
| Query key | `(ctx, _unit : Unit)` and `query.at(())` | Unit is concise, but the callback annotation and separate `at(())` capture are useful inference cues. | MoonBit syntax | Both Query callbacks and surviving Views compile on all four targets | No; not authorized |
| Close | `region.close()` then `store.read(surviving_view)` | Matching `Err(@incr_next.ReadError::ClosedRegion(..))` is direct; both surviving Query Views report closure. | Example design or knowledge | Runtime guards and one passing test on each target | No; not authorized |
| Cutoff selection | Baseline `query`; inspect `query_eq` and `query_type_owned` without using them | `moon ide doc` and generated `.mbti` expose the three typed choices; this graph needs no cutoff. | Example design or knowledge | `incr_next/pkg.generated.mbti` and standalone `moon ide doc` inspection | No; not authorized |
| Toolchain scope | Target the consumer package and use the repository-pinned MoonBit for canonical interface evidence | Local MoonBit 0.10.8 exposes unrelated root-workspace dependency/deprecation failures and removes one generator-owned trailing blank line from the empty interface emitted by pinned 0.10.4. | MoonBit syntax | Both toolchains pass the four-target consumer matrix; pinned 0.10.4 `fmt`/`info` leaves the candidate tree clean | No; not authorized |
| Workspace entry point | Keep a lifecycle-scoped module README and index it from `docs/README.md` | A new workspace member fails repository documentation boundaries without an entry-point README, even when its executable and manifest are complete. | Documentation gap | Hosted `check-documentation-boundaries.py` failure on PR #489; local checker passes after adding the K2.1-only README | No; not authorized |

## 4. K2.2 executable documentation

Begin only after K2.1 is accepted. Write source-backed, public-only executable docs covering: quickstart; mental model; transactions and snapshots; `QueryContext` and tracked reads; Region lifetime; structural versus domain errors; cutoff; caller snapshot obligations; and common mistakes.

Include public-only executable misuse demonstrations for mutable key/source payload/memo result, `ReadError` converted to `Ok`, unsound `CutoffEq`, and untracked state. Classify these as expected divergence from caller-contract violations, not promised kernel behavior. Keep their packages, tests, and reported results separate from successful Quickstart examples and Fresh conformance; do not copy or import the testkit. Before prose, select a drift mechanism—checked `.mbt.md`/tests or snippet extraction tied to the consumer—and document that choice.

## 5. K2.3 distribution dry-run

Do not publish. Audit `incr_next/moon.mod` metadata, package file/content policy, generated `.mbti`, README/license, dependency closure, and monorepo paths. Choose and justify an explicit include/exclude policy; the mere presence of tests is neither an automatic pass nor an automatic defect. Build a candidate archive, unpack it in a fresh non-repository temporary workspace with no path to the source checkout, and run the consumer against the candidate artifact—not repository source—on default, native, JS, and wasm-gc.

Characterize `moon package --list`, supported archive commands, and `moon publish --dry-run`; an unimplemented package dry-run or a server/CLI status mismatch is tooling evidence, not a pass. Never run a command that can mutate the registry. The fresh workspace must not discover or inherit the repository's `moon.work`. Detect undeclared workspace dependencies, testkit leaks, relative docs/examples, and source fallback. Record tool versions, commands, archive hash, file list, dependency graph, and raw outputs durably. Passing means preparable, not publishable now.

## 6. K2.4 disposition

Choose exactly one:

- **A:** separately commission alpha publication;
- **B:** remain unpublished while supporting repository external consumers;
- **C:** fix usability/API issues and reacquire evidence.

K2 authorizes none of these outcomes by itself. At closure, update the accepted sibling-product ADR or add a superseding/follow-up ADR as appropriate, record the accepted evidence and choice, delete Plan 016 under the root plan workflow, and update all indexes and roadmaps.

## Decision record

- Updated ADR: [Adopt Incr Next as a pre-1.0 sibling product](../docs/decisions/2026-08-17-incr-next-pre-1-0-sibling-product.md) now records Plan 016 as the separate K2 commission.
- No new ADR needed for commission: Plan 016 executes the ADR's already accepted next evidence gate without changing product or semantic contracts.
- K2 closure requires the disposition record described above.

## 7. Order and stop conditions

After this commission merges, execute strictly **K2.1 → K2.2 → K2.3 → K2.4**, with the predecessor accepted first. Stop and replan on a forbidden dependency, private API or new semantics requirement, atomicity/lifetime failure, inadmissible documentation pattern, source fallback, target failure, or base/public API movement.

## 8. Final checklist

- [ ] Public-only consumer; no current `incr`, testkit, private API, or evidence provider
- [ ] Dynamic branch values, atomic transaction, close, and surviving View error
- [ ] Default/native/JS/wasm-gc evidence
- [ ] Executable quickstart, caller-violation demos, and selected drift mechanism
- [ ] Fresh dependency resolution and candidate package/.mbti audit
- [ ] Zero unintended K1/API delta; no publication
- [ ] Friction classifications and independent public-interface review
- [ ] Raw backend outputs, exact HEAD, and exact accepted base recorded
