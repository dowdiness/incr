# Plan 011: Exhaustively validate tiny retractable graphs against the independent oracle

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When implementation and all gates pass, follow the
> documentation close-out in Step 9; do not leave this plan or a stale `DONE`
> row in the active plan index.
>
> **Drift check (run first)**:
> `git diff --stat e925853..HEAD -- dataflow/types.mbt dataflow/core.mbt dataflow/engine.mbt dataflow/oracle.mbt dataflow/spike_wbtest.mbt dataflow/property_wbtest.mbt dataflow/moon.pkg dataflow/README.mbt.md`
> If any listed file changed since this plan was written, compare the live code
> with the "Current state" excerpts before proceeding. Stop on a semantic
> mismatch; do not transplant this plan onto changed lifecycle or oracle rules.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none; Plans 008 and 009 are intentionally unrelated
- **Category**: tests
- **Planned at**: commit `e925853`, 2026-07-19

**Reader:** An executor adding deterministic post-GO evidence to the private
`dowdiness/dataflow` correctness spike.

**Decision:** Add a bounded exhaustive Engine-versus-oracle matrix without
changing production semantics or exposing an API.

**Keep until:** The implementation is merged, rejected, or superseded.

**Disposition:** Delete this plan after completion; retain the durable evidence
in `dataflow/README.mbt.md`. **No ADR needed:** this is test-only evidence under
the accepted module boundary, not a new architectural decision.

## Why this matters

Phase 0 compares generated five-node traces with an independent
full-recomputation oracle, but its 40 QuickCheck successes are probabilistic.
A small deterministic state space can cover every support threshold, invalid
retraction, self-loop, two-cycle, three-node cycle, and alternate-path shape in
that domain. The matrix should strengthen the bounded correctness claim without
creating a public API, adapter, new operator, or production-engine commitment.

## State space and exact counts

The state spaces are deliberately finite and explicit:

| Matrix | Source states | Transition/config dimensions | Scenarios |
|---|---:|---|---:|
| A: weighted two-node transitions | `3^4 = 81` directed graphs; four edges including self-edges, each weight `0..2` | each of four edges × diff `[-2,-1,+1,+2]` × N=`1/2/4` | `81 × 4 × 4 × 3 = 3,888` |
| B: Boolean three-node closures | `2^9 = 512` directed graphs; nine edges including self-edges | N=`1/2/4` | `512 × 3 = 1,536` |
| **Total** | | | **5,424** |

Matrix A uses a fresh Engine and Oracle per scenario. Epoch 0 establishes the
encoded graph; epoch 1 applies one signed edge update. Matrix B uses a fresh
Engine and Oracle and closes one epoch. Do not add random sampling to either
matrix and do not describe a subset as exhaustive.

Use these representative shell configurations in both matrices:

| N | Seed | Epoch-0 batching |
|---:|---:|---|
| 1 | none | one batch in canonical edge order |
| 2 | 7 | one update per batch |
| 4 | 11 | one reversed batch |

Each configuration is checked independently against the oracle. Existing
property tests remain responsible for broader randomized batching, delivery,
and same-seed replay.

## Current state

### Existing test boundaries

`dataflow/spike_wbtest.mbt:7-109` already owns source fixtures and full shell
orchestration:

```moonbit
fn test_update(from : Int, to : Int, diff : Int) -> SourceUpdate {
  { edge: { from, to }, diff }
}

fn test_stage_batches(
  engine : Engine,
  epoch : Int,
  batches : Array[Array[SourceUpdate]],
) -> Result[Publication, ProtocolError] {
  // begin -> stage each batch -> close -> run_closed
}

fn test_flatten_batches(
  batches : ArrayView[Array[SourceUpdate]],
) -> Array[SourceUpdate]
```

Reuse those functions. Do not bypass `Engine::begin_epoch`, `stage_batch`,
`close_input`, or `run_closed` in the exhaustive suite.

