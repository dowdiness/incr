# Incr Next read ports

- **Reader:** Incr maintainers evaluating a typed program facade over the published #466 follow-up kernel.
- **Decision:** Test whether one Formula-local builder can produce both a declared Port manifest and the runtime authorization set while keeping opaque kernel Views and Query key types private to the facade.
- **Keep until:** The typed read-port direction is accepted, rejected, or superseded.
- **Disposition:** Keep this executable spike as evidence; preserve any durable conclusion in an ADR or remove the spike afterward.

Run the complete check with:

```bash
bash examples/spikes/incr_next_read_ports/run.sh
```

## Result

The spike passes its constrained workloads. `Program` wraps an existing
`@kernel.Region`; `ReadPort[V]` privately retains a typed opaque
`@kernel.View[V]` and a Program-owned `PortId`. `FormulaBuilder::declare_port`
adds a Port once to ordered `Manifest` state and to the same builder's private
runtime authorization map. Every build attempt consumes the builder, including
kernel phase or Region rejection. A `Formula` exposes its typed result View,
manifest, and defensive debug snapshots.

Formula callbacks receive only `ProgramEvalCtx` and captured `DeclaredRead`
values. `ProgramEvalCtx::read` checks Formula/builder identity and authorization
before recording `{port_id, ordinal}` and invoking the kernel View. Unauthorized
application failures are returned inside the Formula value as
`Result[V, ProgramError]`; kernel `ClosedRegion` and `Cycle` remain the outer
`@kernel.ReadError` channel. The caller contract is that Formula evaluation is
pure: do not create Ports, builders, declarations, or other Program lifecycle
objects from inside a callback. Region/query definition methods still validate
the kernel's global phase and return their typed definition errors.

The result View intentionally remains a normal opaque kernel View so Formulas
compose with existing pull reads. Its public kernel-native handle/origin/lifetime
metadata remains available, but no Program manifest, authorization state,
observations, Formula key type, or underlying ReadPort key type crosses that
boundary.

No kernel provider is forked. There is no generic Sheet/string registry, erased
key/value registry, mount/action/resource/effect/callback/publication layer, or
Canopy/LRU behavior. Deleting `program_provider/` leaves the imported kernel
package untouched.

## Existing API First

The implementation reuses typed `Map::contains/set/copy`, `Array::contains/copy`,
`Option`, `Result`, `Ref`, `Hash`, and `Eq`. `Set`/`HashSet` was checked but is
unnecessary because the builder's typed Map supplies deduplication and the
manifest's Array preserves declaration order. `String`/`StringView`,
`Bytes`/`BytesView`, `Buffer`/`StringBuilder`, and `cmp`/`math` were checked but
do not fit typed capability identity or this evidence formatting. No new
collection abstraction or erased registry is introduced.

## Evidence workloads

The consumer checks initial typed reads, same-View distinct Port identity,
dynamic branch observations with stable manifests, duplicate declarations with
repeated invocation ordinals, foreign declarations without a Source read,
cross-Program rejection, consuming failed/successful builds, structural error
transparency, and application-level Unauthorized results. The harness checks
opaque/private boundaries, generated-interface Query-key absence, native/wasm
output equality, and unchanged #461-#466 evidence trees/executables.
