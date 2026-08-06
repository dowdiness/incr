# V12.3 eager owner and interface spike

> **PROTOTYPE — evidence only. Do not merge this module into the public interface.**

- **Reader:** maintainers resolving the V12.3 eager owner/interface mapping in #453 and #458.
- **Decision:** determine whether current EagerDerived maps to active scheduling over an existing passive View rather than another public value handle.
- **Keep until:** V12.3 records the eager mapping and any implementation no longer needs the compiler/runtime evidence.
- **Disposition:** preserve only on the evidence branch; do not merge the spike into `main`.

## Run

From the repository root:

```bash
./examples/spikes/v12_3_eager_surface/check.sh
```

The command runs native lifecycle probes, then activates each disabled negative probe and verifies the expected compiler diagnostic.

## Verdict

**Pass with constraints for the owner/interface split.**

Select this target seam, with the concrete error channel still owned by V12.10:

```moonbit
Store::eager[T](Store, View[T], label? : String) -> Stop raise ReadError
```

Eagerness is an active scheduling policy applied to a passive View. The caller owns the View. Store owns an active mount record that materializes the View immediately and re-evaluates it after committed upstream changes. `Stop` is the idempotent breaker for one mount; `store.close()` breaks all mounts.

`Store::eager` has no `T : Eq` bound. Equality, custom BackdateEq, and no-backdate policy belong to View creation. The unbounded generated signature is type-compatible with all three tiers selected by the separate #457 evidence; this spike directly exercises Eq-free mounting with a non-Eq input View.

Stopping removes proactive scheduling while leaving the View as a passive, lazily readable value. This intentionally decomposes the current handle: active teardown maps to Stop, while read-after-dispose invalidation is rejected for the target because passive values require no disposal. No external `EagerDerived` consumer was found outside `dowdiness/incr`; the in-repository typed-spreadsheet probe does not depend on read-after-dispose behavior. No public `EagerView[T]` or replacement `EagerDerived[T]` handle is selected.

## Current capability mapping

| Current EagerDerived capability | Target mapping |
|---|---|
| constructor and immediate compute | create a View, then `store.eager(view)` |
| push recomputation after input/batch commit | Store-owned eager mount |
| cached `get` / `read` | callable View |
| active part of `dispose` | `Stop::stop` |
| disposed status | `Stop::is_stopped` reports mount status; View remains passive |
| Scope-owned eager cell | Store owns mounts and close stops all; nested Scope parity is separate |
| `watch` / GC root | caller-held View plus active mount; target has no runtime-wide GC contract |
| stable cell ID | rooted diagnostics rather than a value handle |
| `expr` conversion | separate Expr target mapping; no eager-specific value type required |

The spike uses current `EagerDerived[Unit]` as a keeper that reads the supplied View. It demonstrates the public seam and current scheduling behavior without implementing a target kernel.

## Positive state

```text
before_mount.runs=0
after_mount.runs=1,value=1
after_write.runs=2,value=2
inside_batch.runs=2
after_batch.runs=3,value=4
after_stop.stopped=true,runs=3
after_stopped_write.runs=3
passive_read.value=5,runs=4
non_eq.value=20,runs=2
before_close.runs=1
after_close.counted_stopped=true,non_eq_stopped=true
positive_probes=PASS
```

The executable adapter asserts the following owner/interface behavior:

- mounting materializes once before return;
- writes trigger proactive evaluation without a caller read;
- batch writes do not run the mount until commit and produce one run;
- repeated Stop and close are idempotent;
- Stop prevents later proactive runs;
- the stopped View remains passively usable;
- a non-Eq View can be mounted;
- close covers every Store-owned mount.

## Negative compiler evidence

| Probe | Diagnostic | Meaning |
|---|---|---|
| `view.stop()` | `[4015]` no method `stop` | passive read authority has no teardown authority |
| `stop()` | `[4014]` wanted function type | Stop has no read authority |
| external Stop literal | `[4036]` read-only type | consumer cannot construct mount state |
| `stop.mount = ...` | `[4091]` no field `mount` | consumer cannot mutate mount state |

## Ownership transition

```text
mount:
  caller -> ViewState
  StoreCore -> EagerMount -> ViewState
  Stop -> EagerMount breaker

Stop::stop:
  remove StoreCore -> EagerMount
  remove scheduler subscriptions
  caller -> ViewState remains

Store::close:
  perform Stop transition for every mount
  post-close View/cache behavior remains outside this spike
```

The target implementation must physically remove the active owner edge on Stop. Current `dispose_cell` clears the keeper's compute and source slot; the adapter's Array retains only disposed handles until close. That Array is test scaffolding, not the target field layout or RC evidence. V12.4 remains authoritative for the structural ownership proof.

## Alternatives not selected

These are interface-design conclusions, rather than behaviors proved by the adapter.

| Alternative | Reason not selected |
|---|---|
| `Store::eager(compute) -> (View, Stop)` | duplicates Eq, BackdateEq, and no-backdate View creation policies |
| public `EagerView[T]` handle | recreates the read/lifecycle handle split the callable View redesign removes |
| Store-owned mount without Stop | violates the reachable-breaker requirement |
| ask callers to mount an Effect that ignores `view()` | leaks scheduling implementation and creates a shallow interface |
| invalidate View on Stop | conflicts with the selected rule that passive values require no disposal |

## Constraints

- V12.10 must decide initial and subsequent eager `ReadError` behavior. The generated placeholder signature compiles, but the adapter catches a View failure and aborts; it provides no runtime error-propagation evidence.
- V12.6 owns Stop/close interaction with in-flight dispatch, cleanup, deferred writes, and cancellation.
- The adapter does not model post-close write rejection, frozen-cache errors, nested Scope teardown, or downstream eager early-cutoff wiring. Existing current-engine tests remain the oracle for those current behaviors.
- The compile surface cannot force callers to retain Stop. Selection is conditional on the production ownership design keeping either Stop or an externally invocable Store close capability reachable for every active mount lifetime; otherwise the V12.4 reachable-breaker gate reopens.
- Release benchmarks must compare mounted Views with current EagerDerived on native RC and wasm-gc.

## Reuse check

- Reused project APIs: `Runtime`, `Input`, `EagerDerived[Unit]`, `Runtime::batch`, and eager disposal/status methods.
- Checked MoonBit core APIs: `Array::each`, `Ref`, and `Option`. `Array::each` wires close coverage; `Ref` shares close state across Store values. No mount lookup requires `Option`.
- New definitions: View and Write are prior selected probe adapters; Stop is one breaker; Store is the active-owner shell.
- Remaining imperative code: callback counters observe proactive scheduling, and the Store mount Array mirrors current ownership for the probe. Neither is a target kernel implementation.
