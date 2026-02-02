# TODO

Concrete, actionable tasks for the `incr` library.

## Error Handling

- [ ] Define a `CycleError` type and return it instead of calling `abort()` in `verify.mbt:38`
- [ ] Add `Signal::get_result()` and `Memo::get_result()` that propagate `CycleError`

## Performance

- [ ] Use `HashSet` for deduplication in `ActiveQuery::record` (`tracking.mbt:18-23`) — current linear scan is O(n) per dependency
- [ ] Replace `HashMap[CellId, CellMeta]` in `Runtime` with a flat `Array[CellMeta]` indexed by `CellId.id`
- [ ] Diff old vs. new dependency lists in `Memo::force_recompute` instead of full replacement

## API Improvements

- [ ] Add `Runtime::batch(fn)` that defers revision bump until the closure completes
- [ ] Add `Signal::set_unconditional(value)` that always bumps the revision (skip same-value check)
- [ ] Add public introspection methods: `Runtime::dependencies(CellId)`, `Runtime::dependents(CellId)`, `CellMeta::state()`

## Testing

- [ ] Stress test: deep dependency chain (100+ levels) to verify recursion and performance
- [ ] Wide fanout test: single signal with many downstream memos
- [ ] Test `Memo` with custom `Eq` types where structural equality differs from identity
- [ ] Edge case tests for `set_unconditional` (once implemented)
- [ ] Test cycle detection across 3+ mutually recursive memos

## Documentation

- [ ] Add doc comments to all public functions
- [ ] Add usage examples for durability in README
