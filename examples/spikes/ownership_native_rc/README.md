# Ownership native-RC probe

**Status:** Throwaway native-only evidence for [incr #451](https://github.com/dowdiness/incr/issues/451). This is not production runtime code.

**Reader:** Maintainers deciding whether V12.4 qualifies as `Pass with constraints`.

**Decision:** Preserve as primary native-RC evidence on the spike branch.

**Keep until:** #451 records `Pass with constraints` and the durable invariants are absorbed into the canonical retention brief.

**Disposition:** Preserve only on the spike branch; its branch-local documentation index links this reproducible evidence.

## Question

Does MoonBit native reclamation follow the field-level ownership argument across multiple passive nodes, active breakers, keyed surviving getters, and the opaque cycles excluded by the scoped guarantee?

## Run

From the repository root:

```bash
moon run examples/spikes/ownership_native_rc --target native
```

The command builds the C finalizer probe, creates every scenario with a batch size of 32, prints all expected and observed before/after/finalized counters, and aborts if any value differs from the ownership argument.

## Observation method

MoonBit core currently exposes no `WeakRef`, user destructor, or public finalizer API. This probe therefore uses the native runtime's `moonbit_make_external_object` API.

Each relevant closure or cached payload strongly owns one opaque `RcProbeToken`. The C token finalizer updates category-specific `live` and `finalized` counters when MoonBit native RC releases the last token reference. Primitive counter queries do not retain the token.

This is stronger than a hand-simulated RC graph because the MoonBit compiler and native runtime perform the actual closure conversion, reference counting, and finalization. It remains proxy evidence: the token marks the tested ownership path rather than acting as a destructor on every private MoonBit state object.

## Scenarios

| Scenario | Instances | Before | After breaker/drop | Finalized | Result |
|---|---:|---:|---:|---:|---|
| Passive acyclic chain | 32 nodes | 32 | 0 | 32 | Pass |
| Passive acyclic diamonds | 32 diamonds / 128 marked nodes | 128 | 0 | 128 | Pass |
| Mounted Effect then Stop | 32 | 32 | 0 | 32 | Pass |
| Mounted Effect then `Store.close()` | 32 | 32 | 0 | 32 | Pass |
| Listener then token removal | 32 | 32 | 0 | 32 | Pass |
| Deferred write then flush | 32 | 32 | 0 | 32 | Pass |
| Pending deferred write then `Store.close()` | 32 | 32 | 0 | 32 | Pass |
| Keyed membership retired; getter survives then drops | 32 | 32 while getters survive | 0 | 32 | Pass |
| Late-bound compute cycle | 32 | 32 | 32 | 0 | Expected retention |
| Cached owning-collection cycle | 32 | 32 | 32 | 0 | Expected retention |
| Two-View capture cycle | 32 pairs / 64 tokens | 64 | 64 | 0 | Expected retention |

## Field correspondence

The probe reuses the checked provider in
[`ownership_field_skeleton`](../ownership_field_skeleton/README.md) rather than copying its private target structs.

- `Store::probe_passive_chain` creates upstream-only ViewState ownership.
- `Store::probe_passive_diamond` creates shared passive upstream ownership with no Core reverse edge; each diamond marks its InputState seed plus both branches and root.
- `Store::mount` and `Stop::stop` exercise `Core -> mount -> callback -> View -> state -> Core`, then remove the identified Core registry entry.
- `Store::close` removes all mount, listener, and deferred owner edges.
- `retire_keyed_for_probe` removes membership while returning the independently rooted getter.
- Consumer closures create the three opaque cycle classes without adding a reactive dependency edge.

## Cached owning collection

The cache counterexample stores an `Array[View[CachedPayload]]` inside an Eq payload. After materialization, the array receives its own View:

```text
ViewState -> CachedValue[T] -> T.views -> View -> ViewState
```

Its `Eq` implementation compares only a scalar marker. This confirms both parts of the field argument: `T : Eq` does not imply acyclic ownership, and an owning cached collection can form the excluded passive SCC.

## Verdict

**Pass with constraints.** Actual MoonBit native finalization matches the structural ownership argument for all required multi-instance scenarios. No native counterexample was found for library-controlled passive edges or effective active breakers.

The following constraints remain part of the verdict:

1. StoreCore owns no passive ViewState, InputState, keyed entry, or all-Views registry.
2. Committed dependency ownership points upstream only.
3. Stop, listener removal, queue flush, and close remove their actual owner edges.
4. The no-cycle guarantee is scoped to library-controlled fields.
5. Compute captures and cached values remain caller-owned retention sources.
6. Keyed retirement remains gated by F7 surviving-dependency semantics.

## Limits

- External-object finalizers are native-only and used solely for observation; the C counters are intentionally single-threaded.
- The probe demonstrates ownership cuts, not production scheduling, cancellation, error propagation, or Effect cleanup ordering.
- Intentionally opaque cycles remain alive until process exit; this is the expected counterexample.
- Results supplement the field-level SCC argument; they do not replace it.
- V12.3 semantic parity and V12.6 interleavings remain separate gates.
- No replacement-kernel implementation is authorized.

The remaining V12.4 action is to record `Pass with constraints` and its invariants in the canonical retention brief as a separate documentation change.
