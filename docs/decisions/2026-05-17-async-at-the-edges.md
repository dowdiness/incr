# ADR: Async-at-the-Edges — Framework Compatibility with `moonbitlang/async`

**Date:** 2026-05-17
**Status:** Accepted — no library changes; gated follow-ups recorded
**Anchors:** [moonbitlang/async](https://github.com/moonbitlang/async), [R2 deferred](2026-04-26-r2-runtime-decomposition-deferred.md), [Modal Runtime split — not warranted](2026-04-26-modal-runtime-split-not-warranted.md), [2026-04-20 architecture assessment](../design/specs/2026-04-20-architecture-assessment.md)

## Context

The question came up whether `incr` is "async-ready" for use with the experimental `moonbitlang/async@0.19.0` library — and if not, what structural work it would need. The investigation surfaced two non-obvious findings that have not been written down. This ADR captures them and establishes the supported integration pattern, so future agents/contributors do not propose async-ifying framework internals or build runtime guards that the type system already provides.

The trigger is forward-looking; no driver has adopted `moonbitlang/async` yet. The purpose of this ADR is to *prevent* speculative restructuring, not to commission new work.

## Verified properties of `moonbitlang/async@0.19.0`

Read from the repo's `README.md` + `src/pkg.generated.mbti` on 2026-05-17:

- **Single-threaded cooperative multitasking.** "code without suspension point can always be considered atomic." Scheduling happens only at explicit `await` / `@async.pause()` points. No data races, no locks needed.
- **Function coloring is in the MoonBit type system.** Public APIs use `async fn` and `async () -> X` types throughout (`with_task_group`, `TaskGroup::spawn`, `Task::wait`, `Lazy::wait`, etc.). An `async () -> T` is a distinct type from `() -> T` — neither is assignable where the other is expected.
- **Structured concurrency via `TaskGroup`.** All tasks live in a group scope; group exit guarantees all spawned tasks have terminated. Errors cancel sibling tasks.
- **Cancellation = error at suspend point.** `try`/`catch` handles cancellation uniformly with other errors. No preemption mid-statement.
- **Backends:** native/LLVM Linux/macOS/Windows + JS backend (IO-independent APIs only: `async`, `io`, `aqueue`, `semaphore`, `cond_var`, plus HTTP via fetch). **No wasm-gc backend.**
- **Status: experimental.** Repo `README.md`: "API is subject to future change."

## Verified properties of `incr` (relevant to async compatibility)

Audited against `main @ 7726cff`:

- **Zero `async fn` or `await` in source.** `grep -rn "async fn\|\\bawait\\b" incr/cells/ incr/types/ incr/pipeline/ incr/traits.mbt incr/incr.mbt` returns no hits. The framework never yields.
- **All user-supplied closures are sync.** `Memo::new(rt, f : () -> T)`, `Signal::on_change(f : (T) -> Unit)`, `Runtime::batch(f : () -> Unit)`, `Runtime::batch_result(f : () -> Unit raise?)`, `Accumulator` push-producing memo bodies, `Effect` callbacks, `Rule` apply closures. None are typed as `async`.
- **All `incr/cells/internal/kernel/*.mbt` algorithm bodies are sync.** Verification, propagation, fixpoint, batch commit, gc, dispose — none yield.
- **Primary build target is wasm-gc.** `_build/wasm-gc/` is canonical; native and JS targets exist for the JS-target bench/build chain.

## Finding 1 — MoonBit's function coloring enforces the synchrony contract automatically

The prior architectural concern was that user-supplied closures could `await` mid-execution, leaving framework invariants observably violated by another task:

- `tracking_stack` left in a half-pushed state
- `MemoData.in_progress` set across yield → false cycle detection
- `RuntimeCore.phase` held across yield → another task hits a phase-guard abort
- mid-batch state (`batch.depth`, `batch.pending`, `batch.frames`) visible to other tasks
- `current_revision` bumped by another task mid-recompute
- dispatch-table invariant (`cell_index.len == cell_ops.len == cell_lifecycle.len`) observed mid-update

**All of these are prevented by typing, not by runtime guards.** Because every framework-called closure is typed `() -> T` (not `async () -> T`), a user trying to `await` inside one gets a compile error. The synchrony contract cannot be violated; the entire "Scenario B" (await inside the graph) is structurally impossible.

This was not obvious from the architecture assessment, which framed multi-threaded-async and single-threaded-async as continuous variations. They are not — under cooperative single-threaded async with function coloring, async cannot leak in.

## Finding 2 — incr is structurally compatible with cooperative single-threaded async today

Given Finding 1, every concern in the prior async-readiness analysis dissolves:

| Concern | Status under cooperative async + coloring |
|---|---|
| `tracking_stack` corruption mid-recompute | Safe — recompute closure is sync; no `await` possible inside |
| `MemoData.in_progress` left set across yield | Safe — set/clear bracket sync code |
| Phase machine reentrancy from another task during gc/batch/propagate | Safe — all phase-holding algorithms are sync |
| Mid-batch state visible to another task | Safe — batch closure typed sync |
| `cell_index`/`cell_ops`/`cell_lifecycle` mid-alloc invariant | Safe — allocation is sync |
| `current_revision` bumped by another task mid-recompute | Safe — `Signal::set` and `force_recompute` cannot interleave |
| Module-scope `current_computing_runtime_id : Ref[Int]` (`incr/cells/runtime.mbt:22`) | Safe today — set/cleared inside sync brackets, no task switch possible between them |

Between any two consecutive synchronous incr API calls, no other task can run. Each call is atomic from the scheduler's point of view.

## Decision

1. **No library changes are required to support async-at-the-edges.** The framework's existing sync surface composes cleanly with `moonbitlang/async`'s cooperative model.

2. **Drivers are free to adopt `moonbitlang/async` at any time** on any backend that the async library itself supports (currently native LLVM + the JS-backend subset). The wasm-gc primary target is not affected — async drivers run elsewhere.

3. **Two follow-ups are recorded but stay gated.** Neither is needed for the supported pattern to work; both are robustness improvements that pay off only when a concrete async driver lands.

   - **Integration test on the JS backend** demonstrating the canonical pattern (`with_task_group` + `spawn` + `rt.batch(fn() { sig.set(v) })` + concurrent reads). Makes the synchrony contract executable. Gated on: first canopy/loom driver actually using async.
   - **T3 (`RuntimeRegistry`)** replacing the two file-scope `Ref[Int]`s in `incr/cells/runtime.mbt`. Robustifies multi-runtime + async patterns; today the Refs are correct-by-sync-bracketing discipline. To be written as a separate ADR with its own gate.

## Supported patterns (driver-side, no library code needed)

These compose with the existing framework. Each is a *pattern*, not an API to add.

### Async input sources → signals

```moonbit
with_task_group(fn(g) {
  g.spawn_bg(fn() {
    for {
      let content = await @fs.read_text(path)
      rt.batch(fn() { source_sig.set(content) })
      await @signal.watch(path)
    }
  })
})
```

Drivers: file watcher → reparse; LSP stdin → editor state; HTTP fetch → module import; WebSocket stream → collaboration updates; timer → frame signal.

### Background scheduling

```moonbit
g.spawn_bg(fn() {
  for {
    await @async.sleep(idle_ms)
    rt.gc()
  }
})
```

Also: chunk a large fixpoint with `@async.pause()` between iterations to keep the event loop responsive; defer expensive memo reads with debounce; async-snapshot the graph (Phase 5 persistent caching, when shipped).

### Multi-runtime + task isolation

Each `Runtime` runs in its own task; tasks coordinate via `@aqueue.Queue`. Not parallelism (still single-threaded), but fault-isolated and naturally backpressured.

```moonbit
g.spawn_bg(fn() {
  let bg_rt = Runtime()
  for req in request_q {
    bg_rt.batch(fn() { source.set(req.content) })
    await result_q.put(typed.get())
  }
})
```

### Effect-side async via channels

```moonbit
let log_q : Queue[LogEntry] = Queue::new()
let _ = Effect::new(rt, fn() { log_q.put_nowait({ msg: status.get() }) })
g.spawn_bg(fn() { for entry in log_q { await @fs.append_log(entry) } })
```

The `Effect` closure stays sync; the consumer drains async.

### Cancellation as graph control

`@async.with_timeout(500, fn() { ... drive_pipeline() })` cancels the task on timeout. Because each sync `set`/`get` pair runs atomically, cancellation leaves the runtime in a consistent state — no half-applied edits, no stuck phase.

## Non-goals (out of scope for this ADR and for the framework)

- **Async inside the dependency graph.** Compute closures, callbacks, batch closures, and `Rule` apply closures stay sync. This is enforced by typing, by design.
- **Async compute closures via wrapping.** Do not add helpers that take `async () -> T` and "drive" them internally. Such a helper would have undefined semantics under verification (what does `verified_at` mean across a suspension?) and would defeat the type-level guarantee.
- **Compute parallelism.** `moonbitlang/async` is single-threaded. Multiple memos still recompute serially. Parallel evaluation remains a Phase 5 question with no current design.
- **`async` API surface on `Signal`/`Memo`/`Runtime`.** Public API stays sync. Drivers that need an `async` wrapper write a thin facade in their own crate.
- **wasm-gc backend for async.** `moonbitlang/async` does not currently support wasm-gc. Re-evaluate this ADR if that changes.
- **Internal `await`.** No `incr/cells/*.mbt` or `incr/cells/internal/**/*.mbt` file may introduce `await`. Any such change requires reopening this ADR.

## Verification

Three invariants to preserve. All are checkable today by grep.

| Invariant | Check |
|---|---|
| Framework never yields | `grep -rn "async fn\|\\bawait\\b" incr/cells/ incr/types/ incr/pipeline/ incr/traits.mbt incr/incr.mbt` returns no hits |
| All user-supplied closures are sync | `grep -rn "fn.*async.*->\|: async " incr/cells/ incr/types/ incr/traits.mbt incr/incr.mbt` returns no hits in non-test code |
| Public `.mbti` interfaces declare no `async` | `grep -rn "async fn\|async (" *.mbti incr/cells/*.mbti` returns no hits |

These can be added to `scripts/` as a CI guard if desired; not commissioned now (no driver, no failure history).

## Risks and re-evaluation triggers

- **MoonBit changes its async model** (e.g., adds preemption, removes function coloring, allows `await` in sync contexts). Today's analysis depends on three properties of MoonBit + `moonbitlang/async`: function coloring is enforced, scheduling is cooperative, single OS thread. Reopen this ADR if any changes.
- **`moonbitlang/async` adopts wasm-gc.** Current platform constraint forces drivers off wasm-gc. If async ships on wasm-gc, the JS-backend-subset constraint relaxes; document the new target matrix.
- **A driver requests internal `await`.** This will happen only if a use case wants suspension inside the graph (e.g., async-fetched memo deps). Treat as a fundamentally different incrementality model; do not retrofit, design a separate cell type.
- **Multi-runtime async patterns produce a test failure.** The Ref-based identity is correct by sync-bracketing discipline. A future internal refactor could break that invariant silently. The gated T3 ADR is the answer; commission when the failure appears or when a multi-runtime async driver lands.

## Trade-offs accepted

- **Defer the JS-backend integration test until a driver exists.** Cost: no executable proof of the contract until then. Benefit: the test isn't load-bearing without a consumer, and adding it now would introduce a JS-target maintenance burden (different build chain) for no current user.
- **Defer T3 until a multi-runtime async driver exists.** Cost: the Refs remain a discipline invariant. Benefit: no correctness risk on a load-bearing path absent a regression net.
- **Document the synchrony contract here, not in user-facing docs.** Cost: drivers learning incr from `docs/getting-started.mbt.md` won't see the async story. Benefit: avoids over-promising on an experimental dependency. Promote to user docs when a driver actually ships.

## Scope

**In scope:** the question of whether incr requires structural changes to compose with `moonbitlang/async`. Answer: no.

**Out of scope:**
- Async drivers on the canopy / loom side — owned by those projects.
- The contents of `docs/getting-started.mbt.md` / `cookbook.mbt.md` — async patterns are not yet user-facing recipes.
- Phase 5 persistent caching design — the async-write pattern is one *enabler* of it, not a substitute for the persistence design itself.
- The T1b (`MemoCommitPhase`) gating decision — separate concern, separate ADR, not unlocked by async.

## What this ADR retires

- The implicit framing in earlier discussions that adopting `moonbitlang/async` would require a multi-stage structural migration of `Runtime` and the engines. It does not. The relevant gates are listed above and are far smaller in scope.
- Any future proposal to add a runtime guard ("assert tracking stack empty at suspend points," "abort if phase non-Idle at task switch") to enforce the synchrony contract. Function coloring already enforces it statically.
