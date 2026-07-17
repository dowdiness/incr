# Machine Composition Evidence Driver Plan

**Date:** 2026-07-14

**Status:** Completed. The aggregate design passed its structural and timing
gates; no `Machine` type, per-key reactive variant, or `incr` core API was
added. A 2026-07-15 follow-up removed duplicated request-sequence state and
pre-registered developer-UX extraction gates without changing that decision.
PR hardening then made the deterministic browser gates permanent in CI,
removed package-wide warning suppression, and replaced the browser-global
property hook with a private typed observer seam.

**Revised against:** `bd8e2a8` (2026-07-14).

**Direction:**
[Machine semantics start gates](../research/2026-07-14-machine-layer-start-gates.md).

**Boundary constraint:**
[`incr_tea` module identity ADR](../decisions/2026-07-03-incr-tea-module-identity.md).

**Results:**
[performance snapshot](../performance/2026-07-14-machine-composition-evidence.md),
[invariant and instrumentation follow-up](../performance/2026-07-15-machine-composition-follow-up.md),
[abstraction decision](../research/2026-07-14-machine-composition-abstraction-decision.md),
and [implementation report](../research/2026-07-14-machine-composition-implementation-report.md).

## Goal

Determine whether ordinary pure functions plus the existing
`Program::stateful_cmd` surface are sufficient for parent/child Machine
composition, semantic identity, retirement, and stale-command rejection.

Produce evidence before designing a `Machine` type or allocating one reactive
subgraph per child.

## Non-goals

- no `incr` public API changes;
- no new `Machine` trait or universal component type;
- no `DerivedMap::evict`, `Scope::child` detachment, or keyed core facade;
- no per-child `Input`, `Derived`, `Watch`, or `Scope` in the baseline;
- no renderer rewrite;
- no generic multi-command request protocol in the first fixture;
- no timing threshold in CI;
- no retrofit of Machine semantics into 7GUIs merely to manufacture a second
  confirming driver;
- no generative-UI runtime;
- no claim that #399 is solved by this experiment.

## Existing assets and the new-work boundary

`incr_tea/browser_editor_demo.mbt` already demonstrates semantic keys and
multiple view roots, and its DOM shape is the closest existing application
fixture. It does not contain the pure transition required by this plan: its
update closure and model methods mutate `InputField` values directly, it has a
fixed three-node collection, and it has no add/remove, command, asynchronous
completion, incarnation, or request-sequence behavior. Reuse therefore means:

- reuse its semantic-editor vocabulary, row/selection/inspector shape, DOM
  event patterns, and renderer counters;
- implement the pure model, transition, lifetime tokens, and stale-result
  semantics first in a dedicated test fixture;
- after the pure and Program layers pass, promote that dependency-free core
  into a package-private non-test file shared by the tests and browser fixture.
  The promoted file must remain free of Runtime, DOM, clock, and asynchronous
  dependencies; do not make the existing demo a larger package-private
  dependency.

`incr_tea/ui_compare_dom_keyed_list_bench.mbt` is a renderer-layer reference
for keyed prepend/remove/reorder. It is not the application-shaped measurement
for this plan because it has no editable row state, selection, or inspector.
The typed-spreadsheet `incr_tea` demo remains contextual multi-root/locality
evidence unless a bounded pure transition slice is extracted and tested.
7GUIs Circle Drawer is a natural second-driver candidate because it already has
a pure `update_model`, stable circle IDs, selection, and undo/redo; it must be
reviewed in its existing form rather than extended with artificial command or
incarnation machinery.

The first slice therefore belongs in a dedicated test-only fixture. It may
reuse the semantic-editor scenario, but it must not make the existing demo a
larger package-private dependency. Promotion of the proven pure core into the
package-private shared file is an explicit prerequisite for the later browser
fixture, not a second implementation of the transition.

### Implementation locations

Keep this experiment identifiable and removable. Use these files rather than
folding it into the existing editor demo:

- `incr_tea/machine_composition_wbtest.mbt` for WP1 and WP2 tests. WP1 may
  define the core here initially;
