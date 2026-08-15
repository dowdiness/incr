# Plan 015 — Incr Next K1 kernel alpha

**Reader:** The implementer and reviewers of the first integrated
`dowdiness/incr_next` kernel.

**Decision:** Build one production-quality kernel from the #460–#465 contracts
in six test-first increments. Do not modify or emulate current Incr, and do not
import the evidence providers.

**Keep until:** K1 is accepted, rejected, or replaced by a new plan.

**Disposition:** Active handoff. K1.1 semantic implementation is accepted and
merged. K1.2 typed memo, last-successful forward verification, and failure
atomicity are accepted at implementation head
`12ec2404b676ef7864e353aeb3681c0fef6f20e3`; merged at squash commit
`db2ac77ac0362a7c5ff8d20887868cbdbb635aa8`. K1.3 invocation-level cycle
detection is implementation complete and maintainer accepted at implementation
head `e187b562f87ec4ecd50940a5e8fc2bc5d478380c`; merge is pending the
status-only finalization head passing all required gates. K1.4–K1.6 remain
blocked and uncommissioned. This plan does not authorize publication, Issue
action, parent-submodule update, hosted CI beyond what already ran, push/PR
beyond PR #476, or any work beyond K1.3.

**Status:** IN PROGRESS (K1.1 ACCEPTED / MERGED; K1.2 ACCEPTED / MERGED;
K1.3 IMPLEMENTATION COMPLETE / MAINTAINER ACCEPTED / MERGE PENDING;
K1.4–K1.6 BLOCKED / UNCOMMISSIONED)

---

## Commission scope

Commissioned and accepted:

```text
K1.1 module and package seams
K1.1 independent model/Fresh boundary
K1.1 opaque capability and identity skeleton
K1.1 Source and no-memo Query evaluation
K1.1 atomic transaction and module-global alpha phase gate
K1.1 Region lifetime skeleton
K1.1 target, negative-interface, and ownership gates
```

Commissioned, implemented, and accepted:

```text
K1.2 typed per-Query memo ownership
K1.2 last-successful forward verification and dynamic traces
K1.2 target-local failure atomicity and recovery
K1.2 ownership, backend, boundary, and work-count gates
```

Commissioned, implementation complete, maintainer accepted, merge pending:

```text
K1.3 invocation-level active tracking and structured cycle detection
```

Blocked and uncommissioned:

```text
K1.4 typed cutoff and backdating
K1.5 private proof loss and ownership completion
K1.6 later product-quality conformance expansion
Mount, Program, Canopy integration, ADR, or publication
```

K1.3 implementation is complete and maintainer accepted at implementation head
`e187b562f87ec4ecd50940a5e8fc2bc5d478380c`. Merge is pending the status-only
finalization head passing all required gates. The K1.4–K1.6 sections remain
implementation-ready handoffs, not authorization to begin them. Stop after K1.3
acceptance and request a separate K1.4 decision.

## Goal

Create sibling modules:

```text
incr_next/             dowdiness/incr_next, pre-1.0
incr_next_testkit/     independent Fresh oracle and differential workloads
```

The result must satisfy:

- [K0 Product and Kernel Contract](../docs/design/specs/2026-08-13-incr-next-kernel-contract.md)
- [K0 Lifetime and Transaction Contract](../docs/design/specs/2026-08-13-incr-next-lifetime-and-transactions.md)

The implementation remains independent of Canopy. Existing Canopy P0/P1/P1.2/P2a
workloads become later external acceptance consumers, not K1 kernel code.

## Non-goals

Do not add public eviction, automatic LRU, Mount/reactive roots,
Program/Port/Formula, reducers/history, actions/resources, async effects,
parallel evaluation, cross-Store direct reads, current-Incr compatibility,
persistent cache, or public debug/explain.

Do not optimize representation without a release microbenchmark that reproduces
a measured bottleneck. K1 acceptance uses work-count assertions and has no wall-clock threshold.

## Required work discipline

### Isolated exact-base work

1. Fetch `origin/main` and create a dedicated worktree whose HEAD contains it.
2. Confirm `git status`, `git diff --stat`, and submodule state before edits.
3. Keep current `incr/` behavior and generated interfaces unchanged.
4. Before final review, fetch `origin/main` again; sync and rerun affected gates
   if the base moved.

