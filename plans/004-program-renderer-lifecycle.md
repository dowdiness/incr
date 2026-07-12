# Plan 004: Make shared Program mount ownership and scheduler teardown global

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `rtk git diff --stat 31afb08..HEAD -- incr_tea/program.mbt incr_tea/renderer_js.mbt incr_tea/scheduler_wbtest.mbt incr_tea/renderer_wbtest.mbt incr_tea/lifecycle_wbtest.mbt incr_tea/pkg.generated.mbti incr_tea/README.mbt.md CHANGELOG.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/003-controlled-dom-reconciliation.md` (execution-order dependency because both modify `incr_tea/renderer_js.mbt`; no semantic dependency)
- **Category**: bug
- **Planned at**: commit `31afb08`, 2026-07-13

## Why this matters

A `Program` may be mounted more than once, but ownership is currently counted only inside each `BrowserRenderer`. Destroying the last local root in renderer A can therefore dispose a program still mounted through renderer B. Each mount also appends an after-flush scheduler closure that can never be removed, and `Program::dispose` leaves queued messages/callbacks and those closures retained. This plan makes mount registration program-owned across renderer instances, gives every root an idempotently removable scheduler handle, and makes disposal release pending work without changing the public multi-mount API or detached-root semantics.

## Current state

- `incr_tea/program.mbt` — the program owns two queues and an append-only array of scheduler closures (lines 8–19, initialized at lines 46–58 and 88–100):

  ```moonbit
  pub struct Program[Msg, View] {
    priv runtime : @incr.Runtime
    priv scope : @incr.Scope
    priv update : (Msg) -> Cmd[Msg]
    priv messages : @queue.Queue[Msg]
    priv after_flush : @queue.Queue[((Cmd[Msg]) -> Unit) -> Unit]
    priv after_flush_schedulers : Array[() -> Unit]
    priv mut is_draining : Bool
    // ...watches, subscriptions, view id...
  }
  ```

- `incr_tea/program.mbt` — a mount can add but never remove a scheduler; every pending `AfterFlush` fans out to all closures ever registered (lines 145–178):

  ```moonbit
  AfterFlush(callback) => {
    self.after_flush.push(callback)
    self.request_after_flush()
  }

  fn[Msg, View] Program::add_after_flush_scheduler(
    self : Program[Msg, View],
    schedule : () -> Unit,
  ) -> Unit {
    self.after_flush_schedulers.push(schedule)
  }

  fn[Msg, View] Program::request_after_flush(self : Program[Msg, View]) -> Unit {
    for schedule in self.after_flush_schedulers {
      schedule()
    }
  }
  ```

- `incr_tea/program.mbt` — disposal only tears down subscriptions and the scope, leaving queue elements and scheduler closures reachable (current `Program::dispose`):

  ```moonbit
  pub fn[Msg, View] Program::dispose(self : Program[Msg, View]) -> Unit {
    match self.sub_manager {
      Some(manager) => manager.dispose()
      None => ()
    }
    self.scope.dispose()
  }
  ```

- `incr_tea/renderer_js.mbt` — each mount adds an unremovable closure before creating the root (lines 1384–1425):

  ```moonbit
  let view_id = program.view_id()
  program.add_after_flush_scheduler(() => self.schedule_flush())
  // ...renderer-local instrumentation bookkeeping...
  let root = BrowserRoot::BrowserRoot(program, host, root_stats, /* ... */)
  self.roots.push(root)
  ```

- `incr_tea/renderer_js.mbt` — the last-reference test sees only one renderer's mounted and detached buckets (lines 1546–1558):

  ```moonbit
  fn[Msg] BrowserRenderer::references_program(
    self : BrowserRenderer[Msg],
    view_id : @incr.CellId,
  ) -> Bool {
    self.roots.iter().any(other => other.view_id() == view_id) ||
    self.detached.iter().any(other => other.view_id() == view_id)
  }
  ```

- `incr_tea/renderer_js.mbt` — `destroy` disposes when no *local* sibling remains (lines 1699–1727):

  ```moonbit
  self.remove_root(root)
  // ...local stats bookkeeping...
  let view_id = root.view_id()
  if !self.references_program(view_id) {
    root.dispose_program()
    self.view_ids.val = self.view_ids.val.filter(id => id != view_id)
  }
  ```

