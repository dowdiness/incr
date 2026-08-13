# K1.1 validation record

**Reader:** K1.1 maintainers and reviewers.

**Decision:** Reimplement one independent K1.1 kernel and an independent Fresh testkit; do not import the evidence providers or current `dowdiness/incr`.

**Keep until:** K1.1 is accepted or superseded.

**Disposition:** Active alpha validation record; acceptance is pending final review and the complete validation matrix. Fold durable decisions into a future ADR only after K1 acceptance.

## First failures retained

- Slice 1 boundary controls reject both a direct Fresh import and a transitive `fresh -> model -> incr_next` import.
- Slice 2 tests initially lacked an expiring QueryContext and failed the captured-context read case.
- Slice 3 phase tests initially admitted root reads during evaluation; the gate now rejects them and restores Idle.
- Slice 4 tests initially exposed that a callback could ignore an invalid set; sticky poison now rolls back every staged Source.
- Slice 5 tests initially lacked a surviving View close case; close now clears Source payloads and Query compute captures before sealing the generation.

## Existing API First

Checked with `moon ide doc` before implementation: `Map`/`Set` for typed staging and ownership-free local collections; `Option`/`Result` for capability and structural channels; `Array`/`ArrayView` for close actions and test scripts; `String`/`StringView` and `Bytes`/`BytesView` for the snapshot-value boundary; `Buffer`/`StringBuilder` for diagnostics if needed; `Hash`/`Eq` for private Source identity maps; and `Ref` for Store clocks, phase, lifetime, and capability state. `cmp`/`math` were inspected and rejected because K1.1 has no ordering or numeric policy beyond integer clocks. No current-Incr API or runtime is reused: the new kernel owns its StoreCore, private ChangeEpoch, phase gate, and capabilities.

## Acceptance status

K1.1 is not marked DONE. The remaining gate is final independent review after the blocker fixes and the complete 24-cell target matrix, native RC, boundaries, negative probes, and interface-clean checks.

## Differential work evidence

Fresh and incremental adapters execute the same ordered scripts. Persistent
K1.1 Query graphs are constructed once and read repeatedly: a two-root chain
performs four Query computes, while a two-root diamond performs ten, including
two evaluations of the shared Query on each root read. Domain failure is read as
a nested value; a cross-Store nested read remains a structural error.

## Expected divergence

The kernel never defensively copies mutable keys, Source payloads, or Query results. Executable tests retain these as caller-contract counterexamples rather than pretending Fresh and incremental values can repair alias mutation.
