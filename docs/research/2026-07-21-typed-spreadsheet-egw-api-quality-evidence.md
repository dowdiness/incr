# Typed spreadsheet EGW API-quality evidence — 2026-07-21

**Reader:** Maintainers evaluating Plan 013, EGW issue #72, or a future
application-adapter API.

**Decision:** The published EGW 0.4 container API is sufficient for this adapter,
but it leaves concrete correctness and convenience work in the caller. Preserve
two narrow research candidates: error-transparent property mutation and a
conservative post-apply impact report. The current evidence does not authorize a
public API proposal.

**Keep until:** Plan 013 closes or a separate EGW ADR accepts or rejects the
candidate semantics.

**Disposition:** Compress durable conclusions into the linked ADR or later EGW
decision record, then delete this time-bounded research note. Git history is the
recovery path.

---

## Scope

This note evaluates API quality separately from the Phase 4 performance gate.
The unstable pre-adapter browser baseline blocks only a product-performance
conclusion. It does not erase correctness, misuse-resistance, convenience, or
second-driver evidence from the working adapter.

The comparison covers five axes:

1. **Correctness:** can a caller tell whether EGW recorded the requested work?
2. **Misuse resistance:** does the API prevent operation-level and visible-state
   meanings from being confused?
3. **Convenience:** how much safeguarding and state reconstruction must each
   consumer own?
4. **Generality:** does a candidate avoid spreadsheet, parser, and `incr`
   semantics?
5. **Performance:** can a candidate bound downstream work without claiming a
   product-level win prematurely?

No EGW source, public API, issue, or generic bridge is changed by this note.

## Current API result

The typed-spreadsheet adapter demonstrates that EGW 0.4 is sufficient for a
correct application-specific boundary. Existing white-box tests cover local and
remote authority ordering, dead application authority, read-back mismatch,
projection rollback and retry, duplicate and pending sync, concurrent writes,
delete races, malformed payload recovery, drafts, reset, and convergence.

That sufficiency depends on explicit shell safeguards:

- `seed_document` applies the application's `is_alive` policy, calls
  `Document::set_property`, and reads the value back.
- `EgwAdapter::write_and_project` repeats the liveness check and read-back before
  projecting the authoritative state.
- `EgwAdapter::apply_sync` receives operation counts from `SyncReport`, then
  scans all 2,500 canonical properties before computing semantic decisions.

The API therefore works, but the adapter must supply mutation confirmation and
post-apply impact discovery itself.

## Candidate A: error-transparent property mutation

### Verified current semantics

Published `Document::set_property` differs from container mutators such as
`delete_node` and `insert_text`:

- it returns `Unit` and has no public failure channel;
- it returns silently when the target is not contained in the tree;
- for a contained target, it catches and discards `DocumentError` raised while
  allocating, recording, or applying the property operation;
- it checks containment, not `Document::is_alive`.

The last point matters. `delete_node` moves a node to the trash; a trashed node
may remain contained. Whether the spreadsheet accepts a write to that node is
an application liveness policy, not the same question as whether EGW recorded a
property operation.

On the contained-target path, an identical value does not mean that no
operation occurred. When the internal mutation succeeds, `set_property` emits a
newly versioned property operation. Independently, the adapter test proves that
projection can report `NoSemanticChange` when the visible register value is
unchanged. A swallowed internal error would prevent the first fact, which is
why operation recording and semantic projection require separate evidence.

### Narrow candidate

The concrete candidate is an error-transparent property write: either an
additive checked setter or a compatible future signature that exposes
not-recorded/internal failure through `raise` or a typed result.

Its contract should answer only the EGW-owned question:

> Was the property operation recorded, or why could it not be recorded?

It should not decide whether a contained node is alive enough for a particular
application, nor whether an equal visible value constitutes a semantic change.
A stronger guarantee might remove failure-detection read-back, but an
application may still read back when it needs value confirmation.

### Why a rich receipt is not advanced

A receipt such as `Applied | AlreadyEqual | TargetDead` combines meanings that
are separate in the current model:

- `AlreadyEqual` can still correspond to a newly recorded causal operation;
- `TargetDead` embeds an application liveness policy into a containment-based
  CRDT operation;
- `Applied` can mean recorded, selected by LWW, present on a contained node, or
  semantically relevant to a projection.

No single interpretation has driver evidence. The rich receipt shape is
therefore deferred rather than treated as the mutation candidate.

## Candidate B: conservative post-apply impact reporting

### Verified current semantics

`SyncReport` exposes counts for applied tree operations, applied text
operations, duplicates, and remaining pending operations. It does not expose
which nodes, property keys, or text blocks were involved.

A report named `changed` would overstate what the sync shell knows:

