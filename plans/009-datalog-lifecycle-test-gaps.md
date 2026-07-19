# Plan 009: Cover mid-fixpoint disposal and rebuild-after-teardown in datalog lifecycle tests

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat f839477..HEAD -- incr/cells/dispose_test.mbt incr/cells/datalog_wbtest.mbt incr/cells/internal/kernel/fixpoint.mbt`
> If any changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, treat it
> as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (test-only)
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `f839477`, 2026-07-19

## Why this matters

PR #412 ("enforce relation-rule lifetimes") added lifecycle enforcement to the
Datalog engine: relations referenced by live rules cannot be disposed
(pinning), disposed relations/rules are skipped by the fixpoint loops, and
reads on disposed relations abort. The shipped tests cover disposal that
happens BEFORE a fixpoint runs. Two realistic sequences are unverified:

1. **Disposal during an in-flight fixpoint** — a rule body disposing an
   unpinned relation or an already-registered rule while `run_fixpoint` is
   iterating. The per-loop `is_cell_disposed` guards in
   `incr/cells/internal/kernel/fixpoint.mbt` exist precisely to tolerate this,
   but nothing drives them mid-run; a future refactor of guard placement could
   silently regress.
2. **Rebuild after full teardown** — dispose all rules and relations, then
   register fresh ones in the SAME runtime and run a fixpoint. The engine's
   `datalog.rules`/`relations` arrays are append-only and retain disposed
   entries; the tear-down-then-remount pattern is what UI consumers
   (incr_tea) actually do, and no test proves disposed residue cannot corrupt
   a new registration.

Both are cheap tests against existing behavior; no production code changes.

## Current state

Relevant files:

- `incr/cells/dispose_test.mbt` — black-box lifecycle tests using the public
  API (`Runtime::Runtime()`, `Relation::Relation(rt)`, `rt.new_rule(...)`,
  `rt.dispose_rule(...)`, `rel.dispose()`); the new tests go here.
- `incr/cells/datalog_wbtest.mbt` — whitebox tests that can reach
  `@kernel.run_fixpoint(rt.core, rt.datalog)` directly.
- `incr/cells/internal/kernel/fixpoint.mbt` — the fixpoint loops whose
  disposed-skip guards (lines ~25–90) these tests pin down.
- `incr/cells/datalog_lifecycle.mbt:28-45` — the pin check: disposing a
  relation aborts while any declaring live rule exists. Consequence for test
  design: a rule body may only dispose a relation that NO live rule declares,
  or dispose a rule.

Exemplar 1 — rule wiring pattern, `incr/cells/dispose_test.mbt:290-307`
("disposed rule is skipped during fixpoint"):

```moonbit
test "disposed rule is skipped during fixpoint" {
  let rt = Runtime::Runtime()
  let input : Relation[Int] = Relation::Relation(rt)
  let output : Relation[Int] = Relation::Relation(rt)
  let rule_id = rt.new_rule([input.id()], [output.id()], fn() {
    for x in input.delta_iter() {
      output.insert(x * 10) |> ignore
    }
  })
  input.insert(1) |> ignore
  rt.fixpoint()
  assert_true(output.contains(10))
  rt.dispose_rule(rule_id)
  input.insert(2) |> ignore
  rt.fixpoint()
  assert_false(output.contains(20))
}
```

Exemplar 2 — teardown-order pattern, `incr/cells/dispose_test.mbt:209-223`
("relation: disposal is legal after all declaring rules are disposed"):
dispose all rules first, then relations; double-dispose is idempotent.

Exemplar 3 — disposed-frontier skip at kernel level,
`incr/cells/datalog_wbtest.mbt:408-417` ("fixpoint: disposed relation
frontier is skipped") — uses `@kernel.run_fixpoint(rt.core, rt.datalog)` and
asserts `changed_ids` does not contain the disposed relation's id.

Repo conventions that apply:

- Tests in `incr/cells/` sit beside source; black-box in `*_test.mbt`,
  whitebox in `*_wbtest.mbt`. No tests in `internal/` packages.
- Assertions: `assert_true`/`assert_false`/`inspect`. Panic tests are named
  with a leading `"panic "`.
- Hook-enforced command prefix: use `NEW_MOON_MOD=0 moon ...`.

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---|---|---|
| Typecheck | `NEW_MOON_MOD=0 moon check` | exit 0 |
| Full tests | `NEW_MOON_MOD=0 moon test` | all pass |
| Format/interfaces | `NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt` | exit 0; empty `.mbti` diff |

`moon test -f <file>` filtering is unreliable in this toolchain — run the
full suite.

## Scope

**In scope** (the only files you may modify):

- `incr/cells/dispose_test.mbt`
- `incr/cells/datalog_wbtest.mbt` (only if a kernel-level assertion is needed;
  prefer dispose_test.mbt)

**Out of scope** (do NOT touch):

- `incr/cells/internal/kernel/fixpoint.mbt` and any other production source —
  if a new test FAILS against current behavior, that is a STOP condition
  (you found a bug; report it, do not patch the engine).
- `incr/cells/datalog_lifecycle.mbt`, `datalog_rule.mbt`,
  `datalog_relation.mbt`, `datalog_map_relation.mbt`.
- `pkg.generated.mbti` files (regenerated only).

## Git workflow

- Branch: `advisor/009-datalog-lifecycle-test-gaps` (do not commit to `main`).
- Commit style: conventional commits, e.g. `test(datalog): cover mid-fixpoint
  disposal and rebuild after teardown`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Mid-fixpoint disposal of an unpinned relation

Add to `incr/cells/dispose_test.mbt` a test
`"rule body disposing an unpinned relation mid-fixpoint converges"`:

- Create `rt`, relations `input`, `output`, and a third relation `bystander`
  declared by NO rule (unpinned).
- Rule: `rt.new_rule([input.id()], [output.id()], fn() { ... })` whose body
  copies `input.delta_iter()` into `output` AND — on the first invocation only
  (use a `let disposed = Ref(false)`-style latch captured by the closure) —
  calls `bystander.dispose()`.
- Insert into `input`, run `rt.fixpoint()`.
- Assert: fixpoint returns normally, `output` contains the derived fact,
  `bystander.is_disposed()` is true.

### Step 2: Mid-fixpoint disposal of another rule

Add `"rule body disposing another live rule mid-fixpoint is tolerated"`:

- Two rules A and B over the same `input`; A's body (first invocation latch)
  calls `rt.dispose_rule(b_rule_id)`.
- Note the fixpoint may or may not have already run B in the current
  iteration — assert only order-independent facts: the fixpoint terminates,
  and after a SECOND `input.insert(...) |> ignore; rt.fixpoint()`, B's output
  effect does not occur again while A's does.
- Rule ids are returned by `rt.new_rule(...)` (see Exemplar 1); declare B
  before A only if the body needs the id — if `new_rule` ordering makes the
  latch awkward, store the id in a `Ref[RuleId?]`-shaped holder set after
  declaration, matching whatever id type `new_rule` returns (read its
  signature in `incr/cells/datalog_rule.mbt` first).

### Step 3: Rebuild after full teardown

Add `"datalog rebuild after full teardown derives fresh facts"`:

- Build relation+rule, insert, `rt.fixpoint()`, assert derived fact.
- Dispose the rule then both relations (order per Exemplar 2).
- In the SAME runtime, create a NEW relation pair and a NEW rule, insert a
  distinct value, `rt.fixpoint()`.
- Assert: the new output contains the new derived fact; the old (disposed)
  relations remain disposed; no abort occurs.

**Verify after each step**: `NEW_MOON_MOD=0 moon check` → exit 0.

### Step 4: Full suite + format

`NEW_MOON_MOD=0 moon test` → all pass (3 new tests included), then
`NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt` → empty `.mbti` diff.

## Test plan

This plan IS the test plan: 3 new black-box tests in
`incr/cells/dispose_test.mbt` (Steps 1–3), modeled on the exemplars quoted in
"Current state". Verification: `NEW_MOON_MOD=0 moon test` green.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `NEW_MOON_MOD=0 moon test` exits 0; the 3 new tests exist and pass
- [ ] `git diff --stat` touches only in-scope files (plus no `.mbti` change)
- [ ] No production `.mbt` file outside tests modified (`git status`)
- [ ] `plans/README.md` status row for 009 updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any new test FAILS against current engine behavior (e.g. mid-fixpoint
  disposal aborts, or rebuild derives nothing). That is a real finding —
  report the failing sequence and output; do NOT modify engine code or water
  the assertion down to match broken behavior.
- `rt.new_rule` / `dispose_rule` signatures differ from the exemplar usage
  (drift since `f839477`).
- The pin check rejects a disposal the test design assumed legal (re-read
  `datalog_lifecycle.mbt:28-45` and report the mismatch rather than
  restructuring the scenario ad hoc).

## Maintenance notes

- These tests pin the disposed-skip guard PLACEMENT in
  `kernel/fixpoint.mbt` — anyone refactoring the fixpoint loop structure
  should expect them to catch a dropped guard.
- The index's R14 (measurement-gated) records the cost question of scanning
  disposed residue in the append-only rule/relation arrays; Step 3's rebuild
  test is the correctness companion to that recorded perf question.
- Reviewer should scrutinize Step 2's assertions for order-independence — a
  test that encodes the current iteration order would be flaky under a
  legitimate scheduler change.