### Existing API First for every definition

Before defining a function, helper, type, loop, or data-manipulation path, add a
short reuse note to the implementation PR/handoff:

1. Inspect project candidates in current Incr and prior evidence with
   `moon ide outline`, `peek-def`, and `find-references`. Reuse pure value ideas
   only when they do not introduce a dependency on `dowdiness/incr`.
2. Inspect actual MoonBit core candidates with `moon ide doc`:
   `Map`/`Set`, `Option`/`Result`, `Array`/`ArrayView`,
   `String`/`StringView`, `Bytes`/`BytesView`, `Buffer`/`StringBuilder`, and
   `cmp`/`math`. Add `Hash`/`Eq` and `Ref` when the concrete shape requires
   them.
3. Record at least two applicable candidates, where they are defined, whether
   reused, and why any rejected candidate does not own the responsibility.
4. State the responsibility boundary for every unavoidable new helper.
5. Justify every `let mut`, push loop, manual index loop, and `while`. Local
   mutation is acceptable only to build a returned value or implement the
   measured state machine without observable external mutation.

### Functional Core / Imperative Shell

Keep verification, transaction, cycle, cutoff, clock, and close decisions
deterministic. Pass state and events explicitly and return next state plus
commands. Keep phase mutation, callbacks, payload replacement, capability
expiry, and release actions in a thin imperative shell.

### Validation after each slice

Run from a validated package/module root:

```text
moon fmt
moon info
git diff -- '*.mbti'
moon check <affected package/module>
moon test <affected package/module>
git diff --check
```

Never hand-edit generated `.mbti`. At phase gates, run workspace-root
`moon check` and `moon test`, the architecture scripts, and all supported target
matrices described below.

## Boundary matrix before implementation

Write this matrix into the first test package before production code:

| Dimension | Required cases |
|---|---|
| Provenance | same Store, different Store, same Region, different Region |
| Phase | Idle, Evaluating, Transacting, catchable exit |
| Lifetime | open, first close, duplicate close, surviving View |
| Publication | empty, one write, equal write, multiple Sources, repeated Source, multi-Region same Store, cross-Store/closed-Region poison, callback error, ignored invalid set |
| Query | Source, Unit key, equal keys, dynamic branch, chain, diamond |
| Failure | initial error, error over memo, recovery, dead error branch |
| Cycle | direct, mutual, same Query/different key, finite recursion, recovery |
| Cutoff | always changed, Eq-equivalent, type-owned equivalent, changed, unsound excluded counterexample |
| Proof loss | absent memo, eviction, rematerialization, downstream retained recipe |
| Ownership | external alias, replacement, rollback, close, temporary trace, tombstone |

Every implementation slice begins with a failing behavioral or compile-negative
test derived from this matrix.

## K1.1 — Capability, Fresh semantics, publication, and lifetime skeleton

### K1.1a: Module and package seams

- Add `incr_next` and `incr_next_testkit` to `moon.work` using current
  `moon.mod` and `moon.pkg` formats.
- Start the kernel as one package with multiple private files.
- Create testkit packages `model`, `fresh`, `incremental_adapter`, `scenarios`,
  and `differential`.
- Add `scripts/check-incr-next-boundaries.sh` proving the complete package import
  DAG, not only direct imports:
  - neither `fresh` nor any package reachable from `fresh` imports
    `dowdiness/incr_next`;
  - kernel does not import testkit or current `dowdiness/incr`;
  - `incremental_adapter` may import the kernel;
  - no evidence-provider path is imported or copied as a generated dependency.
- Add known-negative direct and transitive fixtures/self-tests, including
  `fresh -> model -> incr_next`, so a passing boundary script is trustworthy.
- Add reader-facing `incr_next/README.mbt.md`, a minimal
  `incr_next/docs/roadmap.md`, and module docs index before treating the module
  as publishable. Update the root `docs/README.md` and `docs/roadmap.md` links in
  the same change; keep examples checked and explicitly alpha-labeled.