- `incr_tea/renderer_js.mbt:1660-1695` defines detached roots as parked-but-alive and still renderer-owned. A detach must retain the global mount registration and scheduler; reattach must reuse that same registration rather than registering again.
- `incr_tea/renderer_wbtest.mbt:1174-1459` is the lifecycle test cluster. It covers last-root disposal inside one renderer, detached roots, foreign-root rejection, and shared mounts in one renderer, but not one program mounted through two renderer instances.
- `incr_tea/scheduler_wbtest.mbt:252-329` is the pattern for pending `Cmd::after_flush` callbacks and follow-up messages.
- `incr_tea/lifecycle_wbtest.mbt:1-65` is the pattern for verifying scope/watch/cell release and idempotent disposal.
- Repository conventions: private white-box state belongs in `*_wbtest.mbt`; public items require `///`; generated `.mbti` files come only from `moon info`. Recent commits use conventional prefixes (`fix:`, `feat:`, `chore:`).
- Architecture constraint from `AGENTS.md`: make mount-release decisions through a deterministic state transition, then let the mutable `Program`/renderer façade perform scheduler invocation, DOM teardown, listener removal, and scope disposal. Do not expose mutable registration arrays.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Renderer lifecycle tests | `rtk moon test incr_tea -f renderer_wbtest.mbt --target js` | exit 0; all renderer white-box tests pass |
| Scheduler tests | `rtk moon test incr_tea -f scheduler_wbtest.mbt --target js` | exit 0; all scheduler tests pass |
| Lifecycle tests | `rtk moon test incr_tea -f lifecycle_wbtest.mbt --target js` | exit 0; all lifecycle white-box tests pass |
| Format | `rtk moon fmt` | exit 0; MoonBit sources are formatted |
| Regenerate interfaces | `rtk moon info` | exit 0; generated interfaces refresh |
| Check | `rtk moon check` | exit 0; no diagnostics |
| Package tests | `rtk moon test incr_tea --target js` | exit 0; all `incr_tea` tests pass |
| Browser integration | `rtk npm --prefix examples/incr_tea run test:dom` | exit 0; renderer integration remains green |
| Full tests | `rtk moon test` | exit 0; full workspace suite passes |
| Interface drift | `rtk git diff --exit-code -- incr_tea/pkg.generated.mbti` | exit 0; no public API diff is expected |

## Suggested executor toolkit

- Invoke the `moonbit` and `moonbit-verification` skills if available; this change crosses generic program state, JS renderer ownership, queues, and white-box tests.
- Use `incr_tea/renderer_wbtest.mbt:1174-1459` for teardown structure and `incr_tea/scheduler_wbtest.mbt:252-329` for command-queue structure.

## Scope

**In scope** (the only files you should modify):

- `incr_tea/program.mbt` — private global mount registry, removable scheduler registrations, and disposal cleanup.
- `incr_tea/renderer_js.mbt` — root registration ownership and renderer teardown wiring.
- `incr_tea/renderer_wbtest.mbt` — two-renderer, detached-root, ordering, and unregister tests.
- `incr_tea/scheduler_wbtest.mbt` — pending queue/callback release and reentrant disposal tests.
- `incr_tea/lifecycle_wbtest.mbt` — disposal retention/idempotence assertions if they fit better here than scheduler tests.
- `incr_tea/pkg.generated.mbti` — only if regenerated by `rtk moon info`; no diff is expected.
- `incr_tea/README.mbt.md` — clarify shared-program mount ownership and destroy/dispose semantics.
- `CHANGELOG.md` — add a concise Unreleased bug-fix entry.
- `plans/README.md` — status-row update only.

**Out of scope** (do NOT touch, even though they look related):

