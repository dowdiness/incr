# ADR: Adopt Incr Query as a pre-1.0 sibling product

**Date:** 2026-08-17
**Status:** Accepted
**K2 disposition:** Option A accepted 2026-08-24 — separately commission alpha publication after standardizing the candidate packager on MoonBit 0.10.9 or newer; this record does not authorize publication
**Implementation plan:** [Plan 015 at its final merged tree](https://github.com/dowdiness/incr/blob/58469934c5644686992688bc7a9f1685326a081d/plans/015-incr-next-kernel-alpha.md) (deleted on completion under the root plan workflow)

## Context

K1.1–K1.6 are accepted and merged. K1 established the semantic kernel,
independent oracle, ownership closure, and product-quality conformance without
changing current `dowdiness/incr`. K1.6 completed at implementation
`b7d2c32ebdc65472db2ed0fd36f36a678c86822f`, status record
`6f51d63e4e406554e74cbbbb3e6c3f481d559547`, final PR/CI head
`15892973a556dc8a1c960bd3544f8e3c3922596a`, and PR #482 squash merge
`58469934c5644686992688bc7a9f1685326a081d`.

All 46 hosted statuses passed, including `Incr Query Required`. CodeRabbit
skipped content review and is not positive evidence; independent MoonBit and
adversarial reviews returned **APPROVE**. Squash-tree equality passed. Current
`incr`, production Incr Query kernel sources and manifests, and generated
interfaces had zero delta in K1.6.

## Decision

- Adopt `dowdiness/incr_query` as an unpublished pre-1.0 sibling product.
- Keep current `dowdiness/incr` as the current product. Incr Query is not a
  compatible replacement.
- Adopt the K0 Product and Kernel Contract, K0 Lifetime and Transaction
  Contract, and K1 kernel semantics as the Incr Query baseline.
- Recommend a separate alpha publication commission after the candidate
  packager is standardized on MoonBit 0.10.9 or newer. Automation must use an
  exact verified toolchain pin rather than a floating version range.
- Retain the historical MoonBit 0.10.4 compatibility evidence; active CI uses
  the available MoonBit 0.10.8 compatibility consumer while that support
  remains useful. Do not use it as the candidate packager for the selected
  17-file policy.
- Do not authorize publication, registry mutation, version release, or Canopy
  production integration in this decision. Each remains separately gated.
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
coherent. K2 then supplied the missing product evidence:

- K2.1 proved that an independent public-only consumer can express dynamic
  dependencies, atomic transactions, Region closure, and surviving View errors.
- K2.2 supplied checked public-only documentation and isolated caller-contract
  counterexamples on default, native, JavaScript, and wasm-gc.
- K2.3 produced a reproducible 17-file unpublished candidate and consumed it
  outside the source checkout with current and CI-pinned toolchains, with no
  source fallback or registry mutation.

K2 found no public-interface or semantic defect requiring evidence reacquisition.
It did expose one distribution constraint: MoonBit 0.10.4 remains a passing
consumer but cannot enforce the selected `.moonignore` package policy. MoonBit
0.10.9 packages the accepted candidate correctly.

## Consequences

- K1 semantics are the baseline for future Incr Query kernel changes.
- Pre-1.0 breaking changes remain possible, but a semantic change requires an
  explicit K0 contract change record.
- [Plan 016 at its final disposition](https://github.com/dowdiness/incr/blob/e30cf501db5a88d7a3764e8703c1f01b2077e046/plans/016-incr-next-usability-and-distribution.md)
  completed K2.1–K2.4 without changing K0 semantics or current `incr`. The plan
  file is deleted under the root workflow; the immutable blob is its record.
- The accepted consumer fixture, executable guide, caller-contract warnings,
  package policy, and distribution checker remain active product safeguards.
  Time-bound raw K2.3 command output is removed after the accepted hashes are
  preserved in the [K2.3 validation record](../../incr_query/kernel/evidence/k2-3-validation.md)
  and the toolchain constraint is preserved here and in the package policy.
- Active repository automation uses exact MoonBit 0.10.14+7d59c7ec9 through
  the checksum-verified repository-local installer, satisfying the K2 packager
  prerequisite. Historical K1/K2 evidence pins remain unchanged; K2.3 retains
  its original MoonBit 0.10.4 compatibility result as historical evidence,
  while active CI uses the available 0.10.8 consumer.
- Alpha publication requires a new explicit commission. Publication, registry
  mutation, version release, and Canopy production integration remain
  unauthorized and require a separate explicit commission.
- Mount, Program/Port/Formula, public debug/explain, public or automatic
  eviction/LRU, and parallel evaluation remain separately gated.

## Maintenance update

The MoonBit 0.10.4 binary and core archives used by the original K2
compatibility job now return HTTP 403 from the official artifact host. The
historical result remains valid evidence; active CI uses the available,
checksum-verified 0.10.8 toolchain instead.