`test_assert_matches_oracle` is suitable only for epochs expected to publish:
it calls `test_unwrap_publication` and therefore fails on an expected invalid
retraction. The new suite needs a separate comparison helper that returns the
matching `Result` so Matrix A can inspect rejection atomicity.

### Existing rejection checks

`dataflow/property_wbtest.mbt:101-142` snapshots source, canonical
reachability, and publication count before each generated epoch, then confirms
that `InvalidSourceMultiplicity` preserves them. The exhaustive matrix extends
that pattern to worker arrangements, worker reachability/close state, latest
publication, queue emptiness, and recovery at epoch 2.

A rejected expected epoch advances lifecycle order to the following epoch. Do
not assert that `Engine.phase` or the trace is unchanged. The immutable domain
state and worker state must remain unchanged; the lifecycle must become
`Ready(2)`.

### Independent oracle boundary

`dataflow/oracle.mbt:135-169` independently consolidates updates, rejects
negative multiplicity, and recomputes closure with BFS. Keep it unchanged. The
new test may call only `Oracle::Oracle` and `Oracle::apply`; it must not share
encoding, consolidation, affected-origin, delta, routing, or worker helpers with
the oracle implementation.

### Worker state available to white-box tests

`dataflow/types.mbt:328-336` stores each worker's keyed arrangement,
reachability set, and `closed_epoch`. Because `WorkerState` contains mutable
maps and does not implement `Eq`, the new test needs a test-only canonical
snapshot value rather than comparing workers directly.

### Baseline

At planning time:

```text
NEW_MOON_MOD=0 moon test dataflow
+++ [40/0/40] Ok, passed!
Total tests: 20, passed: 20, failed: 0.
elapsed=0.82s
```

The exhaustive suite adds two test blocks, so the expected total is 22 test
blocks while the existing generated property still reports 40 successes.

## Existing API First / reuse check

### Project APIs to reuse

- `test_update` — construct raw signed source updates.
- `test_stage_batches` — exercise the real epoch shell.
- `test_flatten_batches` — present one logical epoch to the oracle.
- `test_engine_with_seed` — create the three representative worker/scheduler
  configurations.
- `Engine::{source_snapshot,reachable_snapshot,last_publication_snapshot,publication_count,is_quiescent}` — inspect shell invariants without exposing new production APIs.
- `canonical_reachable` and sorted `WeightedEdge` values — canonicalize only
  test snapshots; do not reuse engine algorithms in the oracle.
- `Oracle::{Oracle,apply}` — independent semantic authority.

`test_assert_matches_oracle` was checked but is not reused because expected
rejections are valid Matrix A outcomes and that helper unwraps only `Ok`.
`run_generated_trace` was checked but is not reused because it fixes a
five-epoch randomized workload rather than accepting an explicit state.

### MoonBit Core APIs checked

- Reuse `Array::filter_map` for encoded edge-to-update conversion.
- Reuse `Array::map`, `Array::mapi`, and `Array::rev` for snapshots and the
  representative batch layouts.
- Reuse `ArrayView` for read-only helper parameters.
- Reuse `Option` and `Result` pattern matching for expected publication versus
  structured rejection.
- `Int::until`, `Iter::map`, `Iter::flat_map`, and `Iter::to_array` were checked;
  prefer ordinary bounded `for` loops for the Cartesian product because they
  avoid materializing 5,424 scenario descriptors and make the exact dimensions
  visible.
- `HashMap` and `HashSet` were checked. Do not use them to encode source states:
  base-radix integer encoding is deterministic and allocation-light. Nested
  worker maps/sets must be traversed only to build canonical test snapshots.
- Persistent `Vector` was checked but needs no direct use in the new file;
  `Engine::stage_batch` performs the existing Array-to-Vector admission copy.
- Reuse prelude `debug_inspect` for expected/actual diagnostics on the first
  mismatch; `moon ide doc "debug_inspect"` confirms it accepts `Debug` values
  without adding a package import.
- `Buffer`/`StringBuilder`, `Bytes`, `Map`/`Set`, and numeric widening APIs are
  unnecessary here; overflow semantics belong to a separate plan.