- Making `Program` single-renderer-only or rejecting a second renderer mount; existing multi-mount behavior is intentional and already tested within one renderer.
- Changing detach into logical teardown. A detached root remains alive, registered, schedulable, and eligible for reattach until destroy/dispose.
- Subscription reconciliation, animation-frame cancellation, controlled DOM reconciliation, renderer stats semantics, or derived-event/on-change listener APIs.
- Adding a runtime-global registry. The registry belongs to the shared `Program` object; the runtime need not know browser mounts.
- Public signatures for `Program`, `BrowserRenderer`, `BrowserRoot`, `mount`, `detach`, `reattach`, `destroy`, or `dispose`.
- Exposing registration arrays, scheduler closures, or mutable queues through public APIs.

## Git workflow

- Branch: `advisor/004-program-renderer-lifecycle`
- Commit logical units with conventional commits. Recommended final commit: `fix(incr_tea): make program mount teardown global`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add failing cross-renderer and retention regressions

Add a test-only helper in `incr_tea/renderer_wbtest.mbt` that creates a fresh host from the already-installed fake document. Use real `BrowserRenderer::mount` wherever possible; update manual-root tests only when the new registration contract lands in Step 3.

Add tests for these exact state sequences:

1. Mount one `Program` into renderer A and renderer B. Destroy A's root; assert the program remains undisposed, B's root remains mounted, dispatch succeeds, and B flushes the changed view. Destroy B's root; assert the program is then disposed.
2. Repeat with `renderer_a.dispose()` instead of `destroy(root_a)` and prove B remains operational. Dispose B last and prove final disposal is idempotent.
3. Mount in both renderers, detach B's root, then destroy/dispose A. Assert B's parked root keeps the program alive; reattach B and prove it catches up; destroying B finally disposes.
4. Use a stable view whose update returns `Cmd::after_flush` without mutating tracked state. With two mounts, destroy A, dispatch once, and assert only one animation frame is requested. After B is destroyed, assert no scheduler registration remains and the callback queue is released.

In `incr_tea/scheduler_wbtest.mbt`, add a disposal test that places both pending messages and pending after-flush callbacks in the program, disposes it, and verifies neither executes afterward. Prefer an observable sequence using a batched follow-up where possible; white-box queue lengths are acceptable in this package to prove retained callbacks are gone. Add a reentrant case in which update/command processing disposes the program while follow-up messages are queued; later messages must not execute and `is_draining` must settle to false.

Run the new tests against current code and record the failures: renderer A incorrectly disposes the program, two scheduler closures remain after one root is destroyed, and disposal leaves queued entries retained. Do not change existing one-renderer expectations.

**Verify**: `rtk moon test incr_tea -f renderer_wbtest.mbt --target js` → exits nonzero only in the new cross-renderer/scheduler-registration assertions; existing lifecycle cases pass.

**Verify**: `rtk moon test incr_tea -f scheduler_wbtest.mbt --target js` → exits nonzero only in the new queue-release assertions.

### Step 2: Define a program-owned mount transition and removable handle

In `incr_tea/program.mbt`, introduce private closure-free registration identity (a monotonically increasing integer/newtype is sufficient) and private registration entries that pair the identity with the scheduler capability. Store all active renderer-root registrations on the `Program`, not on a `Runtime` or individual renderer.

Keep the decision core deterministic: add a private helper shaped like `registrations + release_id -> (next_registrations, found, last_released)`. It must not invoke schedulers or dispose scopes. Test duplicate/unknown release and last-release decisions directly in a white-box test if the helper is nontrivial. The `Program` façade then provides private shell methods with these semantics:

- register one mount/scheduler and return its unique handle;
- remove exactly that handle idempotently;
- report/act on whether the final active mount was released;
- request after-flush by snapshotting or iterating only currently registered scheduler entries.

Recommended contract: releasing the final active mount disposes the program; releasing any earlier mount only removes that scheduler. An explicit `Program::dispose` invalidates/clears all registrations. This preserves automatic last-root teardown while making "last" global across all renderers.

Do not silently switch to single-renderer ownership. Do not compare closures for identity. Do not key only by `view_id`, because multiple roots legitimately share one program/view id and each needs a distinct removable scheduler registration.

**Verify**: `rtk moon test incr_tea -f scheduler_wbtest.mbt --target js` → private registration transition tests pass; existing command-order and after-flush tests pass.

