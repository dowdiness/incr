# ADR: Keep Incr Query Revision access contextual

**Date:** 2026-08-25
**Status:** Superseded by [Keep Incr Query clocks private](2026-08-25-incr-query-private-clocks.md)

## Context

Revision identifies a Store's committed snapshot and advances once per successful nonempty Transaction. The pre-alpha interface also exposes `Store::revision()`, an untracked clock observation that callers may incorrectly pair with a separate root read as though the two formed one coherent snapshot.

## Decision

Remove the public `Store::revision()` getter. A successful Transaction returns its committed Revision. A computation that needs value and Revision coherence reads Revision through `QueryContext::revision()`, which records the Store-wide Revision dependency in the same root snapshot.

The Store retains its internal Revision clock. Root evaluation may capture it privately when constructing a QueryContext.

## Rationale

Revision is snapshot identity, not a debug counter or ambient timestamp. Transaction return and tracked QueryContext access cover the two coherent uses: identifying a publication that just committed, and deriving a value tied to the root snapshot being evaluated. A standalone getter adds an observation that cannot promise coherence with a later read and encourages time-of-check/time-of-use assumptions.

## Supersession

Immediate interface review found no public-consumer use of Revision and rejected both untracked and tracked ambient clock access as lower-level than the commissioned domain interface. The superseding decision keeps Revision entirely private.

## Historical consequences

> The consequences below describe the superseded proposal and are not part of
> the current public interface. The accepted
> [private-clocks decision](2026-08-25-incr-query-private-clocks.md) keeps
> Revision entirely private.

- External cache or synchronization code would have received a Revision from commit or from a Derived Value that explicitly included tracked Revision.
- Callers would not have polled the Store clock independently of a snapshot operation.
- `QueryContext::revision()` would have remained a broad Store-wide dependency usable only when publication identity affected the value.
- Existing public docs and tests that inspected initial Revision through `Store::revision()` would have migrated to a tracked snapshot or transaction result.