- an applicable property operation can be recorded but lose the LWW comparison;
- pending operations from an earlier call can become applicable during the
  current call;
- duplicate operations are skipped;
- a move into or out of trash changes liveness;
- structural replay calls `reapply_properties`, so a move can affect which
  retained properties are observable;
- raw applied operations and final visible values are not interchangeable.

### Research candidate

The safer research direction is a conservative **impact** or **touched** report,
not a claim that every listed item visibly changed. Possible application-
independent categories include node IDs, `(node, property-key)` pairs, and text
block IDs touched by operations made applicable during the call.

Before this can become an API proposal, its contract must define:

- whether LWW losers are included as touched;
- how results are deduplicated and ordered;
- whether newly applicable pending operations are included;
- whether duplicates are excluded;
- how moves, trash, restoration, and property reapplication expand impact;
- whether returned collections are immutable or defensively owned;
- whether local mutation and remote sync use one report vocabulary.

A conservative report could bound property reads for sparse, property-only
syncs. It does not guarantee that every consumer can avoid a full scan, and the
current browser evidence does not establish a product-performance benefit.

## Second-driver evidence

Loom's `examples/lambda/crdt_egw_test.mbt` is a real but narrower precedent. Its
EGW text 0.3 peer snapshots `old_text`, applies a local insert or remote sync,
reads `new_text`, and reconstructs parser edits with `text_to_delta`.

This confirms analogous consumer pressure: after applying CRDT work, a
downstream incremental system needs a bounded description of authoritative
impact. It does **not** confirm the same container 0.4 property-report contract:

- it uses the text package rather than the container package;
- its state shape is a single text value, while the container driver owns many
  node properties;
- it derives a value diff rather than consuming an EGW impact report;
- it does not exercise `Document::set_property`.

The second-driver gate is therefore informative but unmet for both container
candidates.

## Comparison

| Trajectory | Correctness | Misuse resistance | Convenience | Generality | Status |
|---|---|---|---|---|---|
| Current EGW 0.4 API | Proven sufficient with adapter safeguards | Caller must distinguish recording, liveness, and semantic change | Requires liveness policy, read-back, and full property scan | Application-neutral | Accepted experiment baseline |
| Error-transparent property write | Can expose not-recorded/internal failure | Keeps application liveness and semantic equality separate | May remove failure-detection boilerplate | Container-level and schema-neutral | Concrete candidate pressure; gate unmet |
| Rich mutation receipt | Meaning is ambiguous across operation, LWW, liveness, and projection domains | Encourages callers to overread `Applied` or `AlreadyEqual` | Superficially compact but policy-heavy | Not demonstrated | Shape not advanced |
| Conservative impact report | Safe only with an explicit superset contract | `touched` avoids claiming visible change | Could bound sparse downstream reads | Potentially spans properties, nodes, and text | Research candidate; gate unmet |

## Evidence needed next

No implementation should begin until all applicable evidence exists:

1. A second **container** driver must reproduce the mutation-failure or
   post-apply impact need.
2. The mutation candidate must specify compatibility: additive checked method
   versus a breaking change to `set_property`.
3. The impact candidate must specify and test LWW losers, duplicate and pending
   operations, deterministic ordering, moves, trash/restoration, and immutable
   ownership.
4. Local and remote candidate reports must be compared without identifying
   application command IDs with EGW operation IDs.
5. Existing convergence suites must pass with and without any candidate.
6. Benefits must be quantified as removed caller branches, calls, retained
   state, or end-to-end work—not only microbenchmark speedup.
7. Publishing an issue update, ADR, PR, or EGW code change requires separate
   explicit approval.

Until then, production synchronization remains FullScan and the adapter-local
safeguards remain the correctness baseline.

## Source ledger

| Evidence | Source |
|---|---|
| Liveness checks, mutation read-back, shared projection path | `examples/typed_spreadsheet_incr_tea_demo/egw_adapter/adapter.mbt` |
| Failure, retry, concurrency, sync-ordering, payload, and convergence tests | `examples/typed_spreadsheet_incr_tea_demo/egw_adapter/adapter_wbtest.mbt` |
| Synthetic FullScan/ChangedProperties lower bound | `examples/typed_spreadsheet_incr_tea_demo/egw_adapter/adapter_bench_wbtest.mbt` |
| `set_property`, `SyncReport`, and sync apply semantics | `.mooncakes/dowdiness/event-graph-walker/container/document.mbt` |
| Property operation emission and transaction grouping | `.mooncakes/dowdiness/event-graph-walker/container/undo.mbt` |
| Loom old/new text diff bridge | `../examples/lambda/crdt_egw_test.mbt` |
