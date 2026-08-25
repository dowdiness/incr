# Incr Next roadmap

`dowdiness/incr_next` is an adopted, unpublished pre-1.0 sibling product;
current `dowdiness/incr` remains current and is not replaced. The [accepted
sibling-product ADR](../../docs/decisions/2026-08-17-incr-next-pre-1-0-sibling-product.md),
[K0 Product and Kernel Contract](../../docs/design/specs/2026-08-13-incr-next-kernel-contract.md),
and [K0 Lifetime and Transaction Contract](../../docs/design/specs/2026-08-13-incr-next-lifetime-and-transactions.md)
are normative. Plan 015 is complete; its durable implementation record is the
[GitHub blob at commit 5846993](https://github.com/dowdiness/incr/blob/58469934c5644686992688bc7a9f1685326a081d/plans/015-incr-next-kernel-alpha.md).

K1 is complete: K1.1–K1.6 are accepted and merged. Detailed per-slice evidence
is delegated to the [validation index](README.md).

K2 is complete: public-consumer evidence merged as `93eb59b6`, executable
documentation as `9360816f`, and distribution evidence as `3007f5ff`. The
accepted disposition recommends a separate alpha publication commission. Active
repository automation now uses exact MoonBit 0.10.9+6e6c44045, satisfying the K2
packager prerequisite. The [updated sibling-product ADR](../../docs/decisions/2026-08-17-incr-next-pre-1-0-sibling-product.md)
is the durable decision record.

Actual publication, registry mutation, version release, Canopy production
integration, Mount, Program/Port/Formula, public debug/explain, public or
automatic eviction/LRU, and parallel evaluation remain gated and excluded.
