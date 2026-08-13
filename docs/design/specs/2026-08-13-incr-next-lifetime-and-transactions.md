# Incr Next K0 lifetime and transaction contract

**Reader:** Maintainers and K1 implementers responsible for publication
atomicity, capability expiry, Region closure, and ownership release.

**Decision:** Put the Region lifetime skeleton and transaction-only publication
in K1.1. Preserve the #461–#465 phase, clock, close, failure, and ownership
semantics while keeping retention policy private.

**Keep until:** K1 is accepted, rejected, or superseded. If accepted, replace
this time-bounded spec with current architecture/user documentation and an ADR
for durable product decisions.

**Disposition:** Keep through K1. K0 documentation is commissioned. K1
implementation still requires explicit commissioning.

---

## Relationship to the kernel contract

[Incr Next K0 Product and Kernel Contract](2026-08-13-incr-next-kernel-contract.md)
owns product scope, public capability names, verification, cycles, and cutoff.
This document owns transaction state transitions, Region closure, cross-Region
dependencies, and payload release.

## Facts from evidence

The following branch-only results are evidence, not merged production behavior:

| Issue | Commit | Relevant evidence |
|---|---|---|
| #460 | `39569001f37bece2790f308c024187f4b43feba9` | View recipe survives independently of memo incarnation |
| #461 | `4e2e2650851ab0677a88b9904b6bb0c79650a442` | Atomic staging, sticky poison, capability expiry, Region close |
| #462 | `d54e78087d3837eccee0c55247adb90c07625869` | Cross-Region tombstones, clocks, close-time release |
| #463 | `b0244adaea59e0684bac53026220c9bd0d247bea` | Active-key and temporary-trace cleanup |
| #464 | `c640f65124b2a0eb362f3f08a1b6220e6647b6b7` | Equivalent recompute replaces value/trace ownership |
| #465 | `5e79f111d92ee49645687f2a548b6e12f2063b14` | Explicit memo proof loss and rematerialization |

K1 consolidates these contracts without importing evidence providers.

## Selected transaction contract

### One publication path

`Source[T]` exposes no direct setter. A Store-owned transaction is the only
publication path. Exact MoonBit callback and error-wrapper syntax is fixed by
compile probes, but it must preserve this control flow:

```text
Idle
  -> Transacting
  -> callback stages zero or more typed writes
  -> validate callback result and sticky poison
  -> atomically commit all final staged writes, or release all staging
  -> expire Transaction
  -> Idle
```

The callback cannot perform root reads, open another transaction, or mutate a
Region. The module-global alpha gate rejects the same operations through a
different Store as well.

### Typed heterogeneous staging

Staging may use transaction-local erased closures keyed by private Source
identity, as demonstrated by #461. The closure captures the typed Source core
and next value; no persistent global erased Source registry is introduced.

For each Source, only the final staged write is retained. Replacing an earlier
write releases its payload. Staging never changes the committed Source.

### Sticky poison

Every `set` validates Store provenance, Region generation, Transaction
liveness, and execution phase before staging. A failed set poisons the
transaction even if the callback ignores its returned error. Once poisoned, a
transaction cannot commit.

A callback-returned failure, sticky poison, or catchable raised failure causes
rollback. Rollback clears staged closures and payloads, expires the capability,
restores `Idle`, and changes no committed Source or clock.

Uncatchable abort and arbitrary FFI failure remain outside K1 guarantees.

### Commit

A successful empty callback is a semantic no-op and advances neither clock.
A successful nonempty callback:

1. applies exactly one final prevalidated write per Source;
2. makes all writes visible atomically while root reads remain phase-blocked;
3. advances public `Revision` exactly once;
4. advances private `ChangeEpoch` exactly once;
5. expires the Transaction and restores `Idle`.

Publication is unconditional. An equal-value write still makes the transaction
nonempty and advances both clocks; `Source[T]` has no `Eq` bound. No observer can
see application order because evaluation is forbidden until commit completes.

### Capability expiry and zero-delta rejection

A captured Transaction used after callback exit returns an expired-capability
error. Rejected or duplicate operations do not invoke caller-defined `Hash` or
`Eq`, mutate staging, advance clocks, or disturb the global phase.