### New test-only helpers and boundaries

Introduce only helpers that own exhaustive-test concerns:

1. encoded edge descriptors and integer-code-to-source conversion;
2. representative batching/configuration;
3. canonical worker snapshots;
4. one Engine/Oracle epoch comparison that preserves expected `Err` results;
5. deterministic case-context formatting for failures.

Do not add helpers to `core.mbt`, `engine.mbt`, `oracle.mbt`, or
`spike_wbtest.mbt`.

## Commands you will need

Run from the repository root with `NEW_MOON_MOD=0`.

| Purpose | Command | Expected on success |
|---|---|---|
| Baseline/typecheck | `NEW_MOON_MOD=0 moon check --deny-warn dataflow` | exit 0, no warnings/errors |
| Target tests | `NEW_MOON_MOD=0 moon test dataflow` | 22/22 blocks pass; generated property reports 40 successes |
| Format | `NEW_MOON_MOD=0 moon fmt` | exit 0 |
| Interfaces | `NEW_MOON_MOD=0 moon info` | exit 0 |
| Public-surface guard | `git diff -- dataflow/pkg.generated.mbti` | empty |
| Workspace boundary guard | `bash scripts/check-workspace-boundaries.sh` | exit 0 |
| Documentation checker self-test | `bash scripts/check-documentation-boundaries-selftest.sh` | exit 0 |
| Documentation boundaries | `python3 scripts/check-documentation-boundaries.py` | reports `Documentation boundaries OK` |
| Diff hygiene | `git status --short`; unstaged and cached `git diff --check`/`--stat` after intent-to-add and `git rm` | only in-scope paths; no whitespace errors |

For runtime evidence, measure the same command before and after:

```sh
/usr/bin/time -f 'elapsed=%e maxrss_kb=%M' \
  env NEW_MOON_MOD=0 moon test dataflow
```

## Scope

**In scope:**

- `dataflow/exhaustive_wbtest.mbt` — new exhaustive white-box suite.
- `dataflow/README.mbt.md` — add post-GO exhaustive evidence only after tests
  pass.
- `plans/README.md` — remove Plan 011 from the active table at close-out and
  record its test-only disposition.
- `plans/011-dataflow-exhaustive-tiny-state.md` — delete at close-out after all
  implementation and validation steps pass; Git history retains the plan.

**Out of scope:**

- `dataflow/types.mbt`, `core.mbt`, `engine.mbt`, and `oracle.mbt`.
- `dataflow/spike_wbtest.mbt` and `property_wbtest.mbt`.
- `dataflow/moon.pkg`, `moon.mod`, and `pkg.generated.mbti`.
- protocol-event generation, integer-overflow policy, larger graph traces, and
  benchmark changes.
- public API, adapters, Incr/EGW dependencies, networking, checkpointing,
  capabilities, partial-order time, and production claims.
- `graphify-out/`.

If the tests reveal a production defect, stop and report the smallest encoded
case; do not fix production code under this plan.

## Git workflow

- Branch: `advisor/011-dataflow-exhaustive-tiny-state`.
- Commit style: conventional commits with rationale, for example
  `test(dataflow): exhaust tiny graphs to remove sampling blind spots`.
- Do not push, open a PR, or publish the module without explicit operator
  instruction.

## Steps

### Step 1: Confirm baseline and drift

Run the drift check, `moon check --deny-warn dataflow`, and timed
`moon test dataflow`. Record the elapsed time in the eventual PR description,
not in source comments.

Confirm `dataflow/pkg.generated.mbti` contains headings only and no values,
errors, types, aliases, or traits.

**Verify:** baseline commands match the table above; currently 20 test blocks
pass.

### Step 2: Add deterministic state encoders

Create `dataflow/exhaustive_wbtest.mbt`. Begin with the file-role Doc comment,
then immediate why-focused `///` comments for every top-level helper. Test names
specify behavior; test block comments need no prose.

Define a private encoded-edge value containing an `Edge` and its positional
divisor. Use these canonical descriptors:

- Matrix A, radix 3: `(0,0)/1`, `(0,1)/3`, `(1,0)/9`, `(1,1)/27`.
- Matrix B, radix 2: row-major `(0,0)..(2,2)` with divisors
  `1,2,4,8,16,32,64,128,256`.

Add one conversion helper:

```text
encoded weight = (graph_code / divisor) % radix
```

Use `Array::filter_map` to emit `test_update(from, to, weight)` only when the
weight is positive. This produces canonical source-update order and avoids
mutable graph builders.

Add direct encoder sanity tests inside the two matrix test blocks before the
large loops:

- Matrix A code 0 produces no updates; code 80 produces all four edges at
  weight 2; codes 1, 3, 9, and 27 select the expected single edge.
- Matrix B code 0 produces no updates; code 511 produces all nine edges; codes
  1 and 256 select the first and last edge.

These assertions catch a broken radix mapping before thousands of oracle
comparisons obscure the cause.

**Verify:** `NEW_MOON_MOD=0 moon check --deny-warn dataflow` exits 0.

### Step 3: Add representative shell configuration and worker snapshots

Define three test-only configurations exactly as listed in "State space and
exact counts". Add a batching helper:

- whole canonical batch;
- one update per batch;
- one reversed batch.

Define the layouts exactly:

- canonical: `[updates.copy()]`, therefore `[[]]` for an empty source;
- per-update: `updates.map(update => [update])`, therefore `[]` for an empty
  source;
- reversed: `[updates.rev()]`, therefore `[[]]` for an empty source.

All three forms must close a valid empty epoch and flatten to empty oracle input.

Define a private `ExhaustiveWorkerSnapshot` with:

- worker id;
- canonical sorted `Array[WeightedEdge]` flattened from `edge_by_from`;
- canonical sorted worker-local reachability;
- `closed_epoch`.

Build snapshots with local Array builders while traversing nested mutable maps,
then sort before comparison. This local mutation is necessary to take an owned,
deterministic view of unordered worker state and must not escape the helper.
Derive `Eq` and `Debug` on the snapshot type.

**Verify:** `NEW_MOON_MOD=0 moon check --deny-warn dataflow` exits 0.

### Step 4: Add an Engine/Oracle comparison helper

Add a test-only helper that accepts Engine, Oracle, epoch, batches, and a
preformatted deterministic case label.

1. Compute `expected = oracle.apply(epoch, test_flatten_batches(batches))`.
2. Compute `actual = test_stage_batches(engine, epoch, batches)`.
3. If they differ, fail with the case label, matrix name, graph code, N, edge,
   diff, and epoch.
4. Return `actual` without unwrapping it.

Do not duplicate oracle consolidation or closure logic. Do not call
`test_assert_matches_oracle`, because it intentionally rejects expected `Err`
outcomes.

Use MoonBit string interpolation only for `Int`/`String` context, including
`edge.from` and `edge.to` separately. `Edge`, `Result`, and `Publication` derive
`Debug`, not `Show`; do not interpolate them directly. On the first mismatch,
call prelude `debug_inspect(expected)` and `debug_inspect(actual)`, then fail
with the bounded case label. Do not retain or print every successful scenario.

**Verify:** `NEW_MOON_MOD=0 moon check --deny-warn dataflow` exits 0.

### Step 5: Implement Matrix A

Add:

```moonbit
test "exhaustive two-node weighted transitions match oracle and preserve rejection atomicity"
```

Loop in this deterministic order:

1. `graph_code` in `0..<81`;
2. edge descriptor in canonical Matrix A order;
3. diff in `[-2, -1, 1, 2]`;
4. configuration in N=`1,2,4` order.

For each scenario:

1. Create a fresh Engine and Oracle.
2. Encode the source graph and run epoch 0 under the configuration's batching
   layout. Require matching `Ok` results.
3. Snapshot canonical source, canonical materialization, canonical workers,
   latest publication, and publication count.
