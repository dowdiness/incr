# Incr Next Formula exports

- **Reader:** Incr maintainers reviewing owner-scoped Formula exports.
- **Decision:** Keep `Program::export_formula` as a narrow evidence API if the multi-hop and error-channel checks remain valid.
- **Keep until:** This direction receives review or is superseded.
- **Disposition:** Keep this executable spike as evidence; move durable conclusions to an ADR or remove it afterward.

## Verdict

The evidence verdict is **Pass with constraints**. The spike
answers one question: can a Program export its own opaque Formula result as
`ReadExport[Result[V, ProgramError]]` so downstream Programs compose explicit
multi-hop edges without raw Views, foreign export, direct imported-port
reexport, or a global registry?

Run the complete check with:

```bash
bash examples/spikes/incr_next_formula_exports/run.sh
```

The workload is A/B/C. A exports source `10`; B imports A, doubles it in a
Formula, and exports that result; C imports B's export and maps `Ok(v)` to
`v + 1`. C reads `21`, then reads `41` after A changes to `20`.

B's manifest has exactly the A export to B local edge. C's manifest has exactly
the B Formula export to C local edge. Exporting a Formula does not copy its
manifest, so the provider Formula remains the place where its local manifest is
retrievable. A future observatory can aggregate Formula-local manifests.

`Program` is a capability namespace scoped to a Region, not the exclusive owner
of that Region. Multiple Programs can share a Store while using distinct
Regions, and Region closure is a lifecycle capability rather than a global
ownership registry.

## Error channels

The three channels stay distinct:

1. A kernel structural failure such as `ClosedRegion` remains the outer
   `FormulaReadError`. If A closes, B and then C report outer `ClosedRegion`.
   C does not convert it to `Ok` or to an application error.
2. A provider Formula application failure is an imported value. The provider
   Formula in the error workload returns `Err(ProgramError::UnauthorizedRead)`
   before invoking any View. C preserves that imported value and observes
   `Ok(Ok(Err(ProgramError::UnauthorizedRead(_))))`; no source read occurs.
3. C's own authorization or application failure instead has the distinct shape
   `Ok(Err(ProgramError::UnauthorizedRead(_)))`. Provider and consumer
   application errors therefore do not collapse into one channel.

The wrapper records the first structural kernel error and does not catch it into
an application `Ok`. Formula callback confinement is a caller-owned purity
contract, not a type-enforced property: admissible callbacks read only captured
`DeclaredRead` values. Callbacks that capture Programs and allocate ports,
builders, declarations, exports, or lifecycle objects are excluded from this
evidence. Rejecting or deferring those mutations remains future work.

## Boundary evidence

Formula is opaque and has no `Formula::view`. Formula export validates the
FormulaId owner and the Formula Store/Region identity before allocating an
ExportId. Repeated export of one own Formula gets distinct ExportIds. A foreign
Formula is rejected without advancing the importing Program's next export.

One Formula export can be imported by two consumers: the ExportId is shared and
local PortIds differ. `export_port` remains `ReexportForbidden`, and B's
identity/forwarding Formula remains the edge mediator.

The derived provider imports only the upstream feature facade and `program`; it
imports A's typed export, defines B's Formula, and exports its output. The C
consumer imports facades and `program`, not the kernel. Raw View, Query keys,
and opaque literal construction remain inaccessible through generated public
interfaces. There is no Mount, Action, Resource, effects, Canopy, LRU, or
registry layer.

## Existing API first

The implementation reuses typed `Map`, `Array`, `Option`, `Result`, `Ref`,
`Hash`, and `Eq`. `Set` and `HashSet` were checked and are intentionally not
used. `String` and `string`, `Bytes` and `bytes`, `Buffer` and string builders,
and `cmp` were checked and do not fit these typed identities. No collection
abstraction, erased key/value table, or graph registry was added.
