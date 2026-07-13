# Plan 005: Enforce relation and rule lifecycle integrity in Datalog

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `rtk git diff --stat 31afb08..HEAD -- incr/cells/datalog_relation.mbt incr/cells/datalog_map_relation.mbt incr/cells/datalog_rule.mbt incr/cells/datalog_lifecycle.mbt incr/cells/internal/kernel/fixpoint.mbt incr/cells/dispose_test.mbt incr/cells/datalog_wbtest.mbt docs/api-reference.mbt.md CHANGELOG.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `31afb08`, 2026-07-13

## Why this matters

Rules retain declared input and output relation IDs, but relation disposal does
not consult those declarations. Disposing a declared relation therefore leaves
a live rule whose closure can abort on a disposed output, or whose unguarded
`delta_iter` can silently see a cleared input as empty. This plan establishes a
single lifecycle contract: a live rule pins every relation it declares;
relation disposal is rejected until those rules are disposed, all public reads
reject disposed handles consistently, and fixpoint never processes or
publishes already-disposed relation slots.

## Current state

- `incr/cells/datalog_relation.mbt` — typed set relation handle and current,
  frontier, staged-frontier storage.
- `incr/cells/datalog_map_relation.mbt` — typed map relation handle and its
  three storage layers.
- `incr/cells/datalog_rule.mbt` — validates declarations and stores rule
  metadata.
- `incr/cells/datalog_lifecycle.mbt` — type-erased lifecycle dispatch for
  relations, map relations, and rules.
- `incr/cells/internal/datalog/rule_data.mbt` — internal metadata definition;
  reference only, no change should be necessary.
- `incr/cells/internal/kernel/fixpoint.mbt` — semi-naive fixpoint loops.
- `incr/cells/dispose_test.mbt` — black-box disposal contract tests.
- `incr/cells/datalog_wbtest.mbt` — same-package white-box Datalog tests.
- `docs/api-reference.mbt.md` and `CHANGELOG.md` — public behavior record.

`Runtime::new_rule` validates declaration IDs, then stores the caller-owned
arrays directly (`incr/cells/datalog_rule.mbt:2-35`):

```moonbit
pub fn Runtime::new_rule(
  self : Runtime,
  input_relations : Array[CellId],
  output_relations : Array[CellId],
  apply_delta : () -> Unit,
  label? : String,
) -> @incr_types.RuleId {
  for id in input_relations {
    self.assert_rule_relation_id(id, "input")
  }
  for id in output_relations {
    self.assert_rule_relation_id(id, "output")
  }
  // ...
  let data : RuleData = {
    // ...
    apply_delta,
    input_relations,
    output_relations,
  }
  // ...
}
```

The metadata already contains everything needed for an internal dependency
check (`incr/cells/internal/datalog/rule_data.mbt:1-8`):

```moonbit
pub(all) struct RuleData {
  meta : CellMeta
  apply_delta : () -> Unit
  input_relations : Array[CellId]
  output_relations : Array[CellId]
}
```

Both relation handles clear typed storage only after the generic lifecycle
dispatch (`incr/cells/datalog_relation.mbt:146-167` and
`incr/cells/datalog_map_relation.mbt:223-247`):

```moonbit
pub fn[T] Relation::dispose(self : Relation[T]) -> Unit {
  self.rt.dispose_cell(self.cell_id)
  self.current.val.clear()
  self.delta.val.clear()
  self.staged_delta.val.clear()
}

pub fn[T] Relation::delta_iter(self : Relation[T]) -> Iter[T] {
  self.delta.val.iter()
}
```

```moonbit
pub fn[K, V] MapRelation::dispose(self : MapRelation[K, V]) -> Unit {
  self.rt.dispose_cell(self.cell_id)
  self.current.val.clear()
  self.delta.val.clear()
  self.staged_delta.val.clear()
  self.original_values.val.clear()
  self.changed_keys.val.clear()
}