- `incr_tea/machine_composition_fixture.mbt` for the package-private pure core
  after promotion before WP3. Move the already-tested definitions; do not
  maintain test and browser copies;
- `incr_tea/machine_composition_program.mbt` for the shared aggregate Program
  adapter, inspectable view projection, and optional measurement hooks;
- `incr_tea/machine_composition_dom_bench.mbt` for the JS-only editor harness;
- package-private instrumentation seams in `incr_tea/dom_bench.mbt` and
  `incr_tea/renderer_js.mbt`. Do not change `RenderStats` or another public
  renderer signature;
- `examples/incr_tea/scripts/test-machine-composition.mjs` and
  `examples/incr_tea/scripts/bench-machine-composition.mjs` for browser
  structural assertions and raw measurements, with corresponding private npm
  scripts in `examples/incr_tea/package.json`;
- `docs/performance/2026-07-14-machine-composition-evidence.md` for the dated
  snapshot and `docs/README.md` for its index entry;
- `docs/research/2026-07-14-machine-composition-abstraction-decision.md` for
  WP4 and `docs/README.md` for its index entry.

Existing editor, spreadsheet, keyed-list, and Circle Drawer source files are
read-only evidence for this experiment. Instrumentation-only changes to the two
renderer files above are allowed; renderer reconciliation behavior is not.

## Baseline model

Use immutable returned values or defensive copies for collections crossing the
transition boundary. Local mutation while constructing a returned value is
acceptable when it is unobservable.

The fixture needs these concepts; exact public type names are deliberately not
prescribed:

```text
ChildId          stable semantic identity
Incarnation      changes when a removed ID is reused
RequestSeq       orders requests within one mounted lifetime
ValidationToken  ChildId + Incarnation + RequestSeq
Validation       Pending(seq) | Valid(seq) | Invalid(seq, diagnostic)
ChildModel       local editable state + validation (the sole request-sequence source)
ParentModel      ordered child IDs + child records + next incarnation
HistorySnapshot  order + selected ID + semantic child data only
ChildAction      edits local state or requests a command
ParentAction     routes child actions and performs add/remove/reorder/restore
CommandDescription  pure ValidateText(token, text) data
CommandResult    carries the full ValidationToken back to the parent
Decision         Applied | Ignored(reason) | Rejected(reason)
```

`ChildId` preserves logical identity across reorder. `(ChildId, Incarnation)`
identifies one mounted lifetime and prevents a late result from an old child
from mutating a replacement that reused the same ID. `RequestSeq` prevents an
older request in the same lifetime from overwriting a newer result.

The fixture has exactly one command kind, text validation. Latest-only ordering
is therefore per child. Do not generalize this into a child-wide protocol for
multiple command kinds: if a later driver needs independent validation and
rename requests, ordering must be per `(ChildId, CommandKind)`.

The functional core has the conceptual boundary:

```text
ParentModel + ParentAction
  -> ParentModel + Array[CommandDescription] + Decision
```

The command description is data. It must not read a clock, start asynchronous
work, mutate an `incr` Runtime, or retain a callback.

### User-action decision contract

`Decision` classifies the parent event, not every child reconciliation within
that event. Every accepted edit, add, remove, reorder, or restore returns one
`Applied`, even when restore reconciles several children. Tests observe those
per-child restore outcomes in the returned model and emitted command array,
not by expanding `Decision` into a list. An action targeting a missing child is
`IgnoredMissingChild`; adding an already-live ID is `IgnoredDuplicateId`; and
an exact semantic no-op is `IgnoredNoChange`. A malformed reorder containing
duplicate or unknown IDs is `RejectedInvalidAction`. Ignored and rejected user
actions leave the model unchanged and emit no command. This defines decisions
for every event in a complete replay while keeping completion classification
separate.

### Validation result contract

Editing a child increments its request sequence, stores `Pending(seq)`, and
emits `ValidateText({ child_id, incarnation, seq }, edited_text)`. A completion
is classified in this order:

1. no live child for `ChildId` -> `IgnoredMissingChild`;
2. incarnation mismatch -> `IgnoredRetiredIncarnation`;
3. `seq < latest_seq` -> `IgnoredSuperseded`;
4. `seq > latest_seq` -> `RejectedUnexpected`;
5. equal sequence but validation is no longer `Pending` ->
   `IgnoredDuplicate`;
