# K1.3 validation record

**Reader:** K1.3 maintainers and reviewers.

**Decision:** Add invocation-level active tracking and structured cycle detection
to the accepted K1.2 kernel while preserving Fresh independence, ownership
boundaries, typed memo atomicity, and the small public interface. The testkit
model adds cycle graph recipes and normalized witnesses; Fresh adds its own
independent active invocation tracking; kernel and Fresh share no active-tracking
implementation.

**Keep until:** K1 alpha is superseded or a durable ADR is separately
authorized.

**Disposition:** **ACCEPTED AND MERGED.** The candidate is based on commission
merge `621180cf460661aa95eb89da58553681688fa502`; the accepted implementation
head is `e187b562f87ec4ecd50940a5e8fc2bc5d478380c`, the status-only head is
`a8115757662a6412e053aad9b7dc451f39a825c6`, and PR #476 merged the equivalent
squash tree as `5657cfc99734c9ac9e7093dd71819d6a0c48df87`. Both implementation and
status-only heads passed 46 of 46 hosted checks, including
`Incr Next Required`; public diff review was APPROVE and maintainer acceptance
was PASS. CodeRabbit skipped content review because manual review was required
and is not positive evidence.

K1.4 typed cutoff and backdating is commissioned, but its implementation is not
accepted. K1.5–K1.6 remain blocked and uncommissioned. No ADR or package
publication is authorized.

## Generated-interface compile probe

The reproducible
[`probe-incr-next-k1-3-cycle-witness.sh`](../../scripts/probe-incr-next-k1-3-cycle-witness.sh)
script compares three generated-interface spellings for the commissioned cycle
witness against base `621180cf460661aa95eb89da58553681688fa502`:

```text
1. inline Array[Int]           → rejected: mutable exposure
2. public QueryId in witness   → rejected: larger public surface
3. opaque CycleWitness + path  → selected: smallest natural contract
```

The inline choice exposes the path array directly, allowing callers to mutate
the witness. A public `QueryId` adds identity semantics and surface with no
commissioned consumer. The selected opaque witness keeps private fields,
exposes only a defensive-copy `path()` accessor, and adds the single
commissioned `ReadError::Cycle(CycleWitness)` variant.

The selected delta is the only public `incr_next/pkg.generated.mbti` change:

```text
+ pub struct CycleWitness { /* private fields */ } derive(Eq, Debug)
+ pub fn CycleWitness::path(Self) -> Array[Int]
+ ReadError::Cycle(CycleWitness)
```

No active-tracking representation, key type, QueryCore identity, session stack,
or memo/trace payload appears in the generated interface.

## K1.3a — Fresh independent tracker and matrix

Fresh implements its own typed active invocation map and key-free session stack
independent of the kernel. The testkit model adds cycle graph recipes and
normalized witness observations. Fresh and the kernel adapter compare only
logical outcomes and normalized witnesses; they share no active-tracking
implementation.

The independent matrix covers:

- direct self-cycle `A -> A` produces `Cycle[A, A]`
- mutual cycle `A -> B -> A` produces `Cycle[A, B, A]`
- same Query key cycle `q(0) -> q(1) -> q(0)` produces `Cycle[Q, Q, Q]`
- finite recursion `q(3) -> q(2) -> q(1) -> q(0)` succeeds
- unequal-key cross-Query `A(0) -> B(0) -> A(1)` succeeds
- dead cycle branch succeeds with no Cycle
- sequential duplicate read succeeds with no Cycle
- initial Cycle installs no memo
- Cycle introduced over a successful memo preserves old memo unchanged
- repeated Cycle is detected on every read; error is not cached
- Cycle removed recovers successfully
- Cycle reached only through an old trace requests recomputation
- Cycle reached by current recomputation determines the root error
- close or another structural error empties active map and session stack

## K1.3b — Typed active map and key-free stack

Each `QueryCore[K, V]` owns one private `Map[K, Int]` active map. The map key is
the typed caller key; the value is the session-stack position at invocation
entry. The map is constructed empty at Query creation and cleared at Region
close.

Each `EvalSession` owns one private `Array[QueryId]` active stack. The stack is
key-free: it retains only Query identifiers, never caller keys, QueryCore
references, memo payloads, traces, or Region-owned data. The stack is
constructed empty at session creation and emptied on every structured exit.

