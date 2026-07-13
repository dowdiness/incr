# Plan 001: Make scope disposal re-entrant, ordered, and at-most-once

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `rtk git diff --stat 31afb08..HEAD -- incr/cells/scope.mbt incr/tests/scope_test.mbt docs/api-reference.mbt.md CHANGELOG.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `31afb08`, 2026-07-13

## Why this matters

`Scope::dispose` marks the scope disposed only after invoking child disposal
and user-provided cleanup hooks. A child or hook that calls `dispose` on the
same scope therefore starts the whole sequence again, causing unbounded
recursion instead of the documented idempotent no-op. The fix must close the
scope before any callback can re-enter it while preserving the established
children → hooks → owned-cells teardown order and at-most-once cleanup.

## Current state

- `incr/cells/scope.mbt` — owns the scope lifecycle, children, hooks, and cells.
- `incr/tests/scope_test.mbt` — black-box public-API scope lifecycle tests.
- `docs/api-reference.mbt.md` — checked contributor-facing API reference for
  `Scope` lifecycle behavior.
- `CHANGELOG.md` — release-facing behavior record.

The scope currently uses one mutable Boolean and does not close the lifecycle
until all effects have run (`incr/cells/scope.mbt:24-30,85-104`):

```moonbit
pub struct Scope {
  priv runtime : Runtime
  priv cells : Array[CellId]
  priv children : Array[Scope]
  priv dispose_hooks : Array[() -> Unit]
  priv mut disposed : Bool
}

pub fn Scope::dispose(self : Scope) -> Unit {
  guard !self.disposed else { return }
  for child in self.children {
    child.dispose()
  }
  for hook in self.dispose_hooks {
    hook()
  }
  for cell_id in self.cells {
    self.runtime.dispose_cell(cell_id)
  }
  self.children.clear()
  self.dispose_hooks.clear()
  self.cells.clear()
  self.disposed = true
}
```

`Scope::on_dispose` promises at-most-once execution but only rejects a scope
whose final Boolean has already been set (`incr/cells/scope.mbt:341-361`):

```moonbit
/// The callback runs at most once, during the dispose_hooks phase
/// (step 2 of disposal order — after children, before owned cells).
/// Registration on an already-disposed scope aborts.
pub fn Scope::on_dispose(self : Scope, cleanup : () -> Unit) -> Unit {
  guard !self.disposed else {
    abort("Scope::on_dispose called on a disposed scope")
  }
  self.dispose_hooks.push(cleanup)
}
```

Existing tests pin ordinary idempotence and child-before-parent hook order, but
none re-enter disposal (`incr/tests/scope_test.mbt:261-290`):

```moonbit
test "scope: on_dispose callback runs at most once despite double dispose" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let mut count = 0
  scope.on_dispose(() => count = count + 1)
  scope.dispose()
  scope.dispose()
  inspect(count, content="1")
}

test "scope: on_dispose child hooks fire before parent hooks" {
  // ...
  parent.dispose()
  inspect(log, content="child,parent")
}
```

Architecture constraint: use the repository's Functional Core / Imperative
Shell default. Model the lifecycle request as a deterministic two-state
transition (active + `DisposeRequested` → closed/start effects; closed +
`DisposeRequested` → closed/ignore), then keep child, hook, cell, and collection
mutation in the existing imperative shell. A private pure helper returning the
next Boolean plus a begin/ignore decision is the minimal acceptable equivalent
to introducing a larger enum. Do not add a public lifecycle type.

MoonBit conventions to match: two-space formatting, `Type::method` names,
`snake_case` locals and tests, `///` documentation for every public item, and
comments only for invariants or non-obvious interaction effects. The existing
reducer-shaped batch transition code in `incr/cells/internal/kernel/batch.mbt`
is the architectural exemplar; keep this fix much smaller because scope has
only one terminal transition.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Targeted tests | `rtk moon test incr/tests/scope_test.mbt` | exit 0; all scope tests pass |
| Format | `rtk moon fmt` | exit 0; MoonBit files formatted with two-space indentation |
| Regenerate interfaces | `rtk moon info` | exit 0; generated interfaces refreshed |
| Interface drift check | `rtk git diff --exit-code -- incr/cells/pkg.generated.mbti` | exit 0; no public API signature changed |
| Typecheck | `rtk moon check` | exit 0; no errors |
| Full suite | `rtk moon test` | exit 0; all workspace tests pass |
| Scope check | `rtk git status --short` | only files listed under **In scope** are modified |

