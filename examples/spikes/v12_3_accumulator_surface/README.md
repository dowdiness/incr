# V12.3 Accumulator advanced-handle spike

> **PROTOTYPE — evidence only. Do not merge this module into the public interface.**

- **Reader:** maintainers resolving the V12.3 Accumulator mapping in #453 and #459.
- **Decision:** determine how producer-local contribution reads coexist with callable View without restoring the current Derived read handle.
- **Keep until:** V12.3 records the mapping and implementation no longer needs the compiler/runtime evidence.
- **Disposition:** preserve only on the evidence branch; do not merge the spike into `main`.

## Run

From the repository root:

```bash
./examples/spikes/v12_3_accumulator_surface/check.sh
```

The command runs guarded interface scenarios, the existing current-engine ON_ABORT rollback oracle, and six expected compiler failures.

## Verdict

**Pass with constraints.**

Keep Accumulator as a nominal advanced push/lifecycle handle. Bind its producer-specific read authority when that producer is created:

```moonbit
Store::accumulator[A : Eq](Store, label? : String) -> Accumulator[A]

Accumulator::derived[A, T : Eq](
  Accumulator[A],
  Store,
  compute : () -> T raise ReadError,
  label? : String,
) -> (View[T], Contribution[A]) raise ReadError

Accumulator::is_disposed[A](Accumulator[A]) -> Bool
Contribution::view[A](Contribution[A]) -> View[Array[A]]
Contribution::peek[A](Contribution[A]) -> Array[A]
```

The same pair shape is preserved by `Accumulator::derived_with_backdate[T : BackdateEq]` and unbounded `Accumulator::derived_no_backdate[T]`.

`Accumulator[A]` is push authority for one side-channel family. `Contribution[A]` is passive read authority for one producer's latest successful push sequence. It has no push or disposal method. Product code extracts its callable values View once, then uses normal `values()` reads:

```moonbit
let (type_view, contribution) = diags.derived(store, () => infer(...))
let diagnostics = contribution.view()
let summary = store.derived(() => diagnostics().length())
```

A post-hoc `accumulator.values(view)` is not selected. Structural callable View deliberately hides private producer identity, while current accumulation is keyed by the exact producer. Binding Contribution during producer construction preserves that identity without exposing a generic public Node handle.

V12.10 still owns the concrete error hierarchy. The generated spike surface intentionally uses the current adapter's `Failure` effect and does not convert it to a provisional ReadError. It validates capability shape, early cross-Store rejection, and current rollback separately; it does not claim target error propagation.

## Capability and ownership matrix

| Capability | Authority | Target owner/lifecycle |
|---|---|---|
| `Accumulator::push` | append during that producer's tracked compute | nominal Accumulator; Store-owned state |
| `Accumulator::derived*` | create a producer and bind its local contribution | Store creates producer state |
| primary `View[T]` | callable producer value read | caller-owned passive View |
| `Contribution::view` | tracked defensive read of one producer's pushes | caller-owned passive Contribution/View |
| `Contribution::peek` | untracked defensive snapshot | caller-owned passive Contribution |
| `Accumulator::dispose` | remove one side-channel family | explicit individual breaker |
| `Store::close` | dispose all Store-owned accumulator state | aggregate breaker |

The target field layout is not implemented here. V12.4 must still prove that Store registration, typed buffers, producer state, and breaker paths introduce no forbidden passive cycle.

## Current-to-target mapping

| Current capability | Target mapping |
|---|---|
| `Scope::accumulator[A : Eq]` | `Store::accumulator[A : Eq]` |
| `Accumulator::push` | preserve on nominal Accumulator |
| `Derived::accumulated*` | source-bound `Contribution::view` |
| `Derived::accumulated_peek` | `Contribution::peek` |
| per-producer `push_revised_at` | Contribution View's synthetic invalidation state |
| current Derived value read | primary callable View |
| Accumulator/Scope disposal | Accumulator dispose and Store close |
| `AccumulatorId`, label, debug | rooted diagnostics mapping under V12.11 |

Current local-only semantics remain load-bearing: one accumulator may serve many producers, but each Contribution returns only its own producer's pushes in push order. Changed push sequences invalidate tracked consumers even when the producer's ordinary output backdates; unchanged sequences do not.

## Named consumer

`dowdiness/loom/examples/lambda/typecheck/typecheck.mbt` creates one `Accumulator[TypeDiagnostic]` for a chain scope, passes it through inference, and reads each type producer independently in source order. The consumer depends on:

