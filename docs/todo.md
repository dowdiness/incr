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
- [x] Diff old vs. new dependency lists in `Memo::force_recompute` instead of full replacement
- [ ] Explore push-pull hybrid invalidation (requires subscriber/reverse links)

## API Improvements

- [x] Add `Runtime::batch(fn)` that defers revision bump until the closure completes
- [x] Add two-phase signal values with revert detection in batch mode
- [x] Roll back pending batch writes when batch closure raises (graceful error path)
- [x] `Signal::set_unconditional(value)` already exists — always bumps the revision

### Introspection API (Phase 2A - High Priority)

- [x] Add `Signal::id(self) -> CellId`
- [x] Add `Signal::durability(self) -> Durability`
- [x] Add `Memo::dependencies(self) -> Array[CellId]`
- [x] Add `Memo::changed_at(self) -> Revision`
- [x] Add `Memo::verified_at(self) -> Revision`
- [x] Add `Runtime::cell_info(self, CellId) -> CellInfo?` struct
- [x] Define `CellInfo` struct with all cell metadata
- [x] Add `Signal::debug(self) -> String` for formatted output
- [x] Add `Memo::debug(self) -> String` for formatted output

### Error Diagnostics (Phase 2A - High Priority)

- [x] Change `CycleError` to include cycle path: `CycleDetected(CellId, Array[CellId])`
- [x] Add `CycleError::path(self) -> Array[CellId]`
- [x] Add `CycleError::format_path(self, Runtime) -> String` for human-readable output
- [x] Update cycle detection in `internal/verify.mbt` to track path during traversal

### Per-Cell Callbacks (Phase 2B - High Priority)

- [x] Add `on_change : (() -> Unit)?` field to `CellMeta` (or type-erased callback)
- [x] Add `Signal::on_change(self, f : (T) -> Unit) -> Unit`
- [x] Add `Memo::on_change(self, f : (T) -> Unit) -> Unit`
- [x] Add `Signal::clear_on_change(self) -> Unit`
- [x] Add `Memo::clear_on_change(self) -> Unit`
- [x] Fire per-cell callbacks before `Runtime::fire_on_change()`
- [x] Test callback execution order (per-cell before global)

### Builder Pattern / Ergonomics (Phase 2C - Done)

- [x] Unified `Signal::new` with `durability? : Durability = Low` (replaces `Signal::new_with_durability`)
- [x] Added `label? : String` to `Signal::new` and `Memo::new`
- [x] Added `label? : String` and `durability?` to `create_signal` (replaces `create_signal_durable`)
- [x] Added `label? : String` to `create_memo`
- [x] Labels propagate through `CellMeta`, `CellInfo`, `format_path`
- [x] Labels surface in `derive(Debug)` output for `Signal` and `Memo`
- ~~Define `SignalBuilder[T]` struct~~ — skipped (replaced by optional params)
- ~~Add `Signal::builder(Runtime) -> SignalBuilder[T]`~~ — skipped
- ~~Add `SignalBuilder::with_value(T) -> Self`~~ — skipped
- ~~Add `SignalBuilder::with_durability(Durability) -> Self`~~ — skipped
- ~~Add `SignalBuilder::with_label(String) -> Self`~~ — skipped
- ~~Add `SignalBuilder::build() -> Signal[T]`~~ — skipped
- ~~Define `MemoBuilder[T]` struct with similar pattern~~ — skipped
- ~~Document builder pattern in API reference~~ — skipped

### Ergonomics (Phase 2C - Medium Priority)

- ~~Add `Runtime::with_on_change(self, f) -> Runtime` for method chaining~~ — skipped (replaced by `on_change?` optional param in `Runtime::new`)
- [x] Unified `create_signal` with optional `durability?` replaces `create_signal_durable`
- [ ] Explore RAII `BatchGuard` if MoonBit adds destructors

### Advanced (Phase 4)

- [x] Add subscriber (reverse) links for push-based invalidation
- [x] Add `Runtime::dependents(CellId) -> Array[CellId]` (requires subscriber links)

## Tracked Struct Support

- [x] Add `TrackedCell[T]` wrapping `Signal[T]` for field-level dependency isolation (`internal/tracked_cell.mbt`)
- [x] Add full `TrackedCell` API: `new`, `get`, `get_result`, `set`, `set_unconditional`, `id`, `durability`, `on_change`, `clear_on_change`, `is_up_to_date`, `as_signal`
- [x] Add `Trackable` trait with `cell_ids(Self) -> Array[CellId]`
- [x] Add `Readable` impl for `TrackedCell[T]`
- [x] Add `create_tracked_cell` helper function (mirrors `create_signal` pattern)
- [x] Add `gc_tracked[T : Trackable](rt, tracked)` no-op stub (call site established for Phase 4 migration)
- [x] Re-export `TrackedCell` from root facade (`incr.mbt`)
- [x] Whitebox tests in `internal/tracked_cell_wbtest.mbt`
- [x] Integration tests in `tests/tracked_struct_test.mbt`

## Internal Refactoring

- [x] Extract `Runtime::advance_revision(durability)` to consolidate duplicated revision-bump logic
- [x] Extract `Runtime::mark_input_changed(id)` helper to consolidate duplicated signal-commit logic
- [x] Replace silent `None => Ok(true)` fallback in `finish_frame_changed` with `abort(...)` assertion
- [x] Replace silent `None` skip in `commit_batch` with `abort(...)` assertion
- [x] Add runtime ownership check (`id.runtime_id != self.runtime_id`) in `Runtime::get_cell`
- [x] Simplify `Signal::get_result` to delegate to `Ok(self.get())`
- [x] Improve `Memo::get` abort message to use `CycleError::format_path`
- [x] Centralize cycle-path construction with `CycleError::from_path(path, closing_id)`
- [x] Move pipeline traits to `pipeline/pipeline_traits.mbt`; mark experimental in docs
- [x] Convert safe C-style loops to idiomatic `for .. in` syntax in `memo.mbt` and `runtime.mbt`

## Testing

- [x] Stress test: deep dependency chain (250 levels) to verify iterative verification
- [x] Wide fanout test: single signal with many downstream memos
- [x] Test `Memo` with custom `Eq` types where structural equality differs from identity
- [x] Test cycle detection across 3+ mutually recursive memos

## Package Structure

- [x] Split flat single-package library into four MoonBit sub-packages (`types/`, `internal/`, `pipeline/`, root facade)
- [x] Move pure value types (`Revision`, `Durability`, `CellId`) to `dowdiness/incr/types`
- [x] Move all engine code to `dowdiness/incr/internal`
- [x] Move experimental pipeline traits to `dowdiness/incr/pipeline`
- [x] Re-export all public types from root via `pub type` transparent aliases in `incr.mbt`
- [x] Move whitebox tests (`*_wbtest.mbt`) to `internal/` for private field access
- [x] Move unit tests (`*_test.mbt`) to `internal/` (co-located with source)
- [x] Create `tests/` package for integration tests exercising the full `@incr` public API
- [x] Zero breaking changes — downstream users see identical `@incr` API

## Documentation

- [x] Add doc comments to all public functions
- [x] Add usage examples for durability in README
- [x] Keep [design.md](design.md) in sync when core algorithms change
- [x] Organize user documentation in `docs/` folder (getting-started, concepts, api-reference, cookbook)
