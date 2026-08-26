# ADR: Make Incr Next Region close idempotent

**Date:** 2026-08-25
**Status:** Accepted

## Context

The accepted pre-alpha lifetime contract reports duplicate Region close as `ClosedRegion`. Real owners may reach cleanup through unmount, cancellation, and error quarantine paths; exactly-once close then requires a caller-owned flag that duplicates Region lifetime state.

## Decision

`Region::close` is idempotent. The first successful close releases Region-owned Source payloads, Query and Derived Value recipes, memo evidence, and traces, then invalidates retained Views. Closing an already closed Region succeeds without changing clocks or state.

A close attempted during an illegal evaluation or Transaction phase remains a typed `RegionError`. Creating new Region-owned values after close also remains a typed `RegionError`. Reading a retained View after close raises `ReadError::ClosedRegion`.

## Rationale

Close is resource cleanup rather than a domain transition callers need to distinguish. Idempotency allows independent cleanup paths to compose without exposing or duplicating Region state, while phase failures and stale reads remain observable where recovery decisions differ.

## Consequences

- Owners do not maintain a parallel closed flag solely to suppress duplicate cleanup.
- Tests distinguish harmless duplicate close from illegal-phase close and post-close definition or read.
- The K0 lifetime contract and executable lifetime documentation must be revised and reaccepted before alpha publication.
