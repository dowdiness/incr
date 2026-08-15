# K1.1 validation record

**Reader:** K1.1 maintainers and reviewers.

**Decision:** Reimplement one independent K1.1 kernel and an independent Fresh testkit; do not import the evidence providers or current `dowdiness/incr`.

**Keep until:** K1 alpha is superseded or a durable ADR is separately
authorized.

**Disposition:** Accepted K1.1 alpha validation record. Local acceptance,
hosted CI, independent reviews, and maintainer acceptance pass. K1.2 is
accepted at implementation head `12ec2404b676ef7864e353aeb3681c0fef6f20e3`
and merged as squash commit `db2ac77ac0362a7c5ff8d20887868cbdbb635aa8`. K1.3
is accepted at implementation head `e187b562f87ec4ecd50940a5e8fc2bc5d478380c`
and merged as squash commit `5657cfc99734c9ac9e7093dd71819d6a0c48df87`.
K1.4 implementation is complete locally at semantic head
`16e6a1fc1a4cb48ac1ba11463096595398115472` and ownership/boundary head
`f84d9589d4b979b711036263255f6a3f2e684525`, with a local gate pass, but is not
accepted. K1.5–K1.6 remain blocked and uncommissioned. Fold durable decisions
into a future ADR only after a separately authorized K1 adoption decision.

## First failures retained

- Slice 1 boundary controls reject both a direct Fresh import and a transitive `fresh -> model -> incr_next` import.
- Slice 2 tests initially lacked an expiring QueryContext and failed the captured-context read case.
- Slice 3 phase tests initially admitted root reads during evaluation; the gate now rejects them and restores Idle.
- Slice 4 tests initially exposed that a callback could ignore an invalid set; sticky poison now rolls back every staged Source.
- Slice 5 tests initially lacked a surviving View close case; close now clears Source payloads and Query compute captures before sealing the generation.

## Existing API First

Checked with `moon ide doc` before implementation: `Map`/`Set` for typed staging and ownership-free local collections; `Option`/`Result` for capability and structural channels; `Array`/`ArrayView` for close actions and test scripts; `String`/`StringView` and `Bytes`/`BytesView` for the snapshot-value boundary; `Buffer`/`StringBuilder` for diagnostics if needed; `Hash`/`Eq` for private Source identity maps; and `Ref` for Store clocks, phase, lifetime, and capability state. `cmp`/`math` were inspected and rejected because K1.1 has no ordering or numeric policy beyond integer clocks. No current-Incr API or runtime is reused: the new kernel owns its StoreCore, private ChangeEpoch, phase gate, and capabilities.

## Acceptance status

K1.1 semantic implementation is **ACCEPTED** at implementation head
`0ad8f5ae60082dfc6410aac781baa61f52c67d79`. Plan 015 remains in progress.
K1.2 is accepted and merged. K1.3 is accepted and merged at implementation
head `e187b562f87ec4ecd50940a5e8fc2bc5d478380c`, status-only head
`a8115757662a6412e053aad9b7dc451f39a825c6`, and squash commit
`5657cfc99734c9ac9e7093dd71819d6a0c48df87`. K1.4 implementation is complete
locally with a local gate pass but is not accepted; K1.5–K1.6 remain blocked
and uncommissioned.

The accepted implementation passes:

- all 24 root/target check-and-test cells;
- 1,179 wasm-gc and 256 JS workspace tests;
- native RC/finalizer ownership evidence;
- direct, transitive, and external Fresh boundary self-tests;
- typed negative capability probes with expected diagnostic matching, plus
  workspace/documentation boundaries;
- generated-interface inspection with private `RegionId` and no public debug,
  eviction, memo, or trace surface;
- zero current-`incr/` diff;
- independent MoonBit and product/test review.

For K1.3, hosted CI, public diff review, and maintainer acceptance pass.
CodeRabbit skipped content review and is not positive evidence. Its status-only
head passed the required checks and the accepted tree merged in PR #476.

## Differential work evidence

Fresh and incremental adapters execute the same ordered scripts. Persistent
K1.1 Query graphs are constructed once and read repeatedly: a two-root chain
performs four Query computes, while a two-root diamond performs ten, including
two evaluations of the shared Query on each root read. A dynamic branch may be
defined after its first root read with matching Fresh/kernel observations.
Domain failure is read as a nested value; a cross-Store nested read remains a
structural error. Sticky transaction poison takes precedence over a concurrent
callback error so a structural validation failure cannot be hidden.

## Expected divergence

The kernel never defensively copies mutable keys, Source payloads, or Query results. Executable tests retain these as caller-contract counterexamples rather than pretending Fresh and incremental values can repair alias mutation.
