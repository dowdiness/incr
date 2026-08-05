# Incr DX / Retention Architecture Design Handoff

**Date:** 2026-08-05

**Reader:** The next design session continuing the Incr retention redesign
exploration; readers needing the session history behind the companion
proposal and decision record.

**Decision:** Preserve as a session-state snapshot. The "Current proposed
interface" and "Blocking design findings" sections below are superseded as
current state by the
[first-principles decision record](2026-08-05-retention-redesign-first-principles-decisions.md);
read this handoff for provenance, user decisions, and worktree cautions only.

**Keep until:** The redesign track is commissioned or rejected and the
decision record plus ADR(s) fully absorb this content.

**Disposition:** Session history. Delete once the track is resolved and the
durable ADR(s) exist; Git history is the recovery path.

**Provenance:** Moved verbatim from `/tmp/incr-retention-design-handoff-2026-08-05.md`
(original SHA-256:
`6ea9c555e8a4c3fc2ff72595fa63b922a4af3da6af78d0f9f659d34dd98341e7`); this
header was added and `/tmp` path references below were repointed at
repository paths. All SHA-256 references in the body apply to the pre-move
`/tmp` copies; the repository versions carry the provenance headers above
their original bodies. Written in English with Japanese context; no
translation needed.

**Related documents:**
[retention API redesign proposal](2026-08-05-retention-api-redesign-proposal.md),
[first-principles decision record](2026-08-05-retention-redesign-first-principles-decisions.md)

---

> Goal: continue the Incr interface and retention-architecture design session without relying on the prior conversation, while keeping it separate from the active Canopy #1145 implementation.

Date: 2026-08-05 (Asia/Tokyo)

## Session outcome

This session produced and reviewed a standalone design proposal for a new Incr interface and retention architecture.

Primary design artifact:

- [2026-08-05-retention-api-redesign-proposal.md](2026-08-05-retention-api-redesign-proposal.md)
  (formerly `/tmp/incr-retention-api-design.md`)
- 824 lines (pre-move)
- SHA-256 of the pre-move `/tmp` copy: `6bdc66acb0ff98dc6f1f04535b732295ffb83cb44b956bb13691f2b0a750e609`

The design artifact was updated during the session to use:

- current MoonBit custom-constructor syntax: `Store()` backed by `fn Store::Store() -> Store`
- `effect` instead of `observe` as the primary name for a tracked external side effect

No repository file was changed by this design side conversation.

## Established user preferences and decisions

Treat the following as explicit user direction rather than open naming questions:

1. Do not use the name `Signal`.
2. Separate read and write capabilities in the style:

   ```moonbit
   let (source, set_source) = store.input("")
   ```

3. Do not expose graph-implementation vocabulary such as `Graph` or `Node` in the ordinary caller interface.
4. Reconsider Incr's retention architecture from first principles; do not merely add a `Lifetime::expose()` facade over the existing model.
5. Use current MoonBit custom constructors, not `Type::new()`.
6. Prefer `effect` over `observe` for the core operation that executes an external action, tracks getter use, and re-executes on change.
7. The intended direction is that passive values require no manual disposal; only active effects, subscriptions, I/O, and adapters have cleanup.

## Current proposed interface

The current document proposes the following shape:

```moonbit
let store = Store()

let (source, set_source) = store.input("")

let document = store.view(() => {
  parse_markdown(source())
})

let stop = store.effect(() => {
  patch_dom(document())
})

set_source("# Hello")
stop()
```

Conceptually:

```moonbit
type View[T] = () -> T raise ReadError
type Set[T] = (T) -> Unit
type Stop = () -> Unit
```

This interface is intentionally small, but the review concluded that the function-alias representation of `View` is still an unresolved design choice rather than an accepted result.

## What is accepted

The following parts survived review:

- Read/write capability separation is valuable and should remain.
- `Store` can be a deep in-process module that hides dependency tracking, revisions, batching, scheduling, and active-effect bookkeeping.
- `Graph`, `Node`, `Watch`, root counts, and Scope should not appear in the ordinary product-facing interface.
- Passive values and active resources need different lifetime semantics.
- `effect` is a better primary name than `observe` when the callback performs an external action and tracks arbitrary getter calls.
- UI adapters such as Rabbita should own effect cancellation and expose a UI-specific seam such as `bind`.
- Runtime-wide GC should not be required for ordinary read correctness.
- The design should preserve lazy evaluation, equality cutoff, dynamic dependencies, and at-most-once successful recomputation per revision.

## Blocking design findings

### 1. Transparent function aliases cannot enforce View invariants

The document currently defines:

```moonbit
type View[T] = () -> T raise ReadError
```

