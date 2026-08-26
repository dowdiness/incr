# Incr Next

Incr Next models committed input state and incrementally derived knowledge with explicit ownership and read capabilities.

## Language

**Derived Value**:
One value computed from tracked dependencies without a caller-supplied lookup key.
_Avoid_: Unkeyed query, unit query, formula

**Query**:
A key-indexed family of derived values. A caller binds a key to select one member of the family.
_Avoid_: Derived value, unkeyed query

**Structural Failure**:
A kernel failure involving evaluation, provenance, lifetime, or capability validity. It propagates through MoonBit's typed `raise` channel.
_Avoid_: Domain error, error value

**Diagnostic**:
Opaque, developer-facing context attached to a Structural Failure. It provides an actionable message and optional help without exposing Store identity, Region generation, Query keys, computed values, or kernel witness structure.
_Avoid_: Structural diagnostic, error payload, public graph trace

**Domain Outcome**:
An expected alternative result represented as a value, including unsuccessful domain decisions in derived values or transactional work. It is observed and handled as data rather than raised by the kernel.
_Avoid_: Structural failure, exception

**Transaction**:
An atomic publication decision that commits and returns caller-owned `Ok` data or rolls back caller-owned `Err` data. Kernel-owned Structural Failures are raised separately.
_Avoid_: Batch, infallible transaction, transaction error

**Cutoff Policy**:
An optional propagation-equivalence policy for a Derived Value or Query. Omitting it conservatively treats every successful recomputation as changed.
_Avoid_: Cache policy, arbitrary equality predicate, required optimization mode

**Region**:
The lifetime owner of Sources, Derived Values, Queries, memo evidence, and traces. Closing it is idempotent and invalidates retained Views without transferring ownership to them.
_Avoid_: Scope, cache, session

**View**:
A read capability for one Source value, Derived Value, or key-selected Query member. `Store::get` performs a root read and `QueryContext::get` records a tracked dependency. A Source explicitly attenuates to a View, while a Derived Value is represented by one directly.
_Avoid_: Handle, observer, subscription, value container
