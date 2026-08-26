# ADR: Keep Incr Next clocks private

**Date:** 2026-08-25
**Status:** Accepted

## Context

Revision and change epochs are required internally for verification and memo bookkeeping. The pre-alpha interface exposes both untracked `Store::revision()` and tracked `QueryContext::revision()`, but the public consumer fixture does not use either. A Store-local integer resets with Store identity, is not a durable synchronization cursor, and can be incorrectly paired with a separate root read as though the pair formed one coherent snapshot. Tracked Revision also provides an ambient dependency on every publication, which can hide missing domain dependencies.

## Decision

Revision, change epochs, and changed-at stamps remain private kernel mechanisms. Remove the public Revision type, `Store::revision()`, `QueryContext::revision()`, and numeric Revision access.

A Transaction returns its caller-owned success value after commit rather than a kernel clock:

```moonbit
Store::transaction[T, E](
  (Transaction) -> Result[T, E] raise TransactionError,
) -> Result[T, E] raise TransactionError
```

A computation that needs a refresh token, synchronization cursor, or snapshot identity models that concept explicitly as domain data, normally through a Source. A future coherent Snapshot or Commit Receipt requires a concrete consumer and separate evidence.

## Rationale

The public interface should expose committed domain values and atomic domain outcomes, not the clocks used to prove memo freshness. Explicit domain tokens identify ownership and update authority; ambient Revision access does not. Returning the callback's success value also makes Transaction a useful atomic use-case boundary without inventing speculative commit metadata.

## Consequences

- Successful `Ok(value)` commits staged writes and returns the same value; `Err(error)` rolls back and returns the caller-owned Domain Outcome.
- Structural Transaction failure rolls back and raises `TransactionError` without returning callback data.
- Global recomputation must be driven by an explicit domain Source rather than `QueryContext::revision()`.
- Existing Revision guides, tests, testkit support, generated interfaces, and K0 clock wording must be revised before alpha publication.