pub fn[K, V] MapRelation::delta_iter(self : MapRelation[K, V]) -> Iter[(K, V)] {
  self.delta.val.iter()
}
```

Current/materialized reads already guard disposal: `Relation::contains` and
`iter` at `incr/cells/datalog_relation.mbt:117-136`, and
`MapRelation::get` and `iter` at
`incr/cells/datalog_map_relation.mbt:191-213`. Only `delta_iter` lacks the same
guard.

The type-erased relation lifecycle currently marks the slot disposed without
checking rules (`incr/cells/datalog_lifecycle.mbt:5-35`):

```moonbit
fn dispose_datalog_cell(meta : CellMeta, rt : Runtime, cell_id : CellId) {
  meta.subscribers.clear()
  meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}

impl CellLifecycle for RelationData with fn dispose_cell(self, rt, cell_id) {
  dispose_datalog_cell(self.meta, rt, cell_id)
}
```

Fixpoint skips disposed rules but invokes every relation callback in each phase
and can return disposed relation IDs as changed
(`incr/cells/internal/kernel/fixpoint.mbt:25-80`):

```moonbit
for rel in datalog.relations {
  (rel.begin_fixpoint)()
}
// ... drain every relation ...
for rule in datalog.rules {
  guard !is_cell_disposed(core, rule.meta.cell_id) else { continue }
  (rule.apply_delta)()
}
// ... convergence, promotion, and finish over every relation ...
```

Existing disposal tests cover standalone relation idempotence and disposed-rule
skipping, but not relation↔rule ownership
(`incr/cells/dispose_test.mbt:104-165,215-249`). Existing white-box tests show
declaration registration and cross-runtime validation
(`incr/cells/datalog_wbtest.mbt:18-57`).

No active ADR or design document chooses cascade disposal. The historical
Layer 3 design only says each Datalog kind has a lifecycle implementation; it
does not define relation↔rule ownership. Therefore implement the conservative
contract below, not a cascade:

1. A rule is **live** when its rule cell is not disposed.
2. A live rule pins every `CellId` in its snapshotted `input_relations` and
   `output_relations` arrays.
3. Disposing a pinned `Relation` or `MapRelation`, through either its typed
   `dispose` or `Runtime::dispose_cell`, aborts before clearing metadata or
   typed storage. The diagnostic identifies the relation, first live rule in
   registration order, and whether the declaration is input, output, or both;
   it tells the caller to dispose the rule first.
4. After all declaring rules are disposed, relation disposal is permitted and
   remains idempotent.
5. Creating a rule with an already-disposed input or output aborts with the
   declaration role identified.
6. Every public current or delta read aborts on a disposed relation.
7. Fixpoint skips disposed relations in every lifecycle phase and never
   includes a disposed relation in its returned changed-ID list.

Architecture constraint: follow Functional Core / Imperative Shell. Put the
declaration scan and role classification in a deterministic private helper that
takes explicit state and returns structured data or `None`; it must not abort
or mutate. Keep the abort and lifecycle mutation in
`datalog_lifecycle.mbt`. Snapshot caller-owned arrays at rule construction so
later caller mutation cannot rewrite the core's validated declaration. Do not
expose mutable metadata or add a public query API.

MoonBit conventions: two-space indentation, `Type::method`, snake-case tests,
`///` on public items, no comments that merely restate code. Match the lifecycle
dispatch split documented in `docs/design/internals.md:467-469`: coordinator
lifecycle logic stays in `incr/cells/`; the kernel remains one-way and must not
import the top-level `cells` package.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Disposal tests | `rtk moon test incr/cells/dispose_test.mbt` | exit 0; all disposal contract tests pass |
| Datalog white-box tests | `rtk moon test incr/cells/datalog_wbtest.mbt` | exit 0; all Datalog state tests pass |
| Format | `rtk moon fmt` | exit 0; MoonBit files formatted |
| Regenerate interfaces | `rtk moon info` | exit 0; generated interfaces refreshed |
| Public interface check | `rtk git diff --exit-code -- incr/cells/pkg.generated.mbti incr/cells/internal/kernel/pkg.generated.mbti` | exit 0; no public signature changed |
| Engine boundary check | `rtk bash scripts/check-engine-isolation.sh` | exit 0; all engine-isolation invariants pass |
| Typecheck | `rtk moon check` | exit 0; no errors |
| Full suite | `rtk moon test` | exit 0; all workspace tests pass |
| Scope check | `rtk git status --short` | only files listed under **In scope** are modified |

## Suggested executor toolkit

- Invoke the `moonbit`, `moonbit-agent-guide`, and `moonbit-error-handling`
  skills if available for syntax, package visibility, and abort conventions.
