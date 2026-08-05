# Ownership field skeleton

**Status:** Throwaway compile probe for [incr #451](https://github.com/dowdiness/incr/issues/451). This is not a production implementation or public API proposal.

**Reader:** Maintainers deciding whether the V12.4 field-level ownership layout is expressible in MoonBit.

**Decision:** Preserve as primary compiler evidence on the spike branch.

**Keep until:** #451 reaches its final ownership verdict.

**Disposition:** Keep off `main`; absorb validated constraints into the canonical retention brief.

## Question

Can MoonBit express the candidate field layout with the scoped ownership guarantee: no library-controlled passive back-edge, while unrestricted compute captures and cached values remain demonstrably outside that guarantee?

## Run

From the repository root:

```bash
moon run examples/spikes/ownership_field_skeleton/consumer --target native
```

The command compiles the provider/consumer package boundary and prints every relevant constructed state.

## Field shape

The provider separates:

- public `Store` façade from private `StoreCore`;
- callable `View[T]` closure from private `ViewState[T]`;
- private `CachedValue[T]` and `DependencyCollection`;
- shared private `InputState[T]` from nominal public `Write[T]`;
- Store-owned mounts, deferred commands, and listener records;
- external `Stop` and `ListenerToken` capabilities;
- keyed owner, entry, and surviving getter.

`StoreCore` contains only the active fields `mounts`, `deferred`, and `listeners`. It contains no `ViewState`, `InputState`, keyed entry, or all-Views registry.

Heterogeneous dependency ownership uses a private `DependencyAnchor` closure. Each anchor lexically captures one upstream state while erasing its generic value type. The downstream compute in this probe returns a constant, so those upstream references occur only in the anchors. This adds one production-shaped erasure node that the first ownership model had collapsed into `DependencyCollection -> upstream state`. Native evidence must still confirm the compiled retention behavior.

## Positive results

The probe compiles and executes these shapes:

1. a callable View captures private ViewState across the provider boundary;
2. one dependency collection strongly retains both `InputState[Int]` and `ViewState[Int]` through two type-erased anchors;
3. nominal `Write[T]` shares InputState with its read View;
4. Stop and ListenerToken retain Core plus their active record identity;
5. Stop/token invocation removes the identified Store-owned registry entry;
6. flush and close clear Store-owned active collections;
7. keyed membership can be removed while a surviving getter still reads its entry.

## Opaque-cycle counterexamples

All three ownership cycles compile from the consumer package using the public callable View API.

### Late-bound compute capture

```text
ViewState -> compute closure -> Ref[View?] -> View -> ViewState
```

### Cached Eq payload

```text
ViewState -> CachedValue[T] -> T.backref -> View -> ViewState
```

The consumer-defined payload implements `Eq` using an integer marker while retaining a View through a separate `Ref`. Therefore `T : Eq` does not imply acyclic ownership.

### Two-View capture

```text
ViewState A -> compute A -> Ref[View B?] -> View B -> ViewState B
ViewState B -> compute B -> Ref[View A?] -> View A -> ViewState A
```

These are ownership cycles even though no reactive dependency read is executed.

## Cross-package privacy evidence

`consumer/private_field_probe.mbt.disabled` contains this intentionally rejected access:

```moonbit
ignore(store.core)
```

Reproduce the compiler rejection from the repository root:

```bash
cp examples/spikes/ownership_field_skeleton/consumer/private_field_probe.mbt.disabled \
  examples/spikes/ownership_field_skeleton/consumer/private_field_probe.mbt
moon check --target native examples/spikes/ownership_field_skeleton/consumer
rm examples/spikes/ownership_field_skeleton/consumer/private_field_probe.mbt
```

The targeted check produces:

```text
Error: [4091]
The type @examples/spikes/ownership_field_skeleton/provider.Store has no field core.
```

This confirms the callable public surface does not expose StoreCore or private state metadata.

## Verdict

**Pass with constraints.** The production-shaped library-controlled fields are expressible without a passive Core registry. The compiler also confirms that unrestricted compute captures and cached Eq values can create passive cycles. V12.4 must retain the scoped guarantee:

> Incr introduces no passive cycle through library-controlled fields. Ownership cycles introduced by user closures or cached values remain caller-owned.

A global no-cycle guarantee is incompatible with the selected callable View and unrestricted generic cached values.

## Limits

- This probe checks type shape and closure construction, not deallocation.
- `Stop`, listener removal, flush, and close only demonstrate the required ownership cuts; they do not implement production scheduling or interleavings.
- `DependencyAnchor` is a candidate type-erasure shape, not a selected production representation.
- Keyed retirement remains gated by F7 surviving-dependency semantics.
- No replacement-kernel work is authorized.

The separate [`ownership_native_rc`](../ownership_native_rc/README.md) probe now exercises these fields with multi-instance native finalizer counters. The remaining V12.4 action is the durable canonical-brief update.