## Selected Region contract

### Identity and construction

Every Source and Query belongs to one Region and one Store. A View records
sufficient owner/generation metadata for provenance and closed-lifetime checks.
Same-Store cross-Region reads are legal and tracked. Cross-Store reads are
structural errors.

Region identity and close capability exist from K1.1; they are not attached
after memoization. This keeps View and QueryCore ownership direction stable
through all later K1 stages.

### Close state transition

The minimum Region state is:

```text
Open -> Closing -> Closed
```

A close request is valid only in module-global `Idle`. Rejected close is
zero-delta. The first successful close:

1. prevents new Source/Query definitions and publication;
2. clears Region-owned Source payloads;
3. clears Query compute closures and cutoff captures;
4. clears typed memo tables, values, and Region-owned forward traces;
5. clears active/temporary state that must already be empty in `Idle`;
6. seals the generation as closed;
7. advances `ChangeEpoch` exactly once, without advancing `Revision`.

Duplicate close reports already closed and advances neither clock. Exact public
return shape, such as `Result[CloseOutcome, RegionError]`, is selected by a
compile probe; boolean return is not assumed by this contract.

K1 does not require a public Store-close operation. Application owners may
close their Regions explicitly. Store-wide lifecycle, if later needed, must be
defined in terms of the established Region contract rather than inventing a
second payload-release path.

### Surviving Views

A View does not keep its Region open. After close, a surviving Source or Query
View retains only the lightweight tombstone metadata and, for a Query View, its
captured key needed to reject or identify the invocation. It does not retain
the closed Region's Source payload, compute closure, memo value, or owned trace.
A later root or nested read returns `ClosedRegion`.

View lifetime is independent of memo incarnation: eviction and rematerialization
do not change the View recipe.

## Cross-Region dependencies

Suppose Query `A` in open Region A last read a Query or Source owned by Region B.
Closing B clears B's heavy payload, but A's last-successful trace may still
retain a lightweight typed dependency recipe for B until A verifies,
successfully replaces its trace, is privately evicted, or Region A closes.
Close therefore guarantees release of B-owned heavy payload, not immediate
release of all keys retained by downstream Regions.

On A's later read:

```text
old dependency verifies ClosedRegion
  -> old value lacks reuse proof
  -> recompute A from its current branch

current recompute no longer reads B
  -> success; install new value and trace

current recompute reads B again
  -> return ClosedRegion; preserve A's prior successful memo and trace
```

An old-trace `ClosedRegion` is recomputation evidence, not automatically the
root error. Only a structural error reached by current recomputation is returned
to the caller. This distinction permits ordinary branch-away recovery without
stale fallback.

## Failure and release invariants

Every catchable Query exit (success, Cycle, CrossStore, ClosedRegion, expired
context, or another `ReadError`) removes its temporary active key/frame and
releases its temporary trace. Failed current recompute does not replace the
target's last-successful memo or return it as a fallback.

Native reference-count/finalizer evidence must distinguish cutting a
kernel-owned edge from finalizing an object still held by an external alias.
K1 tests cover at least:

- Region close releasing Source payload and compute capture while Views survive;
- rollback and sticky-poison release of staged payloads;
- last-write-wins release of superseded staging;
- successful commit release of replaced Source payload;
- successful recompute release of replaced memo value and old trace;
- failure release of temporary trace while preserving old successful memo;
- Cycle active-key cleanup;
- cutoff-equivalent replacement releasing the old value while retaining the
  newest value and trace;
- private eviction releasing one typed memo entry;
- surviving downstream tombstone/key release after trace replacement or
  downstream close.

## Deterministic core and imperative shell

The functional core decides transaction validation, poison transitions,
last-write-wins staging plans, clock deltas, verification response to closed
dependencies, and close commands from explicit state. Decisions are testable
without performing release actions.

The imperative shell owns phase entry/exit, callback invocation, closure/payload
storage, atomic application, capability expiry, and execution of close commands.
It must not expose mutable internal collections from validated decisions.

## Deferred choices

K1 does not include nested or cross-Store transactions, undo history,
transaction observers, implicit Region garbage collection, Region recycling,
automatic retention policy, public eviction, Store-wide close, parallel close,
or async teardown.
