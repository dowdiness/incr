# Roadmap

The single canonical current core backlog for the `incr` library.

---

## Current core item

**Issue #399: Residual per-update cost scaling after dispose/GC.**

After disposal and garbage collection, some update paths still show cost that scales with retained graph volume rather than staying constant. Goal: characterize whether the residual is a storage-layout artifact or a live-graph traversal cost, and decide whether slot reclamation or a scheduler change is warranted.

- Plan: [`plans/2026-07-15-retention-cost-attribution.md`](plans/2026-07-15-retention-cost-attribution.md)
- Evidence: [`performance/2026-07-15-retention-cost-attribution.md`](performance/2026-07-15-retention-cost-attribution.md)

No slot-reclamation or scheduler change is commissioned without new evidence from this attribution work.

---

## Module-owned queues

- **incr_tea**: [`incr_tea/docs/backlog.md`](../incr_tea/docs/backlog.md) — task list for the `dowdiness/incr_tea` module (retargeted TEA issues + agenda).

---

## What is not here

Completed work, superseded proposals, driver-gated investigations, and speculative tracks are intentionally absent from this document. They remain recoverable through:

- **ADRs**: [`docs/decisions/`](decisions/) — architectural decisions and their rationale
- **Plans**: [`docs/plans/`](plans/) — concrete implementation records
- **Issues**: GitHub issue tracker — open and closed issues
- **Git history**: commit log — all historical work and decisions

This keeps the roadmap focused on current actionable work rather than becoming a historical archive.
