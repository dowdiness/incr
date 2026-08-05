# V12.5 View Alternatives Compile Probe

**Status:** Throwaway prototype. This branch records language and API evidence;
it does not authorize a production API or kernel replacement.

**Question:** Which interface shape best preserves callable product DX without
losing recoverable Cycle errors, Runtime provenance, labels, diagnostics, or a
cell-bound update capability?

## Alternatives

1. **Transparent getter** — `() -> T` or `() -> Result[T, ReadError]`.
2. **Opaque View** — a nominal handle with explicit `get()` / `get_or_abort()`.
3. **Two-layer** — the opaque kernel handle plus product-local getter closures.

The probe wraps the current `@incr.Input`, `@incr.Derived`, `CellId`, and
`ReadError`; it does not implement a new reactive kernel.

## Reuse check

Project APIs reused or compared:

- `InputView[T]`: existing opaque read-only wrapper.
- `Derived[T]` + `ReadError`: stable identity and recoverable graph errors.
- `Input::set` / `force_set`: distinct equality-suppressing and unconditional
  write semantics.
- `ideal_api_rename_phase0`: provider/consumer spike layout.

MoonBit core APIs checked:

- first-class closures for callable product adapters;
- `Result` for recoverable Cycle reads;
- `Option` for optional labels;
- `Ref` for the self-cycle recovery probe and mutable render sink.

No `Array`, `Map`, or `Set` processing was added because this probe is about
capability representation rather than collections.

## Run

From this spike directory:

```bash
moon check
moon test
```

The positive probes cover:

- transparent getter + cell-bound updater syntax;
- opaque read/write handles;
- product-local closures over a retained opaque handle;
- stable CellId, RuntimeId provenance, and labels;
- recoverable self-cycle behavior;
- a UI-shaped binding that preserves `ReadError`.

## Negative compiler evidence

The negative snippets were compiled one at a time and removed after capturing
the diagnostics.

### Opaque handles are not callable

```moonbit
fn negative_opaque_call(view : @probe.OpaqueView[Int]) -> Int {
  view()
}
```

Compiler `[4014]`:

```text
has type : ...OpaqueView[Int]
wanted   : function type
```

### Transparent getters have no metadata/provenance seam

```moonbit
fn negative_getter_metadata(
  getter : @probe.PlainGetter[Int],
) -> @incr.CellId {
  getter.id()
}
```

Compiler `[4015]`:

```text
Type () -> Int has no method id.
```

### A setter alone cannot implement read-modify-write

```moonbit
fn negative_setter_update(
  setter : @probe.ForceSetter[Int],
  transform : (Int) -> Int,
) -> Unit {
  setter(transform(setter.get()))
}
```

Compiler `[4015]`:

```text
Type (Int) -> Unit has no method get.
```

The updater must therefore be created alongside the input or attached to an
opaque input token. The probe's updater uses `peek()` + `force_set()` and is
not safe against re-entrant writes; it proves representation feasibility, not
atomic update semantics.

MoonBit also requires parentheses when calling a function stored in a record
field: `(record.field)(args)`, not `record.field(args)`.

## Result matrix

| Property | Transparent getter | Opaque View | Two-layer |
|---|---:|---:|---:|
| `value()` product syntax | Yes | No | Yes, via local closure |
| Recoverable Cycle | Only with `() -> Result[...]` | Yes | Yes in handle/local honest getter |
| Stable CellId / RuntimeId | No | Yes | Yes via retained handle |
| Label / diagnostics | No | Yes | Yes via retained handle |
| Cross-Store provenance check | No public seam | Yes | Yes via retained handle |
| Cell-bound updater | Must be returned separately | Yes in writer handle | Yes in writer handle/local capability |
| Arbitrary thunk distinguishable from reactive view | No | Yes | Kernel handle: yes; local closure: no |

## Verdict

**Choose the two-layer interface for the redesign track:**

- The kernel-facing API remains an opaque handle with
  `get() -> Result[T, ReadError]`, identity, provenance, labels, and diagnostics.
- Product modules may create ordinary local closures for ergonomic composition.
  They retain the opaque handle whenever diagnostics, teardown, update, or
  cross-Store checks are needed.
- A local `() -> T` closure is an explicit aborting convenience, not the honest
  kernel contract. A local `() -> Result[T, ReadError]` preserves recovery and
  is the default at UI/FFI quarantine boundaries.
- Input creation must return write/update capabilities together; a bare setter
  cannot be upgraded into an updater later.

This resolves V12.5 in favor of the two-layer alternative and keeps Cycle
recoverable at the kernel boundary. It rejects `View[T] = () -> T` as the sole
public kernel interface.

## Remaining constraints

- The wrapper duplicates the caller-supplied label because current `Derived`
  does not expose its stored label directly.
- The prototype updater is not an atomic or re-entrant-safe contract.
- Current cross-Store misuse still aborts inside the kernel; this probe only
  proves that opaque handles retain enough provenance to diagnose or reject it
  before composition.
- This result does not settle D1's ownership/RC proof, D5 scheduling, D6 keyed
  retirement, or the full Effect contract.

## Disposition

Keep this prototype on the throwaway `spike/v12-5-view-alternatives` branch as
primary compile evidence. Distill only the verdict into the research decision
record; do not merge the spike into the production branch.