**Verify**: `rtk moon check` → exit 0; all registration types/methods remain private.

### Step 3: Make each BrowserRoot own and release exactly one registration

In `incr_tea/renderer_js.mbt`, make every successfully mounted `BrowserRoot` retain the handle returned by `Program` registration. Registration occurs exactly once during `BrowserRenderer::mount`; detach/reattach/deactivate/activate do not add or remove it. Root teardown releases it exactly once, even when `destroy` and renderer `dispose` are repeated or the program was explicitly disposed first.

Replace renderer-local program-disposal decisions with the program-owned release operation:

- `BrowserRenderer::destroy` still validates physical root ownership, detaches DOM, preserves stats, removes local label/instrumentation data, and removes the root from local arrays; then the root releases its mount handle.
- `BrowserRenderer::references_program` may remain only for renderer-local `view_ids` instrumentation cleanup. It must no longer decide whether the shared program is disposed.
- `BrowserRenderer::dispose` snapshots mounted and parked roots as today, removes runtime listeners atomically first, and destroys every local root; each release contributes to the program-global count. A root in another renderer keeps the program alive.
- `BrowserRoot::destroy` and any replacement for `dispose_program` must be idempotent. Store the handle as optional/mutable and clear it before or atomically with release so reentrant teardown cannot release twice.

Several current white-box tests construct `BrowserRoot` directly and push it into renderer arrays, bypassing `mount`. Replace that repeated setup with one private test helper that registers a no-op scheduler through the same root-construction path. Do not allow unregistered production roots as a compatibility escape hatch.

**Verify**: `rtk moon test incr_tea -f renderer_wbtest.mbt --target js` → exit 0; all new two-renderer/detached/order tests and existing #209/#268/shared-program tests pass.

**Verify**: `rtk moon test incr_tea -f lifecycle_wbtest.mbt --target js` → exit 0; scope/watch/cell cleanup and idempotence remain green.

### Step 4: Clear schedulers and pending work during explicit or final disposal

Strengthen `Program::dispose` in `incr_tea/program.mbt` so disposal, including final-mount release, performs all cleanup idempotently:

1. invalidate and clear all active mount/scheduler registrations before scope disposal so retained renderer closures are released;
2. discard every queued message and after-flush callback without invoking it (pop until empty if the core queue has no verified clear operation);
3. dispose the subscription manager and scope as today;
4. ensure reentrant disposal during message draining leaves `is_draining` false when the outer drain returns and cannot execute messages queued before disposal;
5. preserve current post-dispose behavior: `dispatch` returns false, reads return `None`, repeated dispose/release calls are no-ops.

Do not run after-flush callbacks as cleanup; they are application effects that must be abandoned once their owner is disposed. Do not invoke stale scheduler closures during disposal.

**Verify**: `rtk moon test incr_tea -f scheduler_wbtest.mbt --target js` → exit 0; pending callbacks/messages are released and never execute, reentrant drain settles, and existing order/atomicity tests pass.

**Verify**: `rtk moon test incr_tea -f renderer_wbtest.mbt --target js` → exit 0; after one root is removed only live renderer schedulers run, final release disposes, and teardown is idempotent.

### Step 5: Document the ownership contract and run all gates

Update `incr_tea/README.mbt.md` to state:

- a program may be mounted into multiple roots and multiple renderer instances on the same runtime;
- each mounted or detached root keeps one registration alive;
- detach preserves ownership, while destroy/renderer dispose releases it;
- the final global release disposes the program;
- explicit program disposal abandons pending commands and makes remaining roots inert until their renderer teardown.

Add an Unreleased `CHANGELOG.md` entry for the cross-renderer premature-disposal and retained scheduler/queue fixes. Run the repository pre-PR sequence. All registration machinery should be private, so no generated interface change is expected.

**Verify**: `rtk moon fmt` → exit 0.

**Verify**: `rtk moon info` → exit 0, then `rtk git diff --exit-code -- incr_tea/pkg.generated.mbti` → exit 0.

**Verify**: `rtk moon check` → exit 0.

**Verify**: `rtk moon test incr_tea --target js` → exit 0.