- Update `.github/workflows/ci.yml`: existing CI enumerates module roots and
  package paths rather than trusting `moon.work` membership. Add an
  `incr-next` matrix job and a new aggregate job named `Incr Next Required`.
  The aggregate has `needs: [incr-next, boundaries]` and fails unless both jobs
  succeed; configure that named check as the Incr Next branch-protection gate.
  Existing unrelated repository checks remain required by their current policy.

**First failure:** boundary self-tests detect both a direct Fresh import and a
transitive `fresh -> model -> incr_next` import.

### K1.1b: Independent model and Fresh oracle

- Define operation scripts, logical IDs, and normalized observations in
  `model`.
- Implement the memo-free Fresh evaluator in `fresh`, using no kernel imports.
- Cover canonical Source View, Unit/keyed Query, chain, diamond, dynamic branch,
  one root snapshot, domain `Result`, and structural error transparency.
- Keep Fresh's QueryContext-equivalent capability private to testkit; do not
  force Fresh and incremental implementations to share public handles.

**First failure:** a Fresh script observes one normalized result for the initial
Source/Query graph before an evaluator exists.

### K1.1c: Public capability skeleton

- Introduce `Store`, `Region`, `Source[T]`, `Query[K,V]`, opaque non-callable
  `View[V]`, `QueryContext`, `Transaction`, and `Revision` with the minimum
  structural error types.
- Select `QueryContext`, not historical `EvalCtx`; expose only tracked `read`
  and tracked `revision`.
- Keep `ChangeEpoch`, `EvalSession`, frames, recipes, QueryCore, and owner IDs
  private.
- Compile-negative probes reject View construction/invocation, QueryContext
  construction, direct Source mutation, and private field access.

**First failure:** external probes must fail for View invocation and Source set.

### K1.1d: Store/Region and no-memo reads

- Implement Store/Region identity and the module-global
  `Idle/Evaluating/Transacting` alpha gate.
- Implement one canonical Source View and no-memo Query execution with callback
  shape `(QueryContext,K)->Result[V,ReadError]`.
- Permit same-Store cross-Region reads; reject cross-Store reads.
- Expire QueryContext on every callback exit and restore `Idle` on every
  catchable root exit.
- Assert that metadata rejection occurs before caller `Hash`/`Eq` execution.

**First failure:** cross-Store nested read is rejected while same-Store
cross-Region read succeeds.

### K1.1e: Atomic transaction

- Implement transaction-local typed staging closures with last-write-wins.
- Permit one transaction to stage Sources across multiple open Regions of its
  owning Store; validate Store and Region generation before staging.
- Make cross-Store, closed/stale-Region, or otherwise invalid `set`
  sticky-poison the transaction even if its error is ignored.
- Roll back callback errors and poison without clock or Source changes.
- Commit every affected same-Store Region atomically, advancing the owning
  Store's `Revision` and `ChangeEpoch` exactly once, including equal
  publication.
- Make empty success zero-delta and expire captured Transaction capability.
- Reject root operations and Region mutation during transaction, including via
  another Store.

**First failure:** two Sources in different open Regions of one Store never
expose an intermediate commit, while an ignored closed-Region or cross-Store
write rolls the entire callback back.

### K1.1f: Region close skeleton

- Implement `Open -> Closing -> Closed` and close only from `Idle`.
- First close clears Source payloads and Query compute captures, seals the
  generation, advances `ChangeEpoch` once, and leaves `Revision` unchanged.
- Duplicate/rejected close is zero-delta.
- Surviving Views return `ClosedRegion` without retaining cleared heavy payload.
- Do not add Store-wide close unless separately designed.

**First failure:** a surviving View reads `ClosedRegion` after first close while
close counters show one epoch delta and zero Revision delta.

### K1.1 gate

- Fresh and no-memo incremental adapters match normalized K1.1 scripts.
- QueryContext/Transaction expiry and every catchable phase exit restore Idle.
- Boundary and compile-negative probes pass.
- Generated interface contains only the intended capability surface.

## K1.2 — Typed memo and last-successful forward verification

K1.2 answers one question: can the accepted K1.1 kernel add Query-local typed
memos and last-successful forward traces so same-epoch reads hit cache,
unrelated publications green-verify, selected dependency changes recompute,
and failed recomputes preserve the prior successful authority without returning
stale fallback, while Fresh outcomes remain equal?