- Invoke `moonbit-verification` before final handoff if available.
- Read `AGENTS.md`, `docs/architecture.md`, and the engine-isolation section at
  `docs/design/internals.md:467-469` before changing package boundaries.

## Scope

**In scope** (the only files you should modify):

- `incr/cells/datalog_relation.mbt`
- `incr/cells/datalog_map_relation.mbt`
- `incr/cells/datalog_rule.mbt`
- `incr/cells/datalog_lifecycle.mbt`
- `incr/cells/internal/kernel/fixpoint.mbt`
- `incr/cells/dispose_test.mbt`
- `incr/cells/datalog_wbtest.mbt`
- `docs/api-reference.mbt.md`
- `CHANGELOG.md`
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though they look related):

- `incr/cells/internal/datalog/rule_data.mbt`; its existing input/output arrays
  are sufficient metadata. STOP if new fields appear necessary.
- Public APIs for querying rules, reverse dependencies, or lifecycle state.
- Cascading relation disposal into rules, automatically disposing rules, or
  inventing reference-counted ownership.
- Replacing append-only Datalog SoA arrays, compacting disposed slots, changing
  rule scheduling, or redesigning the fixpoint algorithm.
- Inferring closure dependencies that were not declared in `new_rule`; the
  lifecycle contract applies to declared IDs only.
- Relation deletion/retraction semantics, transaction semantics, and GC policy.
- Generated `.mbti` files by hand; no public signature change is expected.

## Git workflow

- Branch: `advisor/005-datalog-relation-rule-lifecycle`
- Commit per logical unit if useful; final commit history should use
  conventional messages such as `fix(datalog): enforce relation rule lifetimes`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Encode the lifecycle contract as a deterministic internal query

In `incr/cells/datalog_rule.mbt`, define a private structured result that
contains the first live declaring rule's `CellId` and declaration role (input,
output, or both). Add a private deterministic helper that accepts the explicit
runtime core/rule collection and a relation `CellId`, scans rules in registration
order, skips disposed rule cells, and returns the first matching result or
`None`. It must not abort, mutate runtime state, or expose the rule arrays.

At `Runtime::new_rule`, keep all current validation but explicitly reject an
already-disposed relation after bounds validation with an abort message that
names `input` or `output`. Store defensive `copy()` values of both validated
declaration arrays in `RuleData`; never retain the caller's mutable arrays.

Add white-box tests in `incr/cells/datalog_wbtest.mbt` that:

- classify input-only, output-only, and input+output declarations;
- skip a disposed rule and select a later live rule deterministically;
- return `None` after every declaring rule is disposed;
- clear or mutate the caller's original input/output arrays after `new_rule`
  and prove the stored metadata remains unchanged;
- assert `new_rule` aborts for an already-disposed input and for an
  already-disposed output.

Keep helper tests white-box; do not create public introspection solely for
testing.

**Verify**: `rtk moon test incr/cells/datalog_wbtest.mbt` → exit 0; the new
classification, snapshot, and disposed-declaration tests all pass.

### Step 2: Reject disposal while a live rule declares the relation

In `incr/cells/datalog_lifecycle.mbt`, separate relation teardown from generic
rule teardown. Before mutating a `RelationData` or `FunctionalRelationData`
cell, call the deterministic helper from Step 1. If it returns a declaration,
abort with a stable diagnostic that includes relation ID, rule ID, role, and
the instruction to dispose the rule first. Only when it returns `None` should
the existing subscriber/label cleanup and `cell_index = Disposed` mutation run.
Leave `RuleData` disposal as the current direct metadata teardown.

The guard must live in the shared `CellLifecycle` path so both typed
`relation.dispose()` and generic `rt.dispose_cell(relation.id())` have identical
behavior. Do not put the only guard in the typed handles. The typed handle must
continue clearing its typed sets/maps only after generic disposal succeeds, so
rejected disposal leaves all facts and frontier data intact.

Extend `incr/cells/dispose_test.mbt` with black-box tests for both relation
kinds and both declaration roles:

- disposing a live rule's `Relation` input aborts;
- disposing a live rule's `Relation` output aborts;
- disposing a live rule's `MapRelation` input aborts;
- disposing a live rule's `MapRelation` output aborts;
- generic `Runtime::dispose_cell` is guarded, not only typed disposal;
- after `Runtime::dispose_rule` for every declaring rule, input and output
  relations can be disposed and repeated disposal remains a no-op.

Use `panic ...` test names for required aborts, following
`incr/cells/dispose_test.mbt:236-249`. Keep successful lifecycle tests separate
so they can assert final `is_disposed()` state.

**Verify**: `rtk moon test incr/cells/dispose_test.mbt` → exit 0; every new
input/output and typed/generic lifecycle test passes.

### Step 3: Make current and delta reads share the strict disposed guard

Add the same disposed-cell guard used by current reads to
`Relation::delta_iter` and `MapRelation::delta_iter`, with type-specific stable
abort messages. Update their public doc comments to state that all reads abort
after disposal. Do not add dependency recording to `delta_iter`: it is a
fixpoint-frontier primitive and changing tracking semantics is outside scope.

In `incr/cells/dispose_test.mbt`, add explicit panic regressions for current and
delta reads after disposal:

- `Relation::contains`, `Relation::iter`, and `Relation::delta_iter`;
- `MapRelation::get`, `MapRelation::iter`, and `MapRelation::delta_iter`.

Current-read tests pin the already-intended contract; delta-read tests prove the
gap is closed. Keep insert-after-dispose tests unchanged.

**Verify**: `rtk moon test incr/cells/dispose_test.mbt` → exit 0; all six
disposed-read cases abort as expected and all existing disposal tests pass.

### Step 4: Exclude disposed relations from every fixpoint phase

In `incr/cells/internal/kernel/fixpoint.mbt`, guard every loop over
`datalog.relations` and `datalog.functional_relations` with
`is_cell_disposed(core, <meta cell id>)`. Apply it consistently to:

1. begin-fixpoint snapshots;
2. frontier draining;
3. staged-delta convergence checks;
4. staged-delta promotion;
5. finish/net-change checks and changed-ID collection.

Keep disposed-rule skipping unchanged. Do not add a new reverse index or alter
iteration order. A disposed relation must contribute neither work nor a
changed ID.

Add white-box regressions in `incr/cells/datalog_wbtest.mbt` for both
`Relation` and `MapRelation`. After legal disposal (no live declaring rule),
use same-package access to seed otherwise unreachable frontier backing storage,
call `@kernel.run_fixpoint(rt.core, rt.datalog)`, and assert the returned array
does not contain the disposed cell ID and the injected value was not drained or
promoted. This deliberately tests kernel skipping rather than relying on the
typed `dispose` method's normal clearing.

**Verify**:

1. `rtk moon test incr/cells/datalog_wbtest.mbt` → exit 0; disposed relation
   callbacks are skipped for both relation kinds.
2. `rtk bash scripts/check-engine-isolation.sh` → exit 0; the kernel boundary
   remains one-way.

### Step 5: Document the ownership and migration contract

Update public doc comments on `Relation::dispose`, `MapRelation::dispose`,
their `delta_iter` methods, and `Runtime::new_rule` so callers know:

- declaration arrays are snapshotted;
- declared relations are pinned by live rules;
- dispose rules before disposing their input/output relations;
- all reads abort after relation disposal.

Extend the Datalog/MapRelation section of `docs/api-reference.mbt.md` with the
same contract and a short teardown order example (`rt.dispose_rule(rule_id)`
before relation disposal). Add a concise `Changed` or `Fixed` entry under a new
or existing `Unreleased` section in `CHANGELOG.md`. State that disposal now
rejects live declared rules; do not describe it as cascade disposal and do not
add a release or issue number.

**Verify**: `rtk rg -n "dispose_rule|live rule|disposed|delta_iter|Unreleased" incr/cells/datalog_relation.mbt incr/cells/datalog_map_relation.mbt incr/cells/datalog_rule.mbt docs/api-reference.mbt.md CHANGELOG.md` → the implemented lifecycle and migration order are documented consistently.

### Step 6: Run the full repository verification sequence

Run formatting and interface regeneration first, then architectural,
typecheck, targeted, and full-suite gates. No public signature should change;
documentation and abort behavior change only.

**Verify**:

1. `rtk moon fmt` → exit 0.
2. `rtk moon info` → exit 0.
3. `rtk git diff --exit-code -- incr/cells/pkg.generated.mbti incr/cells/internal/kernel/pkg.generated.mbti` → exit 0.
4. `rtk bash scripts/check-engine-isolation.sh` → exit 0.
5. `rtk moon check` → exit 0, no errors.
6. `rtk moon test incr/cells/dispose_test.mbt` → exit 0.
7. `rtk moon test incr/cells/datalog_wbtest.mbt` → exit 0.
8. `rtk moon test` → exit 0, all workspace tests pass.
9. `rtk git status --short` → no files outside the **In scope** list are modified.

## Test plan

- `incr/cells/datalog_wbtest.mbt`: deterministic declaration classification,
  caller-array snapshotting, disposed rule filtering, disposed input/output
  rejection at rule creation, and kernel skipping for both relation kinds.
- `incr/cells/dispose_test.mbt`: live-rule disposal rejection for input/output
  and Relation/MapRelation, generic dispatch parity, legal disposal after rule
  teardown, idempotence, and strict current/delta reads after disposal.
- Model panic tests after `incr/cells/dispose_test.mbt:236-249`; model rule
  registration tests after `incr/cells/datalog_wbtest.mbt:25-57`.
- Verification: both targeted commands exit 0, followed by a green full
  `rtk moon test`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] Rule declaration arrays are defensively copied after validation.
- [ ] A private deterministic helper reports the first live declaring rule and
  input/output/both role without mutation or abort.
- [ ] Typed and generic relation disposal reject every live declared input or
  output before any metadata or typed storage is cleared.
- [ ] Disposing all declaring rules makes relation disposal legal and
  idempotent.
- [ ] `new_rule` rejects already-disposed input and output IDs.
- [ ] `Relation` and `MapRelation` current and delta reads all reject disposed
  handles.
- [ ] Every fixpoint relation loop skips disposed cells; returned changed IDs
  never include a disposed relation.
- [ ] No public API signature, reverse index, cascade behavior, or rule
  scheduling redesign is introduced.
- [ ] `rtk moon test incr/cells/dispose_test.mbt` and
  `rtk moon test incr/cells/datalog_wbtest.mbt` exit 0.
- [ ] `rtk moon fmt`, `rtk moon info`, `rtk bash scripts/check-engine-isolation.sh`,
  `rtk moon check`, and `rtk moon test` exit 0.
- [ ] Both generated-interface diff checks exit 0.
- [ ] `rtk git status --short` lists no files outside the in-scope set.
- [ ] `plans/README.md` status row is updated unless the dispatcher owns it.

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in **Current state** does not match the excerpts.
- Implementing the contract requires a new public rule-query/reverse-dependency
  API, a new public lifecycle type, or changes to public signatures.
- The existing input/output arrays are insufficient without modifying
  `incr/cells/internal/datalog/rule_data.mbt` or adding a broad reverse index.
- Evidence in a current ADR or active design document clearly makes cascade
  disposal canonical; report that evidence instead of mixing policies.
- Correctness requires inferring undeclared closure dependencies or redesigning
  the Datalog/fixpoint architecture.
- A relation can be marked `Disposed` or have storage cleared before the
  live-rule check completes.
- Defensive copies are unavailable or change the public constructor contract;
  report the MoonBit limitation rather than retaining mutable aliases.
- `moon info` produces a public interface diff.
- `scripts/check-engine-isolation.sh` reports a new back-edge.
- Any verification command fails twice after one reasonable correction.
- Any out-of-scope file must be modified.

## Maintenance notes

- The declaration arrays become lifecycle authority, not only scheduling
  metadata. Future rule-construction APIs must validate and snapshot them too.
- Reviewers should verify the guard is centralized in `CellLifecycle`; a check
  only in typed `dispose` leaves `Runtime::dispose_cell` unsafe.
- Keep deterministic diagnostics stable: first live rule by registration order
  and explicit input/output/both role makes failures reproducible.
- Any future relation compaction or rule scheduling index must preserve the
  same pinning semantics or intentionally replace them in an ADR.
- Undeclared relation captures in `apply_delta` remain the caller's contract
  violation. Inferring closure captures is deliberately deferred.
- Cascade disposal, reverse indexes, and relation retraction are separate
  design problems and should not be folded into review of this fix.

