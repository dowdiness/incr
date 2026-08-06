# V12.3 nominal Write capability spike

> **PROTOTYPE — evidence only. Do not merge this module into the public API.**

- **Reader:** maintainers resolving the V12.3 write-capability mapping in #453 and #456.
- **Decision:** determine whether MoonBit can pair callable `View[T]` with nominal `Write[T]` while preserving Eq-gated `set`, unrestricted `force_set`, and read/write authority separation.
- **Keep until:** V12.3 records the target Write mapping and any implementation no longer needs the compiler evidence.
- **Disposition:** preserve only on the evidence branch; do not merge the spike into `main`.

## Run

From the repository root:

```bash
./examples/spikes/v12_3_write_capability/check.sh
```

The command runs the positive native probe, then activates each disabled negative probe one at a time and verifies the expected compiler diagnostic.

## Verdict

**Pass with constraints.**

MoonBit can express:

```moonbit
let (view, write) = store.input(initial)
let value = view()
write.set(next_eq_value)
write.force_set(next_value)
```

The provider exports a callable function alias for read authority and an opaque nominal struct for write authority. A method-level `T : Eq` bound on `Write::set` coexists with unbounded `Write::force_set`. Both capabilities can be passed independently across the provider/consumer package boundary.

The probe reuses the current `Runtime` and `Input` implementation as its backing state. It validates the target type shape and authority boundary, not replacement-kernel ownership or lifecycle behavior. PR #455 is the semantic oracle for same-value suppression, forced commits, callbacks, revisions, and rollback.

## Positive state

The runner prints every relevant value transition:

```text
int.initial=1
int.after_equal_set=1
int.after_changed_set=2
int.after_equal_force_set=2
non_eq.initial.tag=10
non_eq.after_force_set.tag=20
positive_probes=PASS
```

`NonEqValue` contains a function field and has no `Eq` implementation. Its `force_set` call compiles and updates the value.

## Negative compiler evidence

| Probe | Required diagnostic | Meaning |
|---|---|---|
| non-Eq `write.set` | `[4018]` does not implement `Eq` | `set` retains its equality contract |
| `view.set` | `[4015]` no method `set` | View has no write authority |
| `write()` | `[4014]` wanted function type | Write has no callable read authority |
| external Write literal | `[4036]` read-only type | Consumer cannot construct provider state |
| `write.input = ...` | `[4091]` no field `input` | Consumer cannot mutate provider state |

## Constraint: ReadError remains V12.10 work

Using the current value-level `@incr.ReadError` directly in a raising function alias fails with `[4127]`: it is not a MoonBit error type. This spike therefore uses provider-local `ProbeReadError` only to retain the raising callable shape. It does not select the eventual `ReadError` hierarchy or representation.

## Reuse check

- Reused project APIs: `Runtime`, `Input`, `Input::set`, and `Input::force_set`.
- Checked but not reused: `InputView` preserves read-only authority but is not callable.
- Checked MoonBit core APIs: `Ref`, `Option`, and `Result`. `Ref` would expose generic mutable-state semantics inside the probe; the current Input backing is closer to the capability being mapped. `Option` and `Result` do not fit this state shape.
- New definitions: `Store` is a creation shell, `View[T]` is read authority, and `Write[T]` is write authority. No new loop or data-manipulation helper is introduced.
