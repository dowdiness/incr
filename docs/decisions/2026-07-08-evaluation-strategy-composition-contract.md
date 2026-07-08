# ADR: Evaluation-Strategy Composition Contract

**Date:** 2026-07-08
**Status:** Accepted (contract documentation); fold/pairwise primitive **reserved, not commissioned**
**Issues:** [#368](https://github.com/dowdiness/incr/issues/368) (runtime guard),
[#369](https://github.com/dowdiness/incr/issues/369) (Reader/Writer proposal)
**Anchors:** [Modal runtime split not warranted](2026-04-26-modal-runtime-split-not-warranted.md),
[Memo Event Observation](2026-05-17-memo-event-observation.md),
[Accumulator API](2026-04-20-accumulator-api.md)

## Context

incr runs three evaluation strategies inside one `Runtime`: pull (lazy,
memoized, backdated verification — Salsa-shaped), push (eager propagation —
fine-grained-reactivity-shaped), and Datalog (fixpoint over relations). Each
engine individually converges on a production-proven design. The composition
of the three is incr's actual differentiator — and until this ADR it was
defined only operationally, by the kernel implementation.

The cost of that gap is documented: a consumer called `Input::set` inside a
reactive compute (an eager fold reading a memo, the memo writing back to an
input), causing reentrant propagation that aborted with a misleading
"disposed input" error. Root-causing it took four implementation attempts
(#368, moondsp dowdiness/moondsp#184). The pull/push legality table in #369
had to be reverse-engineered from that debugging session. Every question the
follow-up analysis raised — is Reader/Writer sound? would trait objects
prevent it? should the strategies be separate libraries? — turned out to be
a question about a contract that was never written down. This ADR writes it
down.

## Decision

### 1. Cell taxonomy: the purity axis

Every cell kind is classified on one axis, and the classification determines
which machinery may legally apply to it:

| | Pure-of-current-values | History-dependent |
|---|---|---|
| Semantics | Value is a function of current dependency values only. Caching is **transparent**: backdating, verification skipping, GC eviction + recompute, and demand schedule must all be unobservable | Value depends on the sequence of committed changes. Recompute events are semantics |
| Evaluation | Lazy pull is safe | Eager push **required** — a missed event changes the answer |
| Backdating | Legal | Illegal |
| Lifecycle | Ordinary derived cells | Must be GC-anchored (like `Watch`/`Observer`) |
| Cell kinds | `Derived`, `ReachableDerived`, `DerivedMap`, `EagerDerived` computes | No sanctioned first-class home today (see §5) |

Consequence: **compute closures must be pure functions of their tracked
reads.** A compute that observes anything else — its own previous result,
how many times it ran, whether a recompute was skipped — is outside the
contract, because in a lazy pull system with verification skipping, *when*
computation happens is a caching and demand decision. Passing the previous
value into every compute by default (Solid-style `createMemo(prev => …)`)
is therefore rejected for incr: it would make the caching layer observable
from every cell and silently void the transparency column above.

Sanctioned escape hatches for history-dependent needs, today:

- **`mut` capture** in the closure environment — works, but its semantics
  under skipped recomputes (the `mut` does not advance on turns where the
  compute did not run) must be understood; this is the idiom #368's error
  message points to.
- **Accumulators** — the side-channel collector
  ([Accumulator API ADR](2026-04-20-accumulator-api.md)) for pushing
  side-band values out of computes.
- A first-class `fold`/`pairwise` primitive is **reserved** (§5), not built.

### 2. Context × operation legality

The pull/push boundary, promoted from #369's reverse-engineered table to
contract:

| Context | `Input::set` / `force_set` (push ops) | `Input::get` / `Derived::get` (pull ops) |
|---|---|---|
| Pull compute (`Derived`, memo verification) | **Illegal** — reentrant propagation | Legal (records dependency) |
| Push compute (`EagerDerived`, `Effect`) | **Illegal** — reentrant propagation | Legal (records dependency) |
| Outside the graph (`Observer::get`, main thread, `on_change` callbacks) | Legal | Legal (untracked) |
| Inside `batch` (outside compute) | Legal — deferred, committed at batch end | Legal |

Mechanism: `Input::force_set` calls `propagate_changes` unconditionally on
the non-batch path (`incr/cells/input.mbt`). Invoking it while a propagation
is in flight re-enters the propagation machinery. `on_change` callbacks run
after propagation returns, so writes there are legal.

**Enforcement is the runtime guard proposed in #368** (abort when the
tracking stack is non-empty), and that guard is *normative*: it is the
definition of the boundary, not a debugging aid.

### 3. Why enforcement is runtime, not types

Analyzed and settled; recorded so it is not re-litigated:

- **Handle splitting** (Reader/Writer, #369) and **trait objects** (a
  read-only `&Readable`-style view) are the same mechanism: they scope the
  write capability to a *handle*. MoonBit closures capture arbitrary
  environment, so a captured writer (or the original `Input`) compiles and
  reproduces the bug inside any compute. Neither is compile-time prevention
  of the bug class; both are least-capability ergonomics. Trait objects are
  strictly worse here because MoonBit traits have no type parameters, so a
  read trait cannot be generic over the value type.
- **Context/token passing** (computes receive a read context; `set` demands
  a write token never handed to computes — Salsa's shape) scopes the
  capability to the *context* and is genuinely stronger: accidental writes
  become compile errors. But without lifetimes, tokens escape through
  mutable state, so soundness still degenerates to a runtime liveness check
  — i.e. back to #368's guard. Adopting it would also mean redesigning every
  compute signature (the zero-argument closure + implicit tracking core).
  Rejected for the current API; noted as the preferred shape if a reactive
  API is ever designed from scratch.
- Salsa gets context-scoped exclusion for free from `&mut` borrow checking.
  incr cannot; the guard is the sound substitute. Claims of "compile-time
  prevention" for handle-splitting designs must not be made in docs or
  issues.

Consequently #369 is rescoped: an *additive* read-only view
(`Input::reader()` returning a `Reader[T]`, analogous to
`watch::Sender::subscribe` / Vue `readonly()`) is welcome as ergonomics on
top of the guard; the tuple-returning constructor (breaking every consumer
post-facade-migration) is not justified by soundness, because it provides
none.

### 4. Single revision clock and the layering intent

The reason the three engines share one `Runtime` rather than being three
libraries: **cross-strategy dependency edges under one revision clock.**
Consumers depend on those edges (UI `Watch` over parser memos in `incr_tea`;
eager folds reading memos in moondsp). One clock makes batch commits atomic
across strategies — a push observer can never see a half-updated pull layer.
Separate libraries would not remove the pull→push seam; they would move it
into user-space bridge code (an observer feeding an input), which is exactly
the guard-unreachable `set`-inside-compute pattern that motivated #368, and
would triplicate the propagation substrate (revisions, dirty marking,
subscribers, batch, GC) that the engines share.

The layering that already exists is the intended design, stated here so it
is auditable: **kernel = shared propagation substrate; engines = isolated
evaluation strategies.** Engines live in `incr/cells/internal/{pull,push,datalog}`
with no cross-engine imports, `shared` as the leaf, and kernel one-way —
mechanically enforced by `scripts/check-engine-isolation.sh`. This is the
"separate implementations" design realized inside one module; what remains
unified is the coordinator and the clock, which is precisely what the
cross-strategy edges require. (See also
[Modal runtime split not warranted](2026-04-26-modal-runtime-split-not-warranted.md).)

### 5. Reserved: `fold` / `pairwise` delivery contract

The reentrancy bug was a *demand* signal: consumers need "state that
survives across recomputes" (previous-value diffing, fold state) and had no
sanctioned primitive, so one was improvised via an illegal write. If/when a
first-class primitive is commissioned, its contract is fixed now:

- `fold(source, init, (acc, v) -> acc)` is an **eager push-side** cell;
  `pairwise` (previous + current of a source) is its special case. A
  prev-aware derived (`with_prev`) is also a fold (acc = own output) and
  needs no separate mechanism.
- Delivery: **every committed change of the source triggers exactly one fold
  step.** Batch coalescing (one batch = one committed change) is part of the
  contract, not a violation. Any push-side path that could skip delivery to
  an eager cell must be pinned by a known-positive test before the primitive
  ships.
- Fold cells are history-dependent (§1): never backdated, never lazily
  verified, GC-anchored.
- Commissioning gate (matching this repo's driver-gated convention): a
  second concrete consumer need beyond the moondsp pattern, OR the `mut`
  idiom proving insufficient in practice.

## Falsifiable predictions

This contract stands or falls on two observable claims:

1. **Fold lands as a leaf.** When commissioned, `fold` must be implementable
   entirely on the push side without modifying pull verification
   (`internal/kernel/verify.mbt` semantics, backdating). If implementing it
   forces changes inside pull verification, the composition seam is
   load-bearing in a bad way — reopen the layering question of §4.
2. **The seam bug class stops growing.** After #368's guard + this ADR, new
   bugs of the class "engine A's operation invoked from engine B's context
   corrupts propagation" should not appear. A second such class (not
   instance) is evidence the interaction matrix is still being discovered
   case-by-case — reopen this ADR.

## Consequences

- #368 proceeds as specified; its abort message should point at the `mut`
  idiom and (once written) the cookbook recipe for history-dependent state.
- #369 is rescoped to an additive `reader()` view, positioned as ergonomics;
  its "compile-time guarantee" and Salsa-equivalence claims are corrected by
  §3.
- A cookbook recipe documenting the `mut`-capture idiom and its
  skipped-recompute semantics becomes the sanctioned answer for
  history-dependent state until/unless §5 is commissioned.
- Architecture docs may cite this ADR as the definition of the pull/push
  boundary instead of restating it.