6. equal sequence and `Pending` -> `Applied` and overwrite the validation
   result slot.

`Ignored` and `Rejected` are distinct decision variants. A normal replay must
never produce `RejectedUnexpected`; that result signals an invalid shell,
fixture, or event log rather than benign lateness. Sequence values reset for a
new incarnation and are compared only after the incarnation matches.

Applying a command result is overwrite-only domain state. It must not append an
undo entry, increment an applied-result counter, or append an arrival log to the
model. Arrival diagnostics belong in the test observer or imperative shell.

### Replay and quiescence contract

The replay input is the complete event stream: user actions plus validation
completions. Identical initial state and identical event stream must produce
identical state, command descriptions, and decisions.

A weaker, separate convergence property covers completion reordering. For
permutations where every completion occurs after its issuing action, after all
in-flight completions are delivered (quiescence), result-derived fields must be
a function only of the user-action sequence and the latest result for each live
`(ChildId, Incarnation)`. Intermediate decisions and the multiset of `Applied`
decisions may differ. Generate exactly one canonical result payload per issued
token; if duplicate deliveries are included, every duplicate for that token
must carry the same payload. Conflicting payloads for one token are an invalid
event log and are outside the convergence claim. Property tests compare final
state only.

### Removal, reuse, and history restoration

The incarnation allocator is monotonic state outside undo/redo snapshots.
`HistorySnapshot` contains order, selection, IDs, and editable semantic data;
it excludes incarnations, request sequences, validation state, allocator state,
and arrival diagnostics. Restoring a snapshot reconciles that semantic data
against the currently live model rather than replacing `ParentModel` wholesale.
The primary fixture does not implement an undo stack: a pure
`snapshot(model) -> HistorySnapshot` helper captures semantic state, and an
explicit `Restore(snapshot)` action exercises reconciliation. Allocator and
lifecycle state remain only in `ParentModel`.
Explicit ID reuse and history restoration compare the live ID sets before and
after restoration:

- live before and live after: preserve the current incarnation;
- dead before and live after: allocate a new incarnation;
- live before and dead after: retire the current incarnation.

Restored records never copy a historical validation state. Every dead-to-live
record starts at sequence 1, enters `Pending(1)`, and emits a new
`ValidateText` command for the restored text. A live-to-live record preserves
its incarnation; if restoration changes its text, it increments its current
sequence and revalidates, while unchanged text preserves the current validation
state. A completion for a historical incarnation is
`IgnoredRetiredIncarnation`, and a completion for pre-restore text in a
continuous incarnation is `IgnoredSuperseded`. These rules prevent a restored
record from waiting forever for a result that can no longer be accepted.

Adding a new ID follows the same new-mounted-lifetime rule as dead-to-live
restore: allocate a fresh incarnation, start at sequence 1, store
`Pending(1)`, and emit `ValidateText` for the supplied initial text. It does
not wait for a later edit before validating.

## Work package 1: pure transition semantics

Create a test-only parent/child transition with no Runtime dependency.

Required tests:

1. a routed child action changes only the named child;
2. reorder preserves every surviving child's local state;
3. removal deletes the child and repairs selection/focus metadata
   deterministically;
4. adding a new ID creates a fresh incarnation at `Pending(1)` and emits its
   initial validation command;
5. removing then reusing an ID allocates a new incarnation;
6. editing emits a token carrying the live child ID, incarnation, next
   sequence, and an immutable text snapshot;
7. a current pending result is `Applied`;
8. missing-child, retired-incarnation, superseded, duplicate, and unexpected
   future results produce their exact decisions and do not mutate the model;
9. a new incarnation resets sequence ordering without comparing it to the old
   incarnation's sequence;
10. restoring a dead ID assigns a new incarnation, reissues validation, and
    rejects the historical completion; IDs live across the restore retain their
    current incarnation;
11. replaying the same initial model and complete event stream produces the
    same final model, command descriptions, and decisions;
12. property-generated legal completion permutations converge at quiescence
    on the same final result-derived state;
