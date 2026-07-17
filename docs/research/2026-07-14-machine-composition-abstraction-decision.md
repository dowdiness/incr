# Machine composition abstraction decision

**Date:** 2026-07-14

**Decision:** Keep machine composition as ordinary pure functions and small
domain types. Do not add a `Machine` type, per-key reactive graph, or `incr`
public API.

**Follow-up (2026-07-15):** The shared-abstraction decision remains unchanged,
but the original fixture's duplicated request-sequence storage was not a safe
endpoint. It has been removed locally, and the candidate vocabulary, extraction
triggers, and UX defect tests below are registered before a second driver is
implemented.

## Primary driver result

The semantic-editor fixture demonstrates one deterministic parent transition
covering routed child edits, selection, add/remove/reorder, history restoration,
and validation commands. `(ChildId, Incarnation, RequestSeq)` rejects missing,
retired, superseded, duplicate, and unexpected completions. One aggregate
`Program::stateful_cmd` owns one version input, one watched view root, and one
stable dependency across child churn.

The [dated measurement](../performance/2026-07-14-machine-composition-evidence.md)
passes all structural gates and all three 256-child p95 runs remain below the
16.7 ms synchronous JS budget. There is no measured performance driver for
per-key ownership.

## Circle Drawer comparison

The natural Circle Drawer implementation in
`examples/incr_tea_7guis/circle_drawer/circle_drawer.mbt` repeats these
responsibilities without adopting the primary fixture's protocol:

- `update_model` is a pure reducer over an aggregate model;
- circle IDs remain stable while array position changes;
- `selected` is a small state lens routing `SetRadius` to one circle;
- undo removes circles and redo restores the same semantic IDs.

It does not repeat validation commands, asynchronous completion routing,
incarnation allocation, request sequencing, or stale-result classification.
Its redo operation restores historical semantic state directly; adding mounted
lifetime tokens solely for comparison would manufacture the proposed
abstraction rather than confirm it.

## Responsibility decision

| Responsibility | Repeats naturally? | Decision |
|---|---|---|
| Pure aggregate reducer | Yes | Keep as a function |
| Stable semantic identity | Yes | Keep as a domain ID field |
| Selected-child state lens | Yes | Keep as a small lookup/update helper |
| History restoration | Yes | Keep policy explicit in each domain |
| Command mapping | No | No shared abstraction |
| Incarnation and stale-result protocol | No | Keep fixture/domain-specific |
| Lifecycle ownership | No per child | Keep one aggregate Program/Scope |

The naturally repeated code does not yet justify a generic type. A future
proposal must present another application-shaped driver that naturally repeats
the command/lifetime protocol, demonstrate a compile-time safety improvement
against the defect catalogue below, or show a measured failure of the aggregate
design.

## Local invariant correction

The first implementation stored the latest request sequence both in
`MachineValidation` and in `MachineChild::latest_request_seq`. That made a
pending sequence and the completion-classification sequence independently
representable, so a drift could silently misclassify a completion. The fixture
now stores the sequence only in `MachineValidation`; edits and restores derive
the next sequence from that value, and validation commands can only be created
from `MachinePending(seq)`.

This is a correction to the evidence driver, not a shared abstraction. The
snapshot type continues to omit the monotonic incarnation allocator by
construction.

## Deferred abstraction candidate

If a second real consumer repeats the same semantics, the first extraction to
evaluate is deliberately narrow:

- a request token whose fields can be read across a package boundary but cannot
  be reconstructed there;
- one pure completion-classification function with an explicit accepted,
  retired, superseded, duplicate, and unexpected result.

Request issuance, retirement, cancellation, restore policy, command mapping,
and lifecycle ownership remain domain decisions. A full `Machine` becomes a
candidate only if those shell responsibilities also repeat naturally.

Extraction requires all of the following:

1. the vocabulary is domain-independent across the real consumers without
   discarding per-command ordering, cancellation, retry, or streaming meaning;
2. the unabstracted misuse can produce a silent failure;
3. MoonBit visibility or representation choices can make that misuse a compile
   error rather than merely move it behind a helper;
4. either two real consumers exist, or one production consumer has a
   compile-time invariant that documentation and local representation cannot
   protect.

The planned fixed-replay/request-lifecycle slice of Incremental Generative UI
is the next natural candidate consumer. Typed Spreadsheet may compare
draft/valid/invalid state shape, but it does not count as a second token
consumer unless retirement and asynchronous completion arise from its own
requirements. Circle Drawer must remain in its natural form.

## Pre-registered developer-UX defect catalogue

Before implementing an abstraction variant, inject the same defects into the
ordinary domain version and the candidate vocabulary version. Record each
outcome as `compile error`, `test failure`, or `silent failure`.

| Defect | Safety question |
|---|---|
| pending sequence drifts from the latest sequence | Can there be more than one source of truth? |
| superseded and retired checks are reordered | Does classification silently accept or mislabel old work? |
| a new incarnation reuses an unintended sequence policy | Is reset/continuation explicit per domain? |
| the monotonic allocator is restored from a snapshot | Can history resurrect an old lifetime? |
| the shell reconstructs an issued token | Can exact-token carry be enforced by visibility? |
| a completion is accepted after cancellation | Is cancellation part of the classified state? |
| a second command kind shares the wrong ordering cursor | Does the vocabulary support per-kind policy without distortion? |

The primary UX signal is the number of defects moved from `silent failure` to
`compile error`, not source-line reduction. Pre-register change tasks for a
second command kind, cancellation, and per-child retry; compare the number of
invariant-bearing edit sites and independently review a seeded-defect diff.

## Conditions that change the decision

Extract the narrow vocabulary when a second real consumer independently starts
to implement the same classification procedure, or when the defect experiment
shows that the candidate representation converts a silent production-shaped
failure into a compile error. Reconsider a full `Machine` only when lifecycle
and shell wiring repeat as well.

Continue waiting when the next consumer instead needs materially different
semantics, such as per-command ordering, cancellation acknowledgement, or a
streaming request tree. That result is evidence that fixing the first fixture's
meaning in a shared API would have been premature.