Any arbitrary function can therefore be treated as a View, including one with I/O or side effects. The type cannot distinguish:

- a memoized Store-created view
- an Input getter
- a raw recomputing closure
- a closure with side effects
- a closure originating from another Store

This conflicts with the document's invariant that getters perform no I/O or callbacks and makes performance properties invisible in the interface.

MoonBit currently has no overloadable call operator for an opaque custom type. The next session must make an explicit choice:

- **Syntax-first:** keep callable function getters and accept convention/runtime validation.
- **Nominality-first:** use an opaque `View[T]` and an explicit observation operation such as `view.get()` or a free function.
- **Two-layer:** keep the Incr module interface opaque, while product modules expose ordinary getter closures locally.

The previous review favored investigating the two-layer option.

### 2. Ordinary closures do not release inactive branches

This example:

```moonbit
let preview = store.view(() => {
  match mode() {
    Raw => raw_preview()
    Block => block_preview()
    Preview => markdown_preview()
  }
})
```

lexically captures all three branch getter closures. Removing an inactive getter from the reactive dependency array does not remove the compute closure's RC reference to it.

Therefore these are distinct claims:

- inactive branch is no longer a reactive dependency
- inactive branch is released by RC

The first is supported by dynamic dependency tracking. The second is false for the example above.

True branch release requires a dedicated lazy factory / switch combinator that owns only the active branch and tears it down on a switch.

### 3. Error ownership is unresolved

Using `ReadError` for every View conflates:

- graph cycles and engine errors
- domain errors such as parse/validation failures
- DOM or I/O adapter failures
- programmer defects

Current Incr already has a deliberate pattern where recoverable domain failure is cached as `Result[V, E]`, while graph-mechanism errors remain separate. Preserve or consciously replace that distinction.

Candidate directions:

- infallible getter plus `View[Result[V, E]]` for domain failures
- opaque View whose materialization returns `Result[T, ReadError]`
- another explicit error-channel design justified by catch sites

Do not use a bare or catch-all error merely to keep the interface short.

### 4. Effect semantics are not yet an interface

The signature is small, but callers still need answers for:

- whether initial execution is synchronous
- behavior when the initial run raises
- behavior when a later run raises
- whether setters are allowed during an effect
- batching and glitch-freedom
- effect ordering
- reentrancy
- cancellation during execution
- whether cleanup runs before re-execution
- idempotence of the returned stop function

A conservative candidate contract was proposed:

- run synchronously once at registration
- track getters used during that run
- schedule at most one rerun after a batch
- defer setters called inside an effect to a later dispatch cycle
- make stop idempotent
- keep the core effect callback `noraise` where possible; let adapters own error quarantine

This is not yet accepted; it needs scenario tests.

### 5. Pull-only passive verification needs measurement

The proposal removes passive reverse edges and verifies the dependency closure after Store revisions. This is retention-friendly but can make unrelated writes cause O(reachable dependency closure) verification on the next read.

Do not call this tradeoff acceptable until measuring at least:

- chain
- diamond
- many independent roots
- one frequently changing Input plus many unrelated Inputs
- 2500-block Markdown document
- rapid getter creation/drop churn

Use release builds and compare against the current Incr semantic oracle and baseline.

### 6. Phase 2 is a kernel replacement, not a local refactor

Moving state out of Runtime's CellId arena and removing passive reverse subscribers affects more than Input and Derived. Current Incr also has push cells, effects, reachable/eager derived values, DerivedMap, accumulators, datalog, durability, evaluation hooks, cycle paths, batching, and dynamic dependency diffing.

A future plan needs a semantic parity matrix and differential oracle before replacing the kernel.

### 7. Secondary unresolved items

- `Store::view[T : Eq]` excludes non-Eq values; consider `view_by(compute, equal)` rather than multiplying interfaces.
- `(T) -> Unit` does not provide atomic read-modify-write; specify the concurrency/reentrancy model or add a separately justified capability.
- `batch` is notification/revision batching unless rollback is explicitly implemented; do not imply transactionality.
- At-most-once recomputation should be stated as at-most-once **successful** recomputation per revision unless failures are cached as values.
- Cross-Store reads need a concrete error contract and deterministic detection.

## Relevant references

### Design artifacts

- Full proposal: [2026-08-05-retention-api-redesign-proposal.md](2026-08-05-retention-api-redesign-proposal.md)
- This handoff: [2026-08-05-retention-redesign-session-handoff.md](2026-08-05-retention-redesign-session-handoff.md)
- (Added 2026-08-05 after this handoff) Decision record: [2026-08-05-retention-redesign-first-principles-decisions.md](2026-08-05-retention-redesign-first-principles-decisions.md)

### External primary sources consulted

