# Incr Next cross-program ports

- **Reader:** Incr maintainers evaluating typed provider/consumer feature-package boundaries.
- **Decision:** Keep provider-owned `ReadExport[V]` separate from consumer-owned `ReadPort[V]`. One `import_export` plus `declare_port` path records authorization and the explicit edge `(provider ProgramId, ExportId) -> (consumer ProgramId, PortId)`.
- **Keep until:** The cross-program port direction receives final review or is superseded.
- **Disposition:** Keep this executable spike as evidence; move durable conclusions to an ADR or remove it afterward.

The evidence result is **Pass with constraints**. This finite spike does not
prove every admissible feature graph or authorize a production API. Run:

```bash
bash examples/spikes/incr_next_cross_program_ports/run.sh
```

## Boundary and ownership

`program` is an optional facade over the unchanged published #467 kernel. A
`Program` owns a `ProgramId`, one kernel `Store`/`Region` identity, local port
allocation, and export allocation. `Program::export(view)` accepts only a View
from its Region and creates a private `ReadExport[V]` containing the provider
identity, `ExportId`, Store identity, and View. There is no export registry.

A consumer gets a same-Store Program from `feature_provider` and calls
`import_export(export)`; MoonBit reserves the shorter `import` identifier.
Store validation happens before local `PortId`
allocation. A rejected different-Store import therefore cannot consume a View
or advance the consumer's port sequence.

Same export imported twice by one consumer gets two local ports. The same export
imported by two consumers keeps one ExportId and receives distinct
consumer-owned PortIds. Imported ports have
`Imported(provider_program, export_id)` origin; local ports have `Local` origin.
Re-export is explicit and returns `ReexportForbidden`.

`feature_provider` privately owns the raw kernel Source and View. Its public
facade returns only typed exports, ports, Programs, values, and lifecycle
operations. `feature_consumer` imports the feature facade and `program`, never
`kernel`; its Formula result is read through `Program::read`. Negative probes
cover raw View extraction, Query-key construction, and opaque value literals.

The Formula builder consumes itself on success and on kernel rejection. A
single declaration transition deduplicates ordered immutable manifest entries
and populates the runtime authorization map. Evaluation records authorized
read attempts with local PortId, origin, and ordinal. This is an attempt trace,
not the kernel's last-successful dependency trace and not transitive Query
attribution. Structural kernel errors stay outside the application result;
first structural error wins. Escaped `ProgramEvalCtx` values reject reads after
invocation expiry without recording or invoking a View.

The caller purity contract is explicit: callbacks may read their captured
`DeclaredRead` values only. They must not create Programs, Ports, builders,
declarations, or lifecycle objects. No Mount, Action, Resource, effect,
Canopy, LRU, mutation, or global registry is part of this spike.

## Existing API first

The implementation reuses typed `Map`, `Array`, `Option`, `Result`, `Ref`,
`Hash`, and `Eq`. `Set`/`HashSet` was checked and is intentionally unused:
`Map` supplies authorization deduplication while `Array` preserves manifest
order. `String`/`StringView`, `Bytes`/`BytesView`, `Buffer`/`StringBuilder`,
and `cmp`/`math` were checked and do not fit these typed identities. No new
collection abstraction is introduced.
