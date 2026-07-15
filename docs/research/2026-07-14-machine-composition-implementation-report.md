# Machine composition implementation report

**Date:** 2026-07-14

**Specification:**
[Machine composition evidence driver](../plans/2026-07-14-machine-composition-evidence-driver.md)

## Implemented

### WP1 — pure transition

- package-private functional core with semantic child IDs, monotonic
  incarnations, request sequences, validation state, snapshots, commands, and
  exact decisions;
- deterministic add/remove/reorder/edit/select/restore/completion transitions;
- replay, legal completion-permutation, identity resurrection, no-op, malformed
  action, and result-classification tests.

### WP2 — aggregate Program

- shared `Program::stateful_cmd` adapter with an external decision/issued-command
  observer and inspectable view projection;
- exact-token command carry, direct corrupt-token test injection, GC-before-use,
  bounded dependency/root checks through churn, and idempotent disposal tests.

### WP3 — browser evidence

- editor-shaped keyed-row and inspector fixture;
- package-private transition/view/patch timing seams;
- bench-only MutationObserver plus controlled-property hook for semantic-target
  attribution and created/removed/moved row counts;
- Playwright structural test and raw 64/256-child benchmark workflow;
- dated performance snapshot. The aggregate design passed, so conditional WP5
  was not started.

### WP4 — abstraction decision

- natural-form Circle Drawer comparison;
- explicit decision to keep pure functions and domain types rather than add a
  `Machine` abstraction.

## Differences from the plan

1. The pure core was placed directly in the final package-private fixture file
   instead of first living in the white-box test and then being moved. The plan
   allowed this path (`WP1 may define the core` in the test); direct placement
   avoided a transient duplicate while preserving the dependency-free core.
2. The original targeted command
   `moon test -p incr_tea -f machine_composition_wbtest.mbt` executed zero tests
   with the installed Moon CLI. The plan was corrected to
   `moon test incr_tea/machine_composition_wbtest.mbt`, which executes all nine
   WP1/WP2 test blocks.
3. DOM operation attribution uses a browser `MutationObserver` plus narrow
   hooks for controlled value/boolean properties instead of deriving every
   count directly from `KeyedPlan`. This observes actual applied DOM work,
   distinguishes moves by node identity, and leaves reconciliation behavior and
   public renderer APIs unchanged.
4. Raw timing records are emitted to a configurable JSON path rather than
   embedded in the dated Markdown snapshot. The snapshot records all required
   p50/p95 summaries and the command to regenerate the 6,000 raw records.

No `incr` public API, public `incr_tea` signature, per-child reactive cell, or
per-key Scope was added.

## 2026-07-15 invariant follow-up

A post-implementation review found that `MachineChild` stored the latest
request sequence twice: in its validation variant and in a separate
`latest_request_seq` field. Although every transition updated the two values
together, the representation allowed them to drift and turn a malformed state
into a silent completion misclassification.

The follow-up:

- removed `latest_request_seq` from the core child and view projection;
- derives the next edit/restore sequence from the single validation state;
- permits validation-command construction only from `MachinePending(seq)`;
- added a transition test covering add, completion, edit, and restore sequence
  progression from that single source;
- retained the decision not to publish a shared abstraction;
- registered the narrow token/classifier candidate, extraction triggers, and a
  developer-UX defect catalogue in the abstraction decision.

This changed no public interface or runtime ownership model.

## Verification record

- `rtk moon update` — dependency registry and symbols updated successfully;
- `rtk moon fmt` — completed successfully;
- `rtk moon info` — completed; no `.mbti` diff;
- `rtk moon check --deny-warn` — passed;
- `rtk moon check --deny-warn --target js` — passed;
- `rtk moon test incr_tea/machine_composition_wbtest.mbt` — 10/10 passed;
- `rtk moon test incr_tea` — 112/112 passed;
- `rtk moon test` — wasm-gc 1,066/1,066 and JS 154/154 passed;
- `rtk npm --prefix examples/incr_tea run test:machine-composition` — passed
  edit, reorder, stale-result, duplicate-result, identity, and mutation-locality
  assertions;
- `rtk npm --prefix examples/incr_tea run bench:machine-composition` — 6,000
  recorded samples; after the invariant follow-up all three 256-child p95 runs
  passed (500, 500, and 200 µs versus the 16,700 µs gate). The original run is
  retained in the dated performance snapshot.

The benchmark raw output from the recorded run is at
`/tmp/incr-machine-composition-raw.json` and is reproducible through the command
above.

An additional advisory `--warn-list +73` workspace audit remains red on five
pre-existing unnecessary-annotation diagnostics in
`examples/spikes/ideal_api_rename_phase0/consumer/probes.mbt` and
`incr/types/intern_table.mbt`. None is in a machine-composition file; the normal
CI-matching `--deny-warn` checks above pass. This follow-up intentionally did not
modify those unrelated files.