K1.2 admits only acyclic invocation graphs. It does not add active invocation
maps, cycle witnesses, recursive Query support, cutoff/backdating, proof loss,
eviction, or a public debug surface.

### Compile probe: public key bounds

Before the first production definition, compare generated `.mbti` variants for
placing the required `K : Hash + Eq` bound on `Region::query`, `Query::at`, or
the `Query[K,V]` definition. Select the smallest natural public contract and
record:

- the generated trait bound and impact on existing K1.1 consumers;
- Eq-equal key sharing semantics;
- the caller contract that key Hash/Eq behavior remains stable while a View can
  be read;
- why neither key erasure nor linear search is used to hide the bound.

### K1.2a: Typed per-Query memo ownership

- Give each `QueryCore[K,V]` a private typed `Map[K,MemoEntry[V]]` and local
  memo identity allocator.
- Store value, memo identity, `verified_at`, `changed_at`, and direct
  last-successful forward trace in each entry.
- Keep root reads parent-trace-free and nested reads trace-producing.
- Make repeated same-`ChangeEpoch` reads cache hits without recomputation.
- Keep different QueryCore instances disjoint even for Eq-equal keys.
- Clear memo values and traces through the Region-owned close path; a surviving
  View owns a recipe, never a memo incarnation.

**First failure:** equal-key Views share one memo while different QueryCore
instances do not, and a same-epoch reread has zero compute delta.

### K1.2b: Verification and dynamic traces

- Record Source, Query invocation, and Revision-clock dependencies in
  last-successful forward traces.
- Stamp each committed Source publication with the current private
  `ChangeEpoch`; track `QueryContext::revision()` only when called.
- Verify old dependencies without recording them into the parent's new trace.
- Treat an unavailable old dependency as `RecomputeRequired`, not as the root's
  current structural error, so a current branch may avoid a closed Region.
- Green verification updates `verified_at` only.
- Red verification recomputes with a temporary trace and atomically installs
  the successful value, trace, and stamps.
- Test chain, diamond sharing, unrelated and selected publication, dynamic
  branch replacement, Revision-clock-only Query, and same-Store cross-Region
  branch-away.

**First failure:** an unrelated publication green-verifies the root while a
selected-branch publication recomputes it.

### K1.2c: Failure atomicity

- First structural failure installs no memo.
- Failure over a successful memo returns the current error with no stale
  fallback and preserves target memo identity, value, trace, and stamps.
- Release the failed temporary trace while retaining valid upstream successes;
  do not roll back upstream memos that completed successfully.
- Recovery retries and atomically replaces the target's successful authority.

**First failure:** current failure over a memo leaves its white-box snapshot
unchanged and returns the error rather than the old value.

### K1.2 gate

Correctness:

- all K1.1 differential scripts still match Fresh;
- equal-key sharing and QueryCore isolation hold;
- same-epoch hits, unrelated green verification, selected red recomputation,
  dynamic trace replacement, Revision-clock tracking, failure preservation,
  no stale fallback, recovery, and cross-Region branch-away pass.

Ownership and boundaries:

- successful replacement releases the old value and trace; failed temporary
  traces and close-time memo payloads are released;
- surviving Views retain no memo incarnation, and downstream tombstone/key
  evidence retains no Region-owned heavy payload;
- no reverse subscriber edge, erased global memo registry, public debug API,
  cycle/cutoff/eviction surface, current-`incr/` diff, Fresh import-DAG drift,
  generated-interface leak, or backend omission is accepted.

Work counts:

- repeated reads do not increase compute count;
- unrelated publication increases green verification but not root compute;
- selected publication increases root compute;
- a shared diamond dependency verifies or computes once per epoch;
- direct trace lengths and memo counts are asserted white-box.

K1.2 acceptance is determined by work-count assertions; wall-clock thresholds remain outside this gate.

## K1.3 — Invocation-level cycles

K1.3 answers one question: can the accepted K1.2 kernel add only
invocation-level active tracking, allow finite recursion across unequal keys,
detect re-entry to the same QueryCore with an Eq-equal key as a deterministic
Cycle, and preserve K1.2 memo, trace, and failure atomicity?

