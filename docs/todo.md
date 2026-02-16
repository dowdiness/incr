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

### Introspection API (Phase 2A - High Priority)

- [x] Add `Signal::id(self) -> CellId`
- [x] Add `Signal::durability(self) -> Durability`
- [x] Add `Memo::dependencies(self) -> Array[CellId]`
- [x] Add `Memo::changed_at(self) -> Revision`
- [x] Add `Memo::verified_at(self) -> Revision`
- [x] Add `Runtime::cell_info(self, CellId) -> CellInfo?` struct
- [x] Define `CellInfo` struct with all cell metadata
- [ ] Add `Signal::debug(self) -> String` for formatted output
- [ ] Add `Memo::debug(self) -> String` for formatted output

### Error Diagnostics (Phase 2A - High Priority)

- [x] Change `CycleError` to include cycle path: `CycleDetected(CellId, Array[CellId])`
- [x] Add `CycleError::path(self) -> Array[CellId]`
- [x] Add `CycleError::format_path(self, Runtime) -> String` for human-readable output
- [x] Update cycle detection in `verify.mbt` to track path during traversal

### Per-Cell Callbacks (Phase 2B - High Priority)

- [ ] Add `on_change : (() -> Unit)?` field to `CellMeta` (or type-erased callback)
- [ ] Add `Signal::on_change(self, f : (T) -> Unit) -> Unit`
- [ ] Add `Memo::on_change(self, f : (T) -> Unit) -> Unit`
- [ ] Add `Signal::clear_on_change(self) -> Unit`
- [ ] Add `Memo::clear_on_change(self) -> Unit`
- [ ] Fire per-cell callbacks before `Runtime::fire_on_change()`
- [ ] Test callback execution order (per-cell before global)

### Builder Pattern (Phase 2C - Medium Priority)

- [ ] Define `SignalBuilder[T]` struct
- [ ] Add `Signal::builder(Runtime) -> SignalBuilder[T]`
- [ ] Add `SignalBuilder::with_value(T) -> Self`
- [ ] Add `SignalBuilder::with_durability(Durability) -> Self`
- [ ] Add `SignalBuilder::with_label(String) -> Self` (for future introspection)
- [ ] Add `SignalBuilder::build() -> Signal[T]`
- [ ] Define `MemoBuilder[T]` struct with similar pattern
- [ ] Document builder pattern in API reference

### Ergonomics (Phase 2C - Medium Priority)

- [ ] Add `Runtime::with_on_change(self, f) -> Runtime` for method chaining
- [ ] Add convenience helper `memo[Db : IncrDb, T : Eq](db, f) -> Memo[T]`
- [ ] Explore RAII `BatchGuard` if MoonBit adds destructors

### Advanced (Phase 4)

- [ ] Add subscriber (reverse) links for push-based invalidation
- [ ] Add `Runtime::dependents(CellId) -> Array[CellId]` (requires subscriber links)

## Testing

- [x] Stress test: deep dependency chain (250 levels) to verify iterative verification
- [x] Wide fanout test: single signal with many downstream memos
- [x] Test `Memo` with custom `Eq` types where structural equality differs from identity
- [x] Test cycle detection across 3+ mutually recursive memos

## Documentation

- [x] Add doc comments to all public functions
- [x] Add usage examples for durability in README
- [x] Keep [design.md](design.md) in sync when core algorithms change
- [x] Organize user documentation in `docs/` folder (getting-started, concepts, api-reference, cookbook)