4. Apply the one-edge diff at epoch 1 and compare Engine/Oracle results.
5. On `Ok`, require quiescence and every worker closed at epoch 1.
6. On `Err(InvalidSourceMultiplicity(_, _))`, require:
   - source snapshot unchanged;
   - reachability snapshot unchanged;
   - canonical worker snapshots unchanged;
   - latest publication and publication count unchanged;
   - transport and all mailboxes empty via `is_quiescent()`;
   - lifecycle is `Ready(2)`.
7. Reject every other error variant as an exhaustive-suite failure.
8. After the rejection invariants pass, run an empty epoch 2 through both
   Engine and Oracle and require matching `Ok`; this proves recovery without
   changing the graph.
9. Increment a local scenario counter.

The mutable counter and bounded nested loops are justified: they expose the
Cartesian product directly without allocating a scenario array. At the end,
require exactly **3,888** scenarios.

**Verify:** run `moon test dataflow`; Matrix A passes and reports no mismatch.

### Step 6: Implement Matrix B

Add:

```moonbit
test "exhaustive three-node boolean closures match oracle at N=1/2/4"
```

Loop over `graph_code` in `0..<512`, then the three configurations. For each
scenario, create a fresh Engine and Oracle, encode the source, and compare epoch
0. Require matching `Ok`, quiescence, and all workers closed at epoch 0.
Increment a local counter and require exactly **1,536** scenarios.

Matrix B proves closure over all three-node Boolean graph shapes; it does not
apply second-epoch toggles. Do not silently expand it into `512 × 9` transitions
without a new runtime/benefit review.

**Verify:** `moon test dataflow` passes both new blocks; total is 22/22 and the
existing QuickCheck property still reaches 40 successes.

### Step 7: Measure runtime without weakening coverage

Run one discarded warm-up, then two exact timed invocations:

```sh
env NEW_MOON_MOD=0 moon test dataflow >/dev/null
/usr/bin/time -f 'run=1 elapsed=%e maxrss_kb=%M' \
  env NEW_MOON_MOD=0 moon test dataflow
/usr/bin/time -f 'run=2 elapsed=%e maxrss_kb=%M' \
  env NEW_MOON_MOD=0 moon test dataflow
```

The planning baseline was 0.82 seconds before the exhaustive file.

- If both measured runs are at or below 15 seconds, continue.
- If either exceeds 15 seconds, stop and report both timings, scenario counts,
  and profiler-free observations. Do not sample, reduce worker counts, merge
  state cases, mark tests skipped, or move them out of CI.
- Record `maxrss_kb` for review, but do not enforce an unspecified memory limit.

This is a manual review gate for CI cost, not a performance target or a CI
runtime assertion.

### Step 8: Record evidence in the module README

After all 5,424 scenarios pass, add a concise "Post-GO exhaustive evidence"
subsection to `dataflow/README.mbt.md`. Record:

- Matrix A's 3,888 scenarios and two-epoch weighted transition semantics;
- Matrix B's 1,536 scenarios and exhaustive three-node Boolean closure;
- N=1/2/4 representative shell configurations;
- independent oracle agreement and rejection atomicity/recovery checks;
- measured local test time as an observation, not an acceptance claim.

Do not call this model checking beyond the explicitly enumerated state spaces.
Do not update the ADR: its boundary and Phase 0 decision remain unchanged.

**Verify:** `git diff --check` produces no output.

### Step 9: Close the plan and run final gates

After Steps 1–8 pass:

1. Run `git rm plans/011-dataflow-exhaustive-tiny-state.md` so Git and the
   documentation checker both see the plan as removed.
2. Remove Plan 011 from the active table in `plans/README.md` and remove/rewrite
   the active prose saying that Plan 011 may execute independently.
3. Add a concise reconciliation note stating that the deterministic 5,424-case
   matrix completed, the module README retains the evidence, and **No ADR is
   needed because the change is test-only and preserves the accepted boundary**.
4. Mark the new untracked test as intent-to-add so unstaged diff checks include
   it: `git add -N dataflow/exhaustive_wbtest.mbt`.