Finite keyed recursion such as `q(3) -> q(2) -> q(1) -> q(0)` is legal. This is
semantic support for finite recursion over unequal keys, not an iterative
evaluation machine, unbounded-depth guarantee, or stack-overflow protection.

### Commissioned scope

- One typed active invocation map per QueryCore.
- One key-free active stack per EvalSession.
- Invocation identity defined by QueryCore identity plus equality under
  `K::Eq`.
- Active re-entry checked before same-epoch memo lookup, old-trace
  verification, or current recomputation.
- Copied key-free cycle witnesses.
- Independent Fresh and incremental cycle detection with shared logical Query
  names, keys, and normalized observations only.
- A Cycle found only while verifying an old trace becomes
  `RecomputeRequired`, allowing the current branch to avoid the old cycle.
- A Cycle reached by current recomputation becomes the root `ReadError`.
- Active/tracking cleanup on every structured exit.
- Failure-atomic memo preservation and recovery after cycle introduction and
  removal.

### Explicit non-goals

- Cutoff or backdating.
- Eviction or automatic retention.
- Iterative evaluation or stack-overflow protection.
- A cycle recovery value or cached cycle error.
- Parallel evaluation.
- Mount, Program, Canopy integration, ADR, or publication.

### Active-check order

Every Query invocation follows this order:

```text
validate Store / Region / QueryContext
    -> active invocation check
    -> same-epoch memo hit
    -> old-trace verification or current recomputation
```

The active check precedes cache lookup so an old memo cannot conceal re-entry
to an invocation that is already on the current evaluation path. An ordinary
same-epoch hit that is not already active returns without adding an active-map
entry. The map and stack track only the slow path that proceeds into stale
verification or computation.

### Witness contract

The testkit-normalized witness has this semantic shape:

```text
CycleWitness {
  path : Array[QueryId]
}
```

Detection is key-sensitive; the copied witness is key-free:

```text
direct self      [A, A]
mutual cycle     [A, B, A]
same Query keys  [Q, Q, Q]
```

A witness retains copied logical Query identifiers only. It never retains or
formats a generic key, QueryCore, closure, memo, trace, or Region-owned payload.
The normalized semantics are fixed by this commission. Before the first kernel
interface edit, generated `.mbti` review must select the smallest structural
`ReadError`/witness spelling that preserves those semantics without exposing
active tracking or key representation.

### Implementation order

```text
K1.3a  testkit model adds cycle graph recipes and normalized witnesses
       Fresh adds its own active invocation tracking
       Fresh and incremental share no active-tracking implementation

K1.3b  QueryCore adds its typed active map
       EvalSession adds its key-free active stack
       active re-entry is checked before cache lookup

K1.3c  old-verification Cycle and current Cycle are separated
       failure atomicity and same-MemoId recovery are retained
       all structured exits receive cleanup and native RC evidence
```

### First failure matrix

| Case | Expected result |
|---|---|
| Direct self-cycle `A -> A` | `Cycle[A, A]` |
| Mutual cycle `A -> B -> A` | `Cycle[A, B, A]` |
| Same Query key cycle `q(0) -> q(1) -> q(0)` | `Cycle[Q, Q, Q]` |
| Finite recursion `q(3) -> q(2) -> q(1) -> q(0)` | Success |
| Unequal-key cross-Query `A(0) -> B(0) -> A(1)` | Success |
| Dead cycle branch | Success; no Cycle |
| Sequential duplicate read | Success; no Cycle |
| Initial Cycle | No memo installed |
| Cycle introduced over a successful memo | Current Cycle; old memo unchanged; no stale fallback |
| Repeated Cycle | Detected on every read; error not cached |
| Cycle removed | Recovery with the same MemoId |
| Cycle reached only through an old trace | `RecomputeRequired`, then current branch succeeds |
| Cycle reached by current recomputation | Current Cycle determines the root error |
| Close or another structural error | Active map and session stack empty after exit |

The matrix is added to the independent testkit before kernel production code.
Fresh and incremental implement active tracking independently and compare only
logical outcomes and normalized witnesses.

### K1.3 acceptance gate

Correctness:

- Existing K1.1 and K1.2 differential scripts still match Fresh.
- Fresh and incremental normalized Cycle witnesses match.
- Direct, mutual, and same-Query keyed cycles are detected.
- Finite keyed recursion, unequal-key cross-Query recursion, dead branches, and
  sequential duplicate reads succeed.