- Jotai repository: https://github.com/pmndrs/jotai
- Jotai core internals: https://github.com/pmndrs/jotai/blob/main/docs/guides/core-internals.mdx
- Jotai atom lifecycle: https://github.com/pmndrs/jotai/blob/main/docs/core/atom.mdx
- Duplix repository: https://github.com/Yoorkin/duplix
- Duplix core implementation: https://github.com/Yoorkin/duplix/blob/main/duplix.mbt
- MoonBit custom constructors: https://docs.moonbitlang.com/en/latest/language/fundamentals.html#custom-constructors
- MoonBit operator overloading: https://docs.moonbitlang.com/en/latest/language/methods.html#operator-overloading

### Existing Incr code inspected

The review inspected the current Incr dependency under the #1145 worktree, including:

- `.worktrees/issue-1145-markdown-ir-preview/.mooncakes/dowdiness/incr/cells/runtime.mbt`
- `.worktrees/issue-1145-markdown-ir-preview/.mooncakes/dowdiness/incr/cells/derived_facade.mbt`
- `.worktrees/issue-1145-markdown-ir-preview/.mooncakes/dowdiness/incr/cells/derived_impl.mbt`
- `.worktrees/issue-1145-markdown-ir-preview/.mooncakes/dowdiness/incr/cells/scope.mbt`
- `.worktrees/issue-1145-markdown-ir-preview/.mooncakes/dowdiness/incr/cells/watch.mbt`
- `.worktrees/issue-1145-markdown-ir-preview/.mooncakes/dowdiness/incr/cells/internal/kernel/state.mbt`
- `.worktrees/issue-1145-markdown-ir-preview/.mooncakes/dowdiness/incr/cells/tracking.mbt`

Prefer the authoritative dependency source over generated `.mooncakes` copies when proposing changes. Use the copies only to reproduce the exact reviewed behavior.

## Completed, uncommitted, and blocked work

### Completed

- Compared the current Incr lifetime model with Jotai and Duplix.
- Chose read/write capability separation as the interface direction.
- Rejected `Signal` and public graph-structure naming.
- Replaced `observe` with `effect` in the proposal.
- Replaced `Store::new()` with the current custom constructor `Store()`.
- Wrote a consolidated 824-line proposal.
- Performed a critical internal review and recorded the blocking findings above.

### Uncommitted / ephemeral

- ~~`/tmp/incr-retention-api-design.md`~~
- ~~`/tmp/incr-retention-design-handoff-2026-08-05.md`~~

Resolved 2026-08-05: all three session artifacts (proposal, this handoff,
and the later decision record) were moved into the `incr` repository under
`docs/research/` and indexed in `docs/README.md`. They remain uncommitted
pending maintainer review.

### Blocked or not performed

- No qwen3.8-max / pi CLI external review was run in this side conversation.
- No prototype was implemented.
- No benchmark was run.
- No GitHub issue, ADR, or durable repository design document was created.
- No final decision was made on callable function getters versus opaque Views.

## Repository and worktree caution

At handoff time:

- repository root: `/home/antisatori/ghq/github.com/dowdiness/canopy`
- root branch: `main`
- root has an existing modified `deps/loom` submodule state that this design session did not create and must not revert
- active implementation worktree: `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/issue-1145-markdown-ir-preview`
- worktree branch: `feat/1145-markdown-ir-preview`
- the worktree contains many uncommitted #1145 implementation files

Do not edit, reset, clean, commit, or otherwise alter either dirty state as part of this design handoff unless the user explicitly expands scope.

## Don't conflate with

The Incr retention design discussion was triggered by a lifetime problem discovered while implementing Canopy GitHub Issue #1145, where a Markdown semantic attachment's collection exposed unrooted SyncEditor derived values.

However:

- this design proposal is a possible future Incr redesign
- the active #1145 implementation needs a scoped, reviewable solution now
- do not silently turn #1145 into an Incr kernel rewrite
- do not modify the active #1145 worktree merely to prototype this design

Keep product delivery and architecture exploration in separate worktrees or repositories if implementation is later authorized.

## Suggested skills

- `codebase-design` — evaluate module depth, interface knowledge, and seam placement
- `moonbit` router
- `moonbit-traits` — opaque/newtype and capability representation constraints
- `moonbit-error-handling` — separate graph, domain, adapter, and defect errors
- `moonbit-perf-investigation` — required before accepting pull-only performance claims
- `prototype` — build a throwaway design probe rather than modifying production Incr
- `tdd` — once observable contracts are agreed

Do not use subagents merely to multiply opinions. If the user explicitly requests an external review, give the reviewer the proposal plus this handoff and ask for evidence-backed challenges against the blocking findings.