After metadata validation, invocation checks the active map before the
same-epoch memo lookup. A same-epoch hit returns without registration. Only a
stale or absent memo enters the slow path: it records the stack position in the
active map, pushes the Query identifier, then verifies or computes. Slow-path
exit pops the stack and removes the active entry for success, Cycle, and every
other structural error.

## K1.3c — Old-verification and current-recompute separation

An old-trace verification that encounters an active re-entry treats the Cycle as
`RecomputeRequired` and does not decide the root error. The current branch
proceeds to current recomputation, which may succeed or report its own Cycle.

A Cycle reached by current recomputation becomes the root `ReadError::Cycle`.
The witness is constructed from the session stack between the recorded position
and the re-entered Query identifier, then closed with the re-entered identifier.
The witness is copied and key-free: it retains only integer Query identifiers.

## Atomicity, recovery, cleanup, and RC

An initial Cycle installs no memo. A Cycle over an existing successful target
preserves the target's value, trace, `MemoId`, `verified_at`, and `changed_at`
exactly. The Cycle error is returned without stale fallback. Cycle errors are
never memoized; repeated reads detect them again. Recovery after Cycle removal
keeps the target `MemoId` and atomically replaces value, trace, and current
stamps.

Active map keys and session stack entries are removed after success, Cycle, and
every other structured error. Temporary traces and frames are released after
Cycle. Region close clears active maps, memo tables, traces, and compute
captures.

Native RC evidence distinguishes a View-retained key from an active-map or
witness leak: dropping the View releases the key before Region close while the
Cycle error and witness remain held. White-box evidence separately proves that
active maps and session stacks are empty after each root exit; Region close
also clears the Query-owned active map.

## Existing API First and reuse

The implementation reuses the K1.2 `QueryContext` child/frame/expiry boundary,
Region close actions, Store lifetime and clock checks, typed per-Query memo
ownership, and last-successful forward verification. MoonBit core `Map` supplies
typed active-map lookup and removal; `Array` supplies the key-free session
stack with push/pop/copy; `Ref` owns private counters and capabilities;
`Option` and `Result` retain lifetime and structural-failure channels; `Hash`/`Eq`
define typed memo and active-map key identity.

`Array::copy` provides the defensive witness path copy. No linear-search table,
key erasure, generic defensive copy, or public Query identity type is added.
The kernel adds no public helper or type beyond the commissioned opaque witness
and `ReadError::Cycle` variant.

Remaining kernel mutation is confined to private active maps, session stacks,
memo tables, counters, temporary tracking frames, clock publication, and
Region-close actions. Testkit mutation is local to setup validation, Fresh
active tracking, and transactional replay.

## Acceptance gate evidence

The candidate passes:

- six package roots across default, native, JavaScript, and wasm-gc targets:
  24 of 24 check-and-test cells;
- workspace tests: 1,236 wasm-gc and 256 JavaScript;
- white-box active-map, session-stack, frame, and trace cleanup after success,
  Cycle, and another structural error; native RC/finalizer evidence that a held
  witness retains no key and existing Region-close payload release still passes;
- boundary self-tests and checks, typed negative probes, engine/workspace
  isolation, and documentation boundaries;
- generated-interface review: the opaque `CycleWitness`, defensive-copy
  `path()`, and `ReadError::Cycle` variant are the only public
  `incr_next/pkg.generated.mbti` delta;
- zero current-`incr/` implementation or interface diff;
- zero K1.4+ cutoff/backdating, eviction, Mount, Program, or public
  debug/explain surface;
- independent MoonBit and adversarial reviews with no findings;
- PR #476 public diff review APPROVE and maintainer acceptance PASS;
- current implementation HEAD hosted acceptance: 46 of 46 checks PASS,
  including `Incr Next Required`, with zero pending or failed checks;
- CodeRabbit skipped content review because manual review is required, so it is
  not counted as positive evidence.

Local and hosted validation pass. The status-only head passed all required
checks with `Incr Next Required`, zero pending or failed checks,
CLEAN/MERGEABLE state, zero current-`incr/` diff, zero K1.4+ surface, and a
documentation/status-only finalization diff. The squash-tree equivalence check
passed before PR #476 merged. K1.4 implementation remains blocked until its
commission PR merges and a separate direct instruction is given.