13. every user-action decision case is exact, and ignored or rejected actions
    leave both model and command array unchanged.

### Exit condition

All semantics are testable without `@incr`, DOM, clocks, or asynchronous
execution. If this is not possible, record the exact impurity before designing
an abstraction around it.

## Work package 2: existing Program integration

Wrap the pure transition with `Program::stateful_cmd` using:

- one Program-owned model;
- one version `InputField` created by the existing constructor;
- one terminal `Derived` view and persistent, primed `Watch`;
- one Program `Scope`;
- command interpretation at the Program shell. The shell simulates deferred
  validation and returns the full `ValidationToken`; it must not reconstruct a
  token from current model state;
- a test-only decision observer injected into the update adapter. The adapter
  invokes the pure transition, sends its `Decision` to this external observer,
  and returns only `(next_model, command)` to `Program::stateful_cmd`; decisions
  and arrival logs must not be stored in the domain model;
- a view projection containing the inspectable semantic model fields used by
  the integration assertions, because `Program::stateful_cmd` exposes the view
  rather than its private model.

Required tests:

1. dispatch produces the same state/view sequence as direct pure replay;
2. `Runtime::gc()` before and during use does not sweep the watched graph;
3. Program disposal makes later dispatch deterministic and harmless;
4. simulated deferred completion carries child ID, incarnation, and request
   sequence, and exercises current, superseded, duplicate, retired, and
   unexpected-result decisions through dispatch. The normal shell must carry
   the exact issued token unchanged; only the test harness may directly inject
   a corrupt future-sequence completion to exercise `RejectedUnexpected`;
5. a white-box Program test records the existing `_view_id` and verifies that
   repeated child churn keeps the same view root, a stable dependency count
   through `Runtime::cell_info`, and `Runtime::gc_root_count(view_id) == 1`;
6. disposal changes `Runtime::gc_root_count(view_id)` to zero and makes the
   disposed view unavailable through introspection;
7. after each churn wave, the ordered IDs and child-record collection contain
   exactly the current live children, with no retired incarnation retained.

### Exit condition

The aggregate Program preserves the pure semantics and owns a bounded reactive
graph independent of historical child count.

## Work package 3: application-shaped measurement

Measure the aggregate design before proposing per-key reactivity. Use the
semantic-editor shape already present in the repository: editable keyed rows,
selection, reorder, add/remove, and an inspector-like projection.

Record at representative live sizes, including at least 64 and 256 children:

- transition time for one local edit;
- view recomputation time;
- DOM patch time when a browser fixture is used;
- the known Program view root's identity, dependency count, and GC-root count;
- live model cardinality after repeated add/remove/reuse waves;
- state and DOM identity preservation across reorder.

The browser measurement must use an editor-shaped fixture with editable row
state, selection, and an inspector projection. The existing keyed-list harness
is a renderer reference only; do not substitute its prepend/remove/reverse
numbers for this measurement. Add an `edit -> flush` operation that records raw
per-iteration elapsed values rather than only averages of iteration batches.

Instrument three explicit shell seams with the same monotonic browser clock:

1. wrap the pure transition call inside the Program update adapter for
   `transition_us`;
2. wrap the semantic view-projection body for `view_us`;
3. wrap the renderer's patch/apply call, excluding browser layout and paint,
   for `dom_patch_us`.

The outer edit-dispatch-through-flush interval is `flush_total_us`. Emit one
raw record per iteration with at least
`{ iteration, child_count, transition_us, view_us, dom_patch_us,
flush_total_us, created_nodes, removed_nodes, moved_nodes,
property_mutations_by_target, transition_calls, view_calls, patch_calls }`.
`property_mutations_by_target` is keyed by row semantic ID or the inspector
region. Warm-up records must be tagged or omitted consistently,
and the dated snapshot must state whether nested seam timings leave any
unattributed shell overhead. Disable the test-only decision observer while
collecting timings so observer bookkeeping is not charged to the transition.
Reset accumulators at the start of each iteration and sum all invocations of a
seam until that iteration's flush completes. Record the invocation count for
each seam as well; a local-edit sample is invalid unless it observes exactly one
transition, while multiple view or patch invocations must remain visible rather
than being overwritten by the last call.