- A cache hit cannot hide active re-entry.
- An old-verification Cycle requests current recomputation and does not decide
  the root error; only a Cycle reached by current recomputation does.
- Cycle removal recovers successfully.

Failure atomicity:

- An initial Cycle installs no memo.
- A Cycle over an existing target preserves its value, trace, MemoId,
  `verified_at`, and `changed_at` exactly.
- A cycle read returns the current error without stale fallback.
- Cycle errors are never memoized; repeated reads detect them again.
- Recovery keeps the target MemoId and atomically replaces value, trace, and
  current stamps.

Cleanup and ownership:

- Active keys are removed after success, Cycle, and every other structured
  error.
- The session stack is empty after every root exit.
- Temporary traces and frames are released after Cycle.
- CycleWitness retains no QueryCore, key, closure, memo, trace, or Region-owned
  payload.
- Region close releases active, memo, and trace payloads; native RC evidence
  distinguishes a surviving View's retained key from an active-map leak.

Boundaries and backends:

- No reverse subscriber edge or global erased-key registry is added.
- Current `incr/` implementation and interface diff remains zero.
- No public cutoff, backdating, eviction, retention, debug, Mount, or Program
  surface appears.
- Fresh and every transitive dependency remain independent of
  `dowdiness/incr_next`.
- Default, native, JavaScript, and wasm-gc matrices pass.
- Generated `.mbti` review confirms only the commissioned structural
  Cycle/witness delta and no active-tracking representation.

**First failure:** finite `q(3) -> q(2) -> q(1) -> q(0)` recursion succeeds
while `q(0) -> q(1) -> q(0)` returns a deterministic copied key-free witness.

## K1.4 — Typed cutoff and backdating

- Compile-probe explicit AlwaysChanged, `Eq`, and type-owned propagation-policy
  constructors before accepting names into `.mbti`.
- Keep cutoff policy fixed per Query and private; expose no arbitrary predicate.
- Invoke cutoff exactly once after successful recompute over an existing memo.
- Always install the newest value and newest trace.
- Preserve old `changed_at` only when propagation-equivalent; otherwise stamp
  current `ChangeEpoch`.
- Do not invoke cutoff for first success, cache hit, green verification, Cycle,
  or another failed recompute.
- Include excluded unsound observer and non-transitive relation counterexamples.

**First failure:** an equivalent dynamic-branch recompute changes its trace and
newest direct value while skipping one downstream compute.

### K1.4 gate

Differential outcomes remain exact for admissible scenarios. Counters prove the
invocation discipline and at least one downstream cutoff skip.

## K1.5 — Private proof loss and complete ownership closure

- Add package-private typed per-key eviction only for white-box tests.
- Reject eviction outside `Idle` or after close before caller `Hash`/`Eq`.
- Eviction changes neither clock nor Query/View definition.
- Rematerialization allocates a new memo identity, calls cutoff zero times, and
  conservatively stamps current `ChangeEpoch`.
- Verify downstream recipes rematerialize missing dependencies and conservatively
  recompute parents after proof loss.
- Complete Region close release for memo tables, traces, cutoff captures, and
  active state.
- Add native reference-count/finalizer evidence listed in the lifetime contract.

**First failure:** a surviving View rematerializes a new memo after private
eviction without a clock delta, while an external alias is distinguished from a
kernel-owned retained edge.

### K1.5 gate

Proof-loss, per-key isolation, dynamic trace, failure, cycle, phase rejection,
close, and ownership scenarios pass. No public eviction appears in `.mbti`.

## K1.6 — Product-quality conformance gate

### K1.6a: Property and differential testing

Generate and shrink operation scripts covering Source updates, atomic
multi-write, dynamic branches, chains/diamonds, equal keys, cycle introduction
and removal, Region close, structural failure/recovery, cutoff, and private
proof loss. Compare only normalized logical outcomes with Fresh.

Retain expected-divergence tests for mutable keys, Source aliases, memo-result
aliases, forbidden cutoff observers, and non-transitive propagation relations.

### K1.6b: Internal observability