Then run, in order:

```sh
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
NEW_MOON_MOD=0 moon check --deny-warn dataflow
NEW_MOON_MOD=0 moon test dataflow
bash scripts/check-workspace-boundaries.sh
bash scripts/check-documentation-boundaries-selftest.sh
python3 scripts/check-documentation-boundaries.py
git status --short
git diff --check
git diff --stat
git diff --cached --check
git diff --cached --stat
git diff -- dataflow/pkg.generated.mbti
```

Confirm status/diff show only the new exhaustive test, module README, Plan 011
close-out metadata, and deletion of this plan. The generated interface diff
must be empty.

## Test plan

Two new white-box test blocks in `dataflow/exhaustive_wbtest.mbt`:

1. weighted two-node transitions: 3,888 deterministic scenarios, including
   valid updates, invalid retractions, support thresholds, self-loops, and
   two-cycles, with full rejection atomicity and recovery checks;
2. Boolean three-node closure: 1,536 deterministic scenarios covering every
   directed self-edge/cycle/alternate-path graph at N=1/2/4.

The independent oracle remains the expected-result authority. Encoder sanity
assertions guard the test generator itself. Existing table and QuickCheck tests
remain unchanged.

## Done criteria

All must hold:

- [ ] `dataflow/exhaustive_wbtest.mbt` contains exactly the two named test blocks.
- [ ] Matrix A asserts exactly 3,888 scenarios.
- [ ] Matrix B asserts exactly 1,536 scenarios.
- [ ] Every Engine result matches `Oracle::apply`.
- [ ] Invalid epoch-1 retractions preserve source, reachability, canonical
      worker state, latest publication, publication count, and empty queues;
      lifecycle advances to `Ready(2)` and an empty epoch 2 succeeds.
- [ ] Two warm timed runs are each at or below 15 seconds, or execution has
      stopped for review without reducing coverage.
- [ ] `moon check --deny-warn dataflow` exits 0.
- [ ] `moon test dataflow` reports 22/22 test blocks and 40 generated successes.
- [ ] `moon fmt` and `moon info` exit 0.
- [ ] `git diff -- dataflow/pkg.generated.mbti` is empty.
- [ ] Workspace boundary and whitespace checks pass.
- [ ] `dataflow/README.mbt.md` records only the bounded evidence actually run.
- [ ] No production source, package manifest, public API, or out-of-scope file
      changed.
- [ ] Plan 011 is deleted after successful implementation, its active-table row
      is removed, and `plans/README.md` records the completion and no-ADR
      decision.

## STOP conditions

Stop and report instead of improvising if:

- any file in the drift check changed semantically after `e925853`;
- `_wbtest.mbt` cannot access the existing private helpers or worker fields
  without changing a production/package boundary;
- encoded sanity assertions fail;
- Engine and Oracle disagree for any case — use `debug_inspect` for expected
  and actual, then report matrix, graph code, decoded source, N, batch mode,
  edge coordinates, diff, and epoch;
- an invalid epoch mutates source, materialization, workers, publication, or
  queues, or fails to advance to `Ready(2)`;
- a new test exposes a production defect; do not patch `core.mbt`, `engine.mbt`,
  `oracle.mbt`, or `types.mbt` under this plan;
- the exhaustive target suite exceeds the runtime gate;
- `moon info` changes `dataflow/pkg.generated.mbti`;
- implementation requires a new dependency, package import, public item,
  benchmark, adapter, or protocol/overflow change.

## Maintenance notes

- Keep matrix counts and README evidence synchronized if the finite domains are
  deliberately changed later.
- Reviewers should decode at least graph codes 0/max and one single-edge code
  for each radix before trusting the matrix.
- The suite protects only the stated two-node weighted transitions and
  three-node Boolean closures. It does not replace generated longer traces,
  protocol-adversarial testing, overflow semantics, or scale measurements.
- Future protocol and overflow work should receive separate plans so a defect
  found here cannot broaden this test-only change into production edits.