- explicit deep `push` authority;
- producer-local rather than transitive diagnostics;
- synthetic invalidation independent of `TypeResult` equality;
- untracked `peek` in white-box tests;
- chain-lifecycle cleanup.

The selected pair maps each type producer to a primary type View plus a diagnostic Contribution while keeping the accumulator explicit in `DiagCtx`.

## Positive state

```text
scenario=independent left=[10] right=[20]
scenario=changed_set producer=7 values=[2] consumer_runs=2
scenario=same_set values=[42] consumer_runs=1
scenario=peek original=[3] mutated_copy=[3, 99] consumer_runs=1
scenario=tiers common=[1] backdated=[2] no_backdate=[3]
scenario=lifecycle accumulator_disposed=true peek=[] close_calls=2
scenario=cross_store rejected=true compute_runs=0
positive_probes=PASS
rollback_oracle=PASS
```

The executable guards verify:

- one accumulator keeps two producers' contributions independent and ordered;
- a changed contribution sequence invalidates a dependent View while the producer value remains equal;
- an unchanged sequence backdates the dependent consumer;
- peek is untracked and returns a defensive copy;
- common Eq, custom BackdateEq, and no-backdate producer tiers retain the same Contribution shape;
- current permissive peek returns `[]` after Accumulator disposal;
- Accumulator disposal and Store close are idempotent adapter breakers;
- cross-Store producer binding fails before its compute runs.

Actual raised-compute restoration is pinned by the existing white-box test `accumulator: ON_ABORT restores prior buffer on raised compute`, which the one-command check runs in release mode. The compile adapter does not fake rollback by catching the producer body.

## Negative compiler evidence

| Probe | Diagnostic | Meaning |
|---|---|---|
| `contribution()` | `[4014]` wanted function type | caller must explicitly extract the callable values View |
| `contribution.push(...)` | `[4015]` no method | read authority cannot emit |
| `accumulator()` | `[4014]` wanted function type | push authority is not read authority |
| `accumulator.read()` | `[4015]` no method | Accumulator cannot read a producer without Contribution |
| external Contribution literal | `[4036]` read-only type | consumers cannot forge producer identity |
| mutate Accumulator private state | `[4091]` no field | consumers cannot redirect its Store/slot state |

## Alternatives not selected

| Alternative | Reason not selected |
|---|---|
| `(View[T], View[Array[A]])` only | compact, but cannot preserve current untracked defensive `peek` without another source-bound capability |
| `Accumulator::values(View[T])` | callable View exposes no producer identity to recover after construction |
| public generic `Producer`/`Node` handle | broadens every advanced API and restores a general identity handle where only Accumulator needs one |
| attach metadata methods to View | structural function values have no custom metadata methods |
| keep public Derived solely for accumulation | makes an advanced side channel dictate common read ergonomics |
| transitive contribution View | contradicts the lambda consumer's per-definition local-only requirement |

## Constraints

- V12.4 owns the production strong-edge table and RC proof. The current Runtime/Scope/Derived backing is not target ownership evidence.
- V12.10 owns `ReadError`, Accumulator misuse, typed cross-Store detection, and post-dispose/close error syntax. The adapter checks RuntimeId before producer creation and raises current `Failure`; the target must retain detection before contribution or revision mutation.
- V12.11 owns public IDs, labels, debug state, and rooted diagnostics. Contribution does not itself require public identity.
- Existing accumulator tests remain the semantic oracle for transaction phases, abort restoration, static-compute rejection, synthetic cycles, and revision bookkeeping.
- Nested Scope replacement must retain the lambda chain's ability to dispose one accumulator family without closing the parent Store.
- Release benchmarks must compare synthetic invalidation and defensive-read cost on native RC and wasm-gc.

## Reuse check

- Reused project APIs: `Scope::accumulator`, `Accumulator::push`, `Derived::accumulated_or_abort`, `Derived::accumulated_peek`, all three Derived creation tiers, and Scope disposal.
- MoonBit core APIs checked: ordered `Array` plus `Array::equal`/`copy`; `Map`/`HashMap` for producer-indexed state; `Set` for touched-slot tracking; `Option` and `Result` for lifecycle/error state; `Iter` for traversal. The adapter reuses current storage and adds no collection helper.
- Existing alternatives checked but not used: a bare collection View cannot expose peek; a generic Node would be broader than the named advanced capability.
- New `Contribution[A]` responsibility: bind one private producer identity to tracked and untracked defensive contribution reads.
- Remaining imperative code: counters observe invalidation and snapshot mutation tests defensive copying. Production transaction mutation remains in the current engine oracle.

No ADR needed: this is gated research evidence, not production API adoption or replacement-kernel authorization.