## Recommended first decision-producing step

Do not begin with the full retention kernel.

Create or reason through three minimal interface alternatives against the same scenarios:

1. transparent callable getter `() -> T`
2. opaque `View[T]` with explicit materialization
3. two-layer design: opaque Incr interface plus product-local getter closure

For each alternative, evaluate:

- whether arbitrary callers can violate getter purity
- Store provenance and cross-Store detection
- graph error versus domain error ownership
- labels and diagnostics
- performance transparency
- UI adapter ergonomics
- dynamic branch retention under RC

Choose an interface only after this comparison. Then build an isolated prototype for the winning interface without editing the active #1145 worktree.

## Complete next-session prompt

```text
Continue the Incr DX / retention-architecture design session.

Context (verify before acting):
- Read docs/research/2026-08-05-retention-redesign-session-handoff.md in the `incr` repository completely.
- Read docs/research/2026-08-05-retention-api-redesign-proposal.md completely. The SHA-256 6bdc66acb0ff98dc6f1f04535b732295ffb83cb44b956bb13691f2b0a750e609 applies to the pre-move `/tmp` copy; the repository version adds a provenance header above the same body. If the body differs, report the delta before relying on the handoff.
- Read docs/research/2026-08-05-retention-redesign-first-principles-decisions.md; it supersedes the blocking findings below as current state.
- Explicit user decisions: do not use Signal; split input into read and write capabilities; do not expose Graph/Node vocabulary to ordinary callers; use current MoonBit custom constructors; prefer effect over observe.
- The current proposal is accepted only as an interface exploration. The retention kernel is not implementation-ready.

Background:
- Jotai: https://github.com/pmndrs/jotai
- Duplix: https://github.com/Yoorkin/duplix
- MoonBit custom constructors: https://docs.moonbitlang.com/en/latest/language/fundamentals.html#custom-constructors
- MoonBit operator overloading: https://docs.moonbitlang.com/en/latest/language/methods.html#operator-overloading

Don't conflate with:
- Canopy #1145 implementation is active in /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/issue-1145-markdown-ir-preview and has uncommitted changes.
- The repository root also has a dirty deps/loom submodule state.
- Do not edit, reset, clean, commit, or reuse either dirty worktree for this design exploration without explicit user authorization.
- Do not expand #1145 into an Incr kernel rewrite.

First step:
- Compare three interface alternatives: callable getter, opaque View, and a two-layer design.
- Test each conceptually against purity, provenance, errors, diagnostics, performance transparency, UI ergonomics, and RC branch retention.
- Pay special attention to the fact that ordinary closures lexically capture inactive branch getters, so dynamic dependency removal does not imply RC release.
- Present a recommendation and explicit rejected alternatives. Do not implement production code yet.

Discipline:
- Use codebase-design vocabulary: module, interface, seam, adapter, depth, leverage, locality.
- Route MoonBit type/error questions through moonbit-traits and moonbit-error-handling.
- Do not claim pull-only performance is acceptable without release benchmarks under moonbit-perf-investigation.
- Treat recoverable domain errors as values or concrete typed errors chosen by catch site; do not collapse them into ReadError for convenience.
- Preserve Functional Core / Imperative Shell: dependency decisions and state transitions deterministic; effects and scheduling in the shell.
```

## Retrospective

- Outcome: **good** — produced a self-contained proposal and found several architecture-blocking contradictions before implementation.
- Process fit: **acceptable** — the exploration was long, but the topic was a kernel-level redesign and the resulting artifact consolidates it.
- Token economy: **acceptable** — external primary-source research and local-source inspection were necessary; the final proposal contains some duplication that should be edited before becoming durable.
- Decision validation: **good** — compared Jotai, Duplix, current MoonBit language rules, and current Incr implementation.
- User alignment: **good** — incorporated explicit corrections on naming, capability separation, scrolling/readability, and custom constructors.
- Recoverability: **acceptable** — the handoff is self-contained, but both artifacts are temporary rather than durable.

No durable skill/configuration edit is proposed from this session.

## Clearance readiness

### Required

- ~~This handoff and the proposal must remain accessible, or be copied into a durable repository/design location in a later authorized session.~~ Done 2026-08-05: moved into `docs/research/` of the `incr` repository.

### Optional

- Intermediate Context7, GitHub API, and source-inspection outputs; their conclusions are captured here.

### Redundant

- Repeated short UI-workaround messages and intermediate wording iterations.

### Compressible

- The full prior conversation; its decisions and blockers are captured in the two `/tmp` artifacts.

Verdict: **safe to transfer to another agent on this machine now; not safe against reboot or `/tmp` cleanup.** Move the artifacts into a durable, user-approved location before relying on them long term.