These operation counters are new test/benchmark instrumentation, not existing
renderer counters and not a renderer rewrite. Derive created and removed row
counts from `KeyedPlan.steps` entries without a reused node and
`KeyedPlan.removals`; derive moves by comparing reused-node positions. Add a
bench-only applier observer for property/text mutations that records the
nearest row `data-semantic-id`, or the inspector region when no row owns the
target. Keep this observer out of the public renderer API and disable it
outside structural tests and measurements. The existing `patch_attempts` and
`skipped_patches` counters remain contextual totals rather than substitutes
for these new counters.

### Pre-registered gates

The following structural gates are deterministic and belong in ordinary tests:

- the view root ID, its dependency count, and one GC root stay constant across
  child churn, then the GC root reaches zero on disposal;
- the aggregate fixture constructs no reactive cells during dispatch; pin the
  known Program-owned root and dependency identities rather than adding a
  public total-cell-count API;
- model cardinality equals the live child set after every churn wave;
- one local edit creates, removes, and moves zero keyed row DOM nodes;
- the bench-only applier attribution records property/text mutations only for
  the edited row's semantic ID or the inspector region; existing browser
  identity assertions independently verify that untouched semantic-ID nodes
  retain identity;
- stale or duplicate completions perform no DOM work when they leave the view
  equal.

The timing gate is recorded in a new dated performance snapshot, not CI:

- at 256 live children, local `edit -> flush` p95 must be below the 16.7 ms
  JS-side frame budget;
- 8 ms is the stretch target, leaving the rest of the frame for browser layout
  and paint;
- record transition, view recomputation, and DOM patch time separately enough
  to attribute a miss;
- record the 64-to-256 scaling factor as diagnostic evidence only. Roughly 4x
  growth is not a failure when the absolute 256-child budget passes.

Capture per-iteration raw elapsed values after warm-up on an otherwise idle
host. Use at least 200 unrecorded warm-up edits followed by 1,000 recorded edits
at each size, and repeat the run three times. Record host, browser version,
target, toolchain, sample count, p50, and p95 for each run in the dated
snapshot. The gate passes only when all three 256-child runs have p95 below
16.7 ms; pooled percentiles may be reported as context but do not decide the
gate. The 16.7 ms gate covers synchronous JS through DOM mutation only; it does
not prove end-to-end 60-fps rendering because layout and paint are excluded.
Do not convert these thresholds into a flaky CI timing assertion.

For attribution, a component dominates only when it is the largest attributed
component and exceeds half of `flush_total_us` in at least 75% of the slowest
5% of recorded samples. If the gate misses without a dominant component, or
unattributed shell overhead exceeds half by the same rule, report the result as
inconclusive and stop instead of selecting a renderer or per-key response.

Use known-root, dependency, and model-cardinality assertions as the primary
lifetime evidence available at the `incr_tea` boundary. The aggregate baseline
does not allocate cells during child dispatch, so do not claim or infer total
Runtime slot counts from this fixture. Timing is secondary and must be stored
in a new dated performance snapshot rather than appended to an unrelated
baseline.

### Exit condition

The result states one of:

- all structural gates pass and 256-child p95 is below 16.7 ms: aggregate
  composition meets the synchronous JS-side target; stop without a per-key
  reactive design;
- the timing gate misses and DOM patching dominates: improve the renderer or
  view partitioning, not core ownership;
- the timing gate misses and transition/view recomputation dominates:
  per-key reactive ownership is a plausible response;
- the timing gate misses without a dominant attributed component: record an
  inconclusive result and improve measurement before changing architecture;
- a structural gate fails: fix identity, ownership, or reconciliation before
  drawing any performance conclusion;
- the workload is still too artificial to authorize another layer.

## Work package 4: abstraction decision

Review this driver together with at least one other application-shaped driver
that actually exercises a pure parent/child transition and the same routing,
identity, or command protocol. The current typed spreadsheet is contextual
evidence only: it uses direct `InputField` mutation and does not qualify unless
a bounded pure-transition slice is extracted and tested separately.