## Suggested executor toolkit

- Invoke the `moonbit` or `moonbit-agent-guide` skill if available for MoonBit
  syntax and test conventions.
- Invoke `moonbit-verification` before final handoff if available; its ordering
  should not replace the exact gates in this plan.
- Read `AGENTS.md` before editing. It is the canonical repository guide.

## Scope

**In scope** (the only files you should modify):

- `incr/cells/scope.mbt`
- `incr/tests/scope_test.mbt`
- `docs/api-reference.mbt.md`
- `CHANGELOG.md`
- `plans/README.md` (status row only)
- `plans/001-reentrant-scope-disposal.md` (done-criteria checkboxes only).

**Out of scope** (do NOT touch, even though they look related):

- Other cell `dispose` implementations; this bug is specifically callback
  re-entry through `Scope`.
- Runtime disposal, GC, observer, watch, accumulator, and derived-map lifecycle
  semantics.
- Catching, aggregating, or recovering from aborts inside cleanup hooks.
- Any public API addition or change to the children → hooks → cells order.
- Generated `pkg.generated.mbti` files by hand; run `moon info` and expect no
  interface diff for this private implementation change.

## Git workflow

- Branch: `advisor/001-reentrant-scope-disposal`
- Commit the implementation, tests, and behavior documentation as one logical
  unit with message `fix(scope): make disposal reentrant-safe`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add a minimal deterministic disposal transition

In `incr/cells/scope.mbt`, add a private, deterministic transition helper for
the two meaningful states represented by the current Boolean. Given the current
`disposed` value and a disposal request, it must return both the next value and
whether the imperative teardown shell should begin:

- active (`false`) → closed (`true`), decision: begin teardown;
- closed (`true`) → closed (`true`), decision: ignore.

Use a private decision enum or a Boolean decision; do not expose it publicly.
Apply the next state to `self.disposed` at the very start of `Scope::dispose`,
before iterating even the first child. Return immediately for the ignore
decision. Keep the effectful shell in its existing order: recursively dispose
children, execute hooks, dispose owned cells, then clear all three owning
arrays. Remove the late `self.disposed = true` assignment because the state is
already closed before effects begin.

This ordering is load-bearing: a child hook may call `parent.dispose()` before
the parent reaches its own hooks, and a parent hook may call
`parent.dispose()` while its hook array is being traversed. Both calls must see
the closed state and return without starting another traversal. Keep all
existing creation and registration guards based on `!self.disposed`; this also
means no new child, cell, watch, or cleanup hook can be registered after
teardown starts. Preserve the current `Debug` shape and the public
`Scope::is_disposed() -> Bool` API.

Update the `Scope::dispose` and `Scope::on_dispose` doc comments to say that a
scope becomes closed before callbacks run, re-entrant and later disposal calls
are no-ops, and registration after teardown starts aborts. Do not claim that
hook aborts are recovered.

**Verify**: `rtk moon check` → exit 0 with no type or warning errors.

### Step 2: Pin re-entry, ordering, and at-most-once cleanup in one regression

Extend `incr/tests/scope_test.mbt` beside the existing `on_dispose` tests. Build
a parent scope with a child; give both an owned input cell. Register a child
hook that records its call, verifies the child cell is not disposed yet, and
calls `parent.dispose()`. Register a parent hook that records its call, verifies
the child cell is already disposed while the parent cell is not, and calls
`parent.dispose()` again. Then call `parent.dispose()` and assert:

- the child and parent hooks each ran exactly once;
- the observed order is child hook, then parent hook;
- the child cell is alive during its hook but disposed by the parent hook;
- the parent cell is alive during its hook and disposed on return;
- `parent.is_disposed()` is true during both re-entrant calls and after return;
- a later explicit `parent.dispose()` changes neither counts nor log.

Use the existing black-box `@incr` style and `inspect(..., content="...")` /
`assert_true` assertions. Avoid a test that relies only on timing out or stack
overflow; successful completion and exact counts must prove the fix.

