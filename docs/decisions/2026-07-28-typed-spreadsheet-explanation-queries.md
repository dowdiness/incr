# ADR: Typed spreadsheet deterministic explanation queries

**Date:** 2026-07-28

**Status:** Accepted

**Driver:** GitHub issue [#218](https://github.com/dowdiness/incr/issues/218)

**Reader:** Maintainers extending typed-spreadsheet inspection for human or AI/tool consumers.

**Decision:** Keep deterministic, bounded spreadsheet explanations in the shared `examples/typed_spreadsheet_demo` module, expose query-specific answers for current-cell semantics and latest-edit evidence, and render them through an on-demand Rabbita adapter.

**Keep until:** Permanently; supersede this ADR if explanation ownership moves out of the typed-spreadsheet domain or complete-sheet indexing changes the scope contract.

**Disposition:** Keep as an accepted ADR. Do not archive it with implementation plans.

## Context

The typed-spreadsheet demos already publish a schema-versioned `AiContextSnapshot` containing an ordered bounded region, cell values and formula metadata, static references, last dynamic dependencies, and optional trace/evidence history. Rabbita previously exposed Trace and Evidence as separate always-available inspectors. That made engine activity prominent while requiring callers to reconstruct the semantic answer to a simpler question: which values produced the selected cell's current value?

A throwaway prototype compared an answer rail, causal strip, and investigation desk. It established that the useful primary facts are the selected cell, current result, formula, and dynamically active inputs. Static-but-inactive references and recomputation history remain useful, but only as secondary evidence.

## Decision

### Keep the seam in the shared spreadsheet demo module

`explain_cell(snapshot, subject)` and `explain_last_change(snapshot, subject)` consume `AiContextSnapshot` values in `examples/typed_spreadsheet_demo`. They do not depend on Rabbita, `incr_tea`, DOM state, or mutable `Worksheet` state, and they do not become generic `incr` engine interfaces.

The module is deep at this seam: callers supply one bounded snapshot and receive stable semantic facts without repeating cell lookup, active/inactive classification, out-of-region handling, trace copying, or evidence normalization.

### Use query-specific answers

`ExplainCellAnswer` owns current semantic facts. It separates `active_inputs` from static `inactive_inputs` and reports `CellOutsideObservedRegion` rather than implying complete-sheet knowledge.

`LastChangeAnswer` owns optional selected-cell before/after evidence and secondary `ExplanationTrace` diagnostics. It is distinct from the current-value answer because recomputation activity is not itself a semantic cause of the value.

The answer schema starts at version 1. Returned collections use `ReadOnlyArray`; region and trace arrays are copied at the query seam so callers cannot mutate retained answer state through a source snapshot. Query answers convert serialization-oriented strings into `ExplanationCellKind`, `ExplanationResult`, `ExplanationInputState`, and `ExplanationChange` variants. Unknown variants retain forward-compatible source labels without permitting contradictory states such as `observed = false` with a present result.

### Make bounded scope explicit

Every answer carries `ExplanationScope`: the ordered observed region, configured limit, and truncation flag. Active references outside that region remain in the answer as unobserved inputs without an invented result.

Complete-sheet dependents and errors are not part of this interface. They require a separate worksheet index before they can claim completeness without scanning the sheet.

### Keep the UI on demand

Rabbita starts with the explanation closed. One `explain <selected cell>` toggle replaces the separate Trace and Evidence toggles. The open inspector follows selection and shows only the current result, formula, and active inputs by default. Inactive references appear only when present. Selected-cell latest-edit evidence appears only when captured, with trace and before/after details behind one disclosure.

The Rabbita package remains a thin adapter: selection and overlay state stay in its reducer; explanation decisions stay in the shared pure module. Its model retains one private `ExplanationFrame` containing the coherent context snapshot, current-cell answer, and latest-change answer. The reducer refreshes that frame atomically after relevant messages, while the view only renders the frame and never reads `Worksheet`.

## Rejected alternatives

- **One generic `ExplanationAnswer` union:** rejected because each query would expose fields and invariants irrelevant to most callers.
- **Put explanations in `incr` core:** rejected because formulas, cells, observed regions, and before/after spreadsheet evidence are application-domain concepts.
- **Claim complete dependents/errors from the bounded snapshot:** rejected because absence outside the region is unknown, not empty.
- **Treat static references as current causes:** rejected because conditional formulas can retain an inactive branch reference that did not participate in the current result.
- **Keep separate or always-open Trace/Evidence panels:** rejected because they prioritize engine diagnostics over routine spreadsheet work.
- **Generate explanatory prose:** rejected because deterministic structured facts are more testable, reusable, and trustworthy for both UI and tools.

## Consequences

- Rabbita and future adapters can share one deterministic explanation interface while choosing different presentations.
- AI/tool consumers can serialize the query-specific answers instead of scraping UI text or reconstructing dependencies.
- `AiContextSnapshot` remains the adapter-neutral input and retains its bounded contract. Schema version 2 adds structured before/after results alongside the compatibility display fields in evidence cells.
- Trace and evidence remain available but are no longer the primary navigation model in Rabbita.
- A future complete-sheet query must introduce and validate an index, then either add a separately scoped answer type or supersede the bounded part of this ADR.