Review 7GUIs Circle Drawer in its natural form as evidence for stable identity,
selected-child state access, and history restoration. Its redo path restores a
previously absent circle ID and therefore tests the semantic-ID versus mounted-
lifetime distinction. Do not add commands, incarnation fields, or artificial
parent/child wrappers merely to make it resemble the primary driver. If only
identity and state-lens behavior repeats, only those responsibilities are
abstraction candidates. The conclusion that command composition does not
repeat is valid evidence against a universal Machine abstraction.

Do not propose a `Machine` type unless both expose the same repeated protocol.
If they do, write a separate design that names the smallest shared
responsibility: action mapping, command mapping, state lenses, incarnation
handling, lifecycle ownership, or subscription composition.

The decision may be "pure functions remain sufficient." That is a successful
outcome.

## Conditional work package 5: per-key reactive variant

This package is not authorized by completion of packages 1–4 alone. Start only
when package 3 records a missed target caused by aggregate reactive work and a
per-key graph has a credible path to that target.

Before implementation, add a delta design covering:

- the owner and terminal root of each per-key graph;
- F7 behavior if a surviving cell can retain a retired dependency;
- removal, tombstone, or aggregate retirement protocol;
- #399 relevance to the intended bounded or unbounded workload;
- create/retire/recreate count assertions;
- the exact comparison against the aggregate baseline.

If the per-key experiment requires total live/free slot counts that public
introspection cannot provide, add a separate white-box probe alongside
`incr/cells` and the retention suite. Keep that instrumentation test-only; do
not widen the public Runtime API merely to execute this plan.

For a bounded product, publish the supported bound and measured ceiling. For a
general unbounded-lifetime claim, require #399 attribution and demonstrate
that engine-owned work converges on the live graph.

## Validation sequence

For any implementation of this plan:

1. `rtk moon fmt` -> exits 0.
2. `rtk moon test incr_tea/machine_composition_wbtest.mbt` -> all WP1 and
   WP2 tests pass.
3. `rtk moon check incr_tea` -> exits 0 with no diagnostics.
4. `rtk moon test incr_tea` -> all package tests pass.
5. `rtk npm --prefix examples/incr_tea run test:machine-composition` -> all
   structural DOM and identity assertions pass in Chromium. The same command
   runs in the `incr_tea-machine-composition-dom` CI job; timing thresholds do
   not run in CI.
6. `rtk npm --prefix examples/incr_tea run bench:machine-composition` -> emits
   the required raw records for 64 and 256 children; record the dated snapshot,
   but do not use a timing failure as a CI failure.
7. `rtk moon info` and public `.mbti` inspection only if a public surface
   changes. A public diff is unexpected and must be removed or treated as a
   STOP condition.
8. `rtk moon check` and `rtk moon test` -> both pass before final handoff.

## Deliverables

- a package-private pure composition fixture, first proven in the white-box
  test before promotion;
- aggregate Program integration tests;
- an editor-shaped browser measurement fixture with structural operation
  counters and raw per-iteration timings;
- a dated semantic-editor-shaped measurement snapshot with p50/p95 and
  transition/view/patch attribution;
- a Circle Drawer comparison that records which responsibilities repeat
  naturally and which do not;
- a short abstraction decision: functions remain sufficient, or a separate
  narrowly scoped design is warranted;
- no core API change unless a later gated proposal supplies independent
  evidence.

## STOP conditions

Stop and report instead of improvising if:

- the pure transition requires `@incr`, DOM, a clock, or an asynchronous
  callback;
- the shell cannot carry the exact issued token and would need to reconstruct
  it from current state;
- a restored record cannot be assigned a fresh incarnation without rewinding
  the monotonic allocator;
- the editor-shaped browser fixture cannot distinguish transition, view, and
  DOM patch cost well enough to attribute a 16.7 ms miss;
- the only way to obtain a second confirming driver is to add the proposed
  abstraction or command protocol to that driver first;
- implementation appears to require an `incr` public API, per-key reactive
  graph, renderer rewrite, or total Runtime slot-count API;
- a completion-permutation generator needs conflicting result payloads for the
  same token to make its claim pass;
- the final diff changes a public `.mbti` surface.