**Verify**: `rtk moon test incr/tests/scope_test.mbt` → exit 0; the new
re-entrant regression and every existing scope test pass.

### Step 3: Record the clarified public behavior

In the Scope lifecycle paragraph of `docs/api-reference.mbt.md`, document that
disposal closes the scope before child/hook callbacks, re-entrant disposal is
an idempotent no-op, and the teardown effect order remains children → hooks →
owned cells. Add a concise `Fixed` entry under a new `Unreleased` section in
`CHANGELOG.md` (or the existing Unreleased section if one has appeared) naming
the recursive-disposal bug and the preserved order. Do not add a released
version number or issue number.
Retain the existing `Scope::on_dispose` resource-cleanup example in
`incr/cells/scope.mbt`; add the new lifecycle wording around it rather than
deleting practical listener-removal guidance. Refer to the scope as closed,
not the closure.

**Verify**: `rtk rg -n "re-entrant|children.*hooks.*cells|Unreleased" incr/cells/scope.mbt docs/api-reference.mbt.md CHANGELOG.md` → matches in all three files and accurately describes the implemented contract.

### Step 4: Format, regenerate, and run the complete verification gates

Run the repository-required order. Inspect the generated interface diff after
`moon info`; the private transition must not change the public signature.

**Verify**:

1. `rtk moon fmt` → exit 0.
2. `rtk moon info` → exit 0.
3. `rtk git diff --exit-code -- incr/cells/pkg.generated.mbti` → exit 0.
4. `rtk moon check` → exit 0, no errors.
5. `rtk moon test` → exit 0, all workspace tests pass.
6. `rtk git status --short` → no files outside the **In scope** list are modified.

## Test plan

- Add one focused black-box regression in `incr/tests/scope_test.mbt` covering
  re-entry from both a child hook and the same parent scope's hook.
- Assert action order and cell lifecycle state, not merely absence of a crash.
- Retain and run the existing tests at `incr/tests/scope_test.mbt:261-298` for
  ordinary callback execution, later double disposal, child-before-parent
  hooks, and rejection of late hook registration.
- Verification: `rtk moon test incr/tests/scope_test.mbt` → all existing tests
  plus the new regression pass.
- Final regression gate: `rtk moon test` → the entire workspace passes.

## Done criteria

Machine-checkable. ALL must hold:

- [x] `Scope::dispose` closes its lifecycle before invoking any child or hook.
- [x] Re-entry from a child hook and a parent hook completes without recursion.
- [x] Children → hooks → owned-cells ordering is asserted by the new test.
- [x] Every cleanup hook runs at most once; a later dispose remains a no-op.
- [x] Existing public signatures are unchanged.
- [x] Existing `Scope::on_dispose` resource-cleanup example remains present.
- [x] `rtk moon test incr/tests/scope_test.mbt` exits 0.
- [x] `rtk moon fmt`, `rtk moon info`, `rtk moon check`, and `rtk moon test` exit 0 in that order.
- [x] `rtk git diff --exit-code -- incr/cells/pkg.generated.mbti` exits 0.
- [x] `rtk git status --short` lists no files outside the in-scope set.
- [x] `plans/README.md` status row is updated unless the dispatcher owns it.

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in **Current state** does not match the excerpts.
- Preventing re-entry appears to require changing the public `Scope` API or
  changing children → hooks → cells ordering.
- A proposed state model allows registration or cell construction while
  teardown is in progress.
- The new test can pass without proving hook counts and cell-order states.
- `moon info` produces a public interface change in
  `incr/cells/pkg.generated.mbti`.
- Correctness appears to require recoverable hook-failure semantics; that is a
  separate lifecycle design decision.
- A verification command fails twice after one reasonable correction.
- Any out-of-scope file must be modified.

## Maintenance notes

- Treat `disposed == true` as "closed to lifecycle work," including the period
  while teardown effects are still running, not only after the arrays clear.
- Reviewers should scrutinize the exact point where state closes and verify
  that no user callback occurs before it.
- Future changes that add another scope teardown phase must place it after the
  close transition and explicitly preserve or revise the documented order.
- Hook failure recovery and asynchronous/concurrent disposal are deliberately
  deferred; this plan only makes synchronous callback re-entry safe.