**Verify**: `rtk npm --prefix examples/incr_tea run test:dom` → exit 0.

**Verify**: `rtk moon test` → exit 0; full workspace suite passes.

## Test plan

- `incr_tea/renderer_wbtest.mbt`:
  - one program mounted through two renderers survives first-root destroy;
  - it survives first-renderer dispose;
  - a detached root in the second renderer counts as a live owner and reattaches successfully;
  - destroy/dispose ordering permutations release only the targeted root and final global release disposes;
  - repeated destroy/dispose/release is idempotent;
  - after one root is removed, a stable `Cmd::after_flush` schedules only the remaining renderer;
  - final release removes the last scheduler and leaves no live roots/registrations.
- `incr_tea/scheduler_wbtest.mbt`:
  - disposal discards pending after-flush callbacks without executing them;
  - disposal discards pending/follow-up messages;
  - reentrant disposal during drain prevents later queued work and restores `is_draining=false`;
  - post-dispose dispatch remains false and disposal remains idempotent.
- `incr_tea/lifecycle_wbtest.mbt`: retain existing scope/watch/cell GC assertions; add registration/queue retention assertions only if not already directly covered in scheduler tests.
- Model renderer setup after `#209: destroy keeps a shared Program alive while another root still renders it`, but split roots across two renderer objects.
- Verification: the three targeted `moon test ... -f ... --target js` commands all pass, followed by package, browser, and full workspace gates.

## Done criteria

- [ ] The cross-renderer and queue-retention tests failed on the planned-at code and pass after implementation.
- [ ] A mounted or detached root in any renderer keeps its shared program alive when another renderer destroys/disposes its local roots.
- [ ] Every root owns one unique removable scheduler handle; detach/reattach does not duplicate it; destroy/dispose releases it exactly once.
- [ ] The final global mount release disposes the program, and explicit disposal clears every registration, pending message, and after-flush callback without executing abandoned effects.
- [ ] Renderer-local stats, `view_ids`, labels, listener teardown, foreign-root rejection, and detached-root behavior remain covered and green.
- [ ] No public API signature changes and `rtk git diff --exit-code -- incr_tea/pkg.generated.mbti` exits 0.
- [ ] `rtk moon fmt`, `rtk moon info`, `rtk moon check`, all three targeted test files, `rtk moon test incr_tea --target js`, `rtk npm --prefix examples/incr_tea run test:dom`, and `rtk moon test` exit 0.
- [ ] `rtk git diff --name-only` lists only in-scope files plus the permitted `plans/README.md` status edit.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" has drifted or an existing program-global ownership mechanism has landed.
- Current API constraints make program-owned registration impossible without changing a public signature or generated `.mbti`; report the exact constraint instead of silently banning multi-renderer mounting.
- The ownership decision changes public API semantics, or conflicts with the documented rule that detached roots remain alive and reattachable. In particular, do not dispose or unregister on detach.
- A proposed solution requires a runtime-global browser registry, closure identity comparison, or treating `view_id` as a unique mount id.
- Explicit `Program::dispose` cannot safely make still-owned renderer roots inert under the current read/flush contract; report the failing sequence and do not invent remount semantics.
- Disposal would need to execute pending application callbacks to empty queues; callbacks must be discarded, not run.
- `moon info` produces a public interface diff.
- A verification command fails twice after a reasonable fix attempt, or the change requires an out-of-scope file.

## Maintenance notes

- The registration handle is the lifecycle boundary between `Program` and browser shells. Future renderers must acquire one per root and release it on logical teardown, while temporary visibility/detachment states retain it.
- Reviewers should trace every root construction path and every teardown path; an unregistered root recreates premature disposal, while a missing release recreates closure retention.
- Snapshot active schedulers before invoking them if callbacks can synchronously destroy roots; mutation during iteration must not skip or double-call unrelated current registrations.
- If animation-frame cancellation is later added, keep it renderer-local. This plan removes program-held scheduler capabilities; it does not require cancelling a frame already queued by a renderer.
- Queue cleanup is observable lifecycle behavior. Future command variants that retain callbacks/resources must join the same explicit disposal path.
