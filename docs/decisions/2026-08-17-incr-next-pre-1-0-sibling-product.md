# ADR: Adopt Incr Next as a pre-1.0 sibling product

**Date:** 2026-08-17
**Status:** Accepted
**Implementation plan:** [Plan 015 at its final merged tree](https://github.com/dowdiness/incr/blob/58469934c5644686992688bc7a9f1685326a081d/plans/015-incr-next-kernel-alpha.md) (deleted on completion under the root plan workflow)

## Context

K1.1–K1.6 are accepted and merged. K1 established the semantic kernel,
independent oracle, ownership closure, and product-quality conformance without
changing current `dowdiness/incr`. K1.6 completed at implementation
`b7d2c32ebdc65472db2ed0fd36f36a678c86822f`, status record
`6f51d63e4e406554e74cbbbb3e6c3f481d559547`, final PR/CI head
`15892973a556dc8a1c960bd3544f8e3c3922596a`, and PR #482 squash merge
`58469934c5644686992688bc7a9f1685326a081d`.

All 46 hosted statuses passed, including `Incr Next Required`. CodeRabbit
skipped content review and is not positive evidence; independent MoonBit and
adversarial reviews returned **APPROVE**. Squash-tree equality passed. Current
`incr`, production Incr Next kernel sources and manifests, and generated
interfaces had zero delta in K1.6.

## Decision

- Adopt `dowdiness/incr_next` as an unpublished pre-1.0 sibling product.
- Keep current `dowdiness/incr` as the current product. Incr Next is not a
  compatible replacement.
- Adopt the K0 Product and Kernel Contract, K0 Lifetime and Transaction
  Contract, and K1 kernel semantics as the Incr Next baseline.
- Do not authorize package publication or Canopy production integration.
- Do not include Mount, Program/Port/Formula, public debug/explain, public or
  automatic eviction/LRU, or parallel evaluation in this adoption decision.

## Rationale

K1 provides an opaque non-callable `View`, tracked reads through
`QueryContext`, transaction-only publication, typed memo ownership with
last-successful traces, cycle detection, typed cutoff and backdating, and
package-private proof loss. Its evidence includes an independent Fresh oracle,
generated and shrinkable differential conformance, default/native/JS/wasm-gc
coverage, native ownership and RC checks, package boundaries, and generated
interface checks.

This evidence resolves whether the kernel semantics and ownership model are
coherent. It does not yet resolve external usability, ordinary module
consumption, documentation sufficiency, or distribution readiness.

## Consequences

- K1 semantics are the baseline for future Incr Next kernel changes.
- Pre-1.0 breaking changes remain possible, but a semantic change requires an
  explicit K0 contract change record.
- [Plan 016](../../plans/016-incr-next-usability-and-distribution.md) is the
  separate K2 commission for external-consumer, executable-documentation, and
  distribution evidence, not additional kernel semantics. Its commission
  accepts no implementation evidence.
- Publication, Canopy production integration, Mount, Program/Port/Formula,
  public debug/explain, public or automatic eviction/LRU, and parallel
  evaluation remain separately gated.