Retain content-free internal counters sufficient to assert compute, same-epoch
hit, green verification, red recompute, failure, cutoff/backdate, memo/trace,
eviction, and rematerialization work counts. Do not expose them through
QueryContext or public `.mbti`; public explain/debug remains K2.

### K1.6c: Backend, CI, documentation, and interface matrix

Before implementation chooses package names, verify this preliminary list
against every created `moon.pkg`, then commit the exact root × target matrix.
No target may be silently omitted:

| Root | Default | Native | JS | wasm-gc |
|---|---|---|---|---|
| `incr_next/` | check + test | check + test | check + test | check + test |
| `incr_next_testkit/model` | check + test | check + test | check + test | check + test |
| `incr_next_testkit/fresh` | check + test | check + test | check + test | check + test |
| `incr_next_testkit/incremental_adapter` | check + test | check + test | check + test | check + test |
| `incr_next_testkit/scenarios` | check + test | check + test | check + test | check + test |
| `incr_next_testkit/differential` | check + test | check + test | check + test | check + test |

Each cell expands to exact commands:

```text
moon check [--target native|js|wasm-gc] <root>
moon test  [--target native|js|wasm-gc] <root>
```

The default cell omits `--target`. If a created package cannot support one of
these targets, K1 stops for an explicit contract amendment that names the root,
toolchain limitation, replacement evidence, and maintainer approval; CI must
not skip it conditionally. Run `moon fmt && moon info` from both `incr_next/`
and `incr_next_testkit/` module roots, then inspect every generated `.mbti` diff
for constructor visibility, accidental fields, widened trait bounds, and public
debug/eviction leakage.
Also run:

```text
native reference-count/finalizer harness
compile-negative probes
boundary scripts and direct/transitive self-tests
scripts/check-workspace-boundaries.sh and self-test
python3 scripts/check-documentation-boundaries.py
workspace-root moon check and moon test as a final fan-out
```

Update `.github/workflows/ci.yml` with an `incr-next` matrix whose rows are the
24 root/target combinations above. Every row runs its exact check and test
commands. Add `Incr Next Required` with `needs: [incr-next, boundaries]`; it
passes only when the full matrix and boundary job succeed. Make this named job
the Incr Next branch-protection requirement. Validate the reader-facing README,
module roadmap/docs index, checked examples, and root index migration. Confirm
current `incr/` interfaces and behavior are unchanged.

### K1.6d: Independent review

Run independent MoonBit reviews for semantic parity, public interface depth,
package boundaries, lifetime/RC evidence, documentation drift, and CI readiness.
Resolve all blockers, fetch `origin/main` again, and repeat affected gates on the
exact candidate commit.

## Final acceptance matrix

```text
[ ] independent Fresh package imports no incr_next
[ ] current dowdiness/incr dependency and interface delta are zero
[ ] one opaque non-callable View recipe surface
[ ] QueryContext has tracked read/revision only
[ ] Transaction is the only Source publication path
[ ] same-Store multi-Region transaction publishes atomically
[ ] closed-Region/cross-Store set poisons before staging and rolls back all writes
[ ] one root observes one committed Store snapshot across Regions
[ ] Store-owned Revision and ChangeEpoch follow the clock table
[ ] repeated same-epoch read performs no recompute
[ ] unrelated publication green-verifies a demanded root
[ ] dynamic trace replacement drops old dependencies
[ ] failed recompute preserves last-successful memo without stale fallback
[ ] invocation-level cycles are key-sensitive and clean up
[ ] equivalent cutoff keeps newest value/trace and skips downstream work
[ ] private proof loss rematerializes conservatively
[ ] Region close releases owned heavy payload
[ ] cross-Region tombstone and branch-away behavior pass
[ ] native / JS / wasm-gc pass
[ ] native ownership evidence passes
[ ] negative capability/package probes pass
[ ] no reverse subscribers or global erased memo registry
[ ] no public eviction or debug surface
[ ] no unintended generated-interface drift
[ ] no wall-clock acceptance threshold
```

## Decision record

- **No ADR yet:** K0 records a time-bounded product contract and a blocked
  implementation handoff. Create or update an ADR only after a working K1
  kernel supports a maintainer decision to adopt Incr Next as a sibling
  pre-1.0 product.
