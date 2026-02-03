# TODO

Concrete, actionable tasks for the `incr` library.

## Error Handling

- [x] Define a `CycleError` type and return it instead of calling `abort()` in verification
- [x] Add `Signal::get_result()` and `Memo::get_result()` that propagate `CycleError`
- [x] Ensure failed `get_result()` calls don't record dependencies (prevents spurious cycles)

## Performance

- [x] Use `HashSet` for deduplication in `ActiveQuery::record` — O(1) per dependency
- [x] Replace `HashMap[CellId, CellMeta]` in `Runtime` with `Array[CellMeta?]` indexed by `CellId.id`
- [x] Convert recursive `maybe_changed_after` to iterative with explicit stack (prevents stack overflow on deep graphs)
- [ ] Diff old vs. new dependency lists in `Memo::force_recompute` instead of full replacement
- [ ] Explore push-pull hybrid invalidation (requires subscriber/reverse links)

## API Improvements

- [x] Add `Runtime::batch(fn)` that defers revision bump until the closure completes
- [x] Add two-phase signal values with revert detection in batch mode
- [x] `Signal::set_unconditional(value)` already exists — always bumps the revision
- [ ] Add public introspection methods: `Runtime::dependencies(CellId)`, `Runtime::dependents(CellId)`, `CellMeta::state()`
- [ ] Add subscriber (reverse) links for push-based invalidation

## Testing

- [x] Stress test: deep dependency chain (250 levels) to verify iterative verification
- [ ] Wide fanout test: single signal with many downstream memos
- [ ] Test `Memo` with custom `Eq` types where structural equality differs from identity
- [x] Test cycle detection across 3+ mutually recursive memos

## Documentation

- [x] Add doc comments to all public functions
- [x] Add usage examples for durability in README
- [x] Keep [DESIGN.md](DESIGN.md) in sync when core algorithms change
- [x] Organize user documentation in `docs/` folder (getting-started, concepts, api-reference, cookbook)
