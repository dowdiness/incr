# Roadmap

The single canonical current core backlog for the `incr` library.

---

## Current core backlog

No core implementation is currently commissioned. The prior #399 attribution
is retired from the active backlog, with slot reclamation/compaction a no-go;
see the [dated performance note](performance/2026-07-15-retention-cost-attribution.md)
and [retention follow-up ADR](decisions/2026-07-14-retention-followup-tracks-gated.md).

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
