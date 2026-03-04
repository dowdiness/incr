# Tracked Struct Support for incr — Implementation Specification

> **Status: ✅ Complete.** Phases 1 and 2 implemented as of 2026-02-23. Phase 3 documentation already updated. Phase 4 (GC integration) deferred to roadmap Phase 4. 162 tests passing.

> **Target audience**: Coding agents (Claude Code) and human developers.
> Self-contained: no prior context required.
> Verified against the incr codebase at commit HEAD on 2026-02-22.

---

## §1 Background and Motivation

### §1.1 What incr Is

`incr` is a MoonBit incremental computation library inspired by Rust's Salsa framework. It provides two core primitives that form a dependency graph:

**Signal[T]** — An input cell whose value is set externally. Signals are the leaves of the dependency graph. Defined in `internal/signal.mbt`, each Signal holds a typed value, a `CellId`, and `Durability` metadata. Creating a Signal registers a `CellMeta` entry (`kind=Input`) in the Runtime.

**Memo[T]** — A derived cell whose value is computed lazily from other Signals and Memos. Defined in `internal/memo.mbt`, each Memo holds a compute closure `() -> T` and a cached `value : T?`. Creating a Memo registers a `CellMeta` entry (`kind=Derived`) with a type-erased `recompute_and_check` closure that the verification algorithm can invoke without knowing `T`.

All cells are managed by a **Runtime** (`internal/runtime.mbt`) which owns an `Array[CellMeta?]` indexed by `CellId.id`, a revision counter, a tracking stack for automatic dependency recording, and durability tracking arrays. When `Signal::set()` is called, the Runtime bumps its global revision. When `Memo::get()` is called, the iterative `maybe_changed_after` algorithm in `internal/verify.mbt` walks the dependency chain to determine whether recomputation is needed.

Key features already implemented: backdating (if a Memo recomputes to the same value, `changed_at` is preserved), durability-based verification skipping, batch updates with revert detection, per-cell `on_change` callbacks, cycle detection with path diagnostics, incremental dependency diffing, and labels for debugging.

### §1.2 Current Package Structure

The library is organized into four sub-packages (see each directory's `moon.pkg` file):

```
incr/                       # Root facade — re-exports public types
├── moon.mod.json           # name: "dowdiness/incr", version: "0.3.0"
├── moon.pkg                # imports @incr_types, @internal, @pipeline
├── incr.mbt                # pub using re-exports
├── traits.mbt              # Database, Readable traits; create_signal, create_memo, batch
├── types/                  # Pure value types (zero dependencies)
│   ├── moon.pkg            # no imports
│   ├── cell_id.mbt         # CellId struct
│   └── revision.mbt        # Revision, Durability
├── internal/               # Engine code
│   ├── moon.pkg            # imports @incr_types, moonbitlang/core/hashset
│   ├── signal.mbt          # Signal[T] struct + methods
│   ├── memo.mbt            # Memo[T] struct + methods
│   ├── runtime.mbt         # Runtime struct + methods
│   ├── cell.mbt            # CellMeta (private), CellKind enum
│   ├── tracking.mbt        # ActiveQuery for dependency recording
│   ├── verify.mbt          # maybe_changed_after algorithm
│   ├── cycle.mbt           # CycleError suberror
│   └── *_test.mbt / *_wbtest.mbt
├── pipeline/               # Experimental pipeline traits (standalone)
│   ├── moon.pkg            # no imports
│   └── pipeline_traits.mbt # Sourceable, Parseable, Checkable, Executable
└── tests/                  # Integration tests
    ├── moon.pkg            # imports @incr, @pipeline (for "test")
    └── *_test.mbt
```

Import alias conventions used throughout the codebase:
- `"dowdiness/incr/types" @incr_types`
- `"dowdiness/incr/internal" @internal`
- `"dowdiness/incr/pipeline" @pipeline`
- `"dowdiness/incr" @incr` (in test packages)

The root facade in `incr.mbt` re-exports types using `pub using` syntax:

```moonbit
// incr.mbt (current state)
pub using @incr_types {
  type Revision,
  type Durability,
  type CellId,
  DURABILITY_COUNT,
}

pub using @internal {
  type Runtime,
  type CellInfo,
  type Signal,
  type Memo,
  type CycleError,
}
```

### §1.3 The Gap: Tracked Structs

In Salsa, `#[salsa::tracked]` structs are types whose individual fields are tracked as separate incremental nodes. When you create a tracked struct, each field becomes an independent piece of incremental state. Downstream queries can depend on individual fields, so changing field A does not invalidate queries that only read field B.

Currently in incr, users face a binary choice: wrap the entire struct in a single `Signal[MyStruct]`, in which case any field change invalidates everything downstream, or manually create a separate `Signal` for each field, losing the conceptual grouping of related data. Neither option is satisfactory for real-world patterns like:

- A language server where a `SourceFile` has `path`, `content`, and `revision` — queries reading `path` should not recompute when `content` changes.
- A UI framework where a `Style` has `color`, `fontSize`, `padding` — a layout computation that only reads `fontSize` should not re-run when `color` changes.
- An ECS where each entity's components are individually tracked but logically grouped.

### §1.4 Why Macros Are Not Available

MoonBit does not currently support procedural macros. Salsa relies heavily on `#[salsa::tracked]` proc macros to auto-generate field-level Signal boilerplate. We need a manual but ergonomic approach that a future macro system could automate.

### §1.5 MoonBit Type System Constraints

Relevant constraints that shape this design:

- **No higher-kinded types** — cannot abstract over `Signal[_]` as a type constructor.
- **No associated types** — traits cannot declare `type Output` members.
- **No type parameters on traits** — `trait Foo[T]` is invalid; only methods can be generic.
- **Monomorphization** — trait-constrained generics compile to specialized code (confirmed via C backend inspection). No vtable overhead.
- **Derive macros exist** — `derive(Eq, Show, Debug)` etc. are available, with field ignore syntax: `derive(Debug(ignore=[SomeType]))`. Custom derives are not supported.
- **Optional parameters** — `fn f(x~ : Int = 0, label? : String)` syntax is supported and used extensively in incr's API.
- **`pub(open) trait`** — allows external packages to provide implementations. Used for `Database` and `Readable`.
- **`pub(all) struct`** — makes all fields publicly accessible. Used for `Signal`, `Memo`, `Runtime`, `CellInfo`.

---

## §2 Design: Plan F + GC Helper

After evaluating five alternative designs (A through E), Plan F was selected for its low learning cost, maximum sync strategy freedom, and clear migration path. The design introduces three components:

### §2.1 TrackedCell[T] — Signal Wrapper for Fields

`TrackedCell[T]` is a thin wrapper around `Signal[T]` that represents one field of a tracked struct. It exists primarily for semantic clarity and to provide a future attachment point for field-level metadata (field name, parent struct reference) without changing user code.

```moonbit
/// A single tracked field within a tracked struct.
///
/// TrackedCell is a thin semantic wrapper around Signal that represents
/// a field-level incremental node. Each field of a tracked struct becomes
/// one TrackedCell. Downstream Memos that read a specific field via
/// `TrackedCell::get()` only depend on that field, not the entire struct.
///
/// The wrapper exists to:
/// 1. Distinguish struct fields from standalone Signals in the type system
/// 2. Attach field-level metadata (label defaults to field name)
/// 3. Provide a future attachment point for parent-struct references and GC roots
///
/// The Debug derive ignores the inner Signal to avoid recursive debug output,
/// matching the pattern used by Signal (which ignores Runtime and CellId)
/// and Memo (which ignores Runtime, Fn, and CellId).
pub(all) struct TrackedCell[T] {
  priv signal : Signal[T]
} derive(Debug(ignore=[Signal]))
```

The API mirrors Signal's public interface, delegating to the inner Signal. Every public method on Signal that makes sense for a field has a corresponding TrackedCell method:

```moonbit
/// Creates a new TrackedCell backed by a fresh Signal.
///
/// Parameters and behavior are identical to Signal::new().
/// The `label` parameter is especially useful here — convention is to
/// set it to "StructName.field_name" for clear introspection output.
pub fn[T] TrackedCell::new(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> TrackedCell[T] {
  { signal: Signal::new(rt, initial, durability~, label?) }
}

/// Returns the current value, recording a dependency if inside a Memo computation.
///
/// This is the primary read path. When called inside a Memo's compute function,
/// the Runtime records a dependency from that Memo to this TrackedCell's inner
/// Signal. This is what enables field-level dependency isolation: a Memo that
/// reads only `tracked_struct.field_a.get()` will NOT depend on `field_b`.
pub fn[T] TrackedCell::get(self : TrackedCell[T]) -> T {
  self.signal.get()
}

/// Returns the current value as a Result, for API consistency with Memo::get_result().
///
/// Since TrackedCell wraps a Signal (which cannot have cycles), this always
/// returns Ok(value). Provided so that generic code using Result-based APIs
/// can work uniformly with both TrackedCells and Memos.
pub fn[T] TrackedCell::get_result(self : TrackedCell[T]) -> Result[T, CycleError] {
  self.signal.get_result()
}

/// Sets the value with same-value optimization.
///
/// If new_value == current value (via Eq), this is a no-op: no revision bump,
/// no downstream recomputation. During a batch, the write is deferred.
pub fn[T : Eq] TrackedCell::set(self : TrackedCell[T], value : T) -> Unit {
  self.signal.set(value)
}

/// Sets the value unconditionally, always bumping the revision.
///
/// Use when T does not implement Eq, or when you want to force downstream
/// reverification even if the value is logically the same.
pub fn[T] TrackedCell::set_unconditional(self : TrackedCell[T], value : T) -> Unit {
  self.signal.set_unconditional(value)
}

/// Returns the CellId of the inner Signal.
///
/// This is used by the Trackable trait implementation to collect all field IDs,
/// and for introspection via Runtime::cell_info().
pub fn[T] TrackedCell::id(self : TrackedCell[T]) -> CellId {
  self.signal.id()
}

/// Returns the durability level of this field.
pub fn[T] TrackedCell::durability(self : TrackedCell[T]) -> Durability {
  self.signal.durability()
}

/// Registers a per-field change callback.
///
/// The callback fires when this specific field changes. Only one callback
/// at a time; calling again replaces the previous one.
pub fn[T] TrackedCell::on_change(self : TrackedCell[T], f : (T) -> Unit) -> Unit {
  self.signal.on_change(f)
}

/// Removes the on_change callback for this field.
pub fn[T] TrackedCell::clear_on_change(self : TrackedCell[T]) -> Unit {
  self.signal.clear_on_change()
}

/// Returns true. TrackedCells (like Signals) are always up-to-date.
pub fn[T] TrackedCell::is_up_to_date(self : TrackedCell[T]) -> Bool {
  self.signal.is_up_to_date()
}

/// Returns the underlying Signal for interop with APIs that expect Signal[T].
///
/// Use sparingly — prefer TrackedCell methods for new code. This exists to
/// enable gradual migration: existing code that expects Signal can work with
/// TrackedCell fields via as_signal().
pub fn[T] TrackedCell::as_signal(self : TrackedCell[T]) -> Signal[T] {
  self.signal
}
```

TrackedCell also implements the existing `Readable` trait, following the exact pattern used by Signal and Memo in `traits.mbt`:

```moonbit
// In traits.mbt, alongside existing Readable implementations:
pub impl[T] Readable for TrackedCell[T] with is_up_to_date(self) {
  TrackedCell::is_up_to_date(self)
}
```

### §2.2 Trackable Trait — Struct Contract

The `Trackable` trait defines what it means for a struct to be "tracked". It is the incr equivalent of Salsa's `#[salsa::tracked]` annotation, but applied manually by the user.

```moonbit
/// Contract for types that contain TrackedCell fields.
///
/// Implementing this trait declares that a type manages field-level
/// incremental state. The trait requires a single method that returns
/// all CellIds owned by the struct, enabling the runtime to perform
/// operations like GC root scanning and bulk introspection.
///
/// A future MoonBit macro system could auto-derive this trait.
///
/// The ordering of CellIds returned by cell_ids() must be stable across
/// calls (i.e., always return fields in the same order).
pub(open) trait Trackable {
  cell_ids(Self) -> Array[CellId]
}
```

Why `cell_ids()` returns `Array[CellId]`:

- The Runtime's type-erased cell storage (`Array[CellMeta?]`) operates on `CellId`, not typed values. Any runtime-level operation (GC marking, bulk validation, graph visualization) needs `CellId`s.
- Collecting all field CellIds into one array enables batch operations. For instance, `gc_tracked` (§2.3) passes these to the Runtime for root marking.
- The cost is one small array allocation per call. For GC this happens infrequently and is dominated by the actual graph walk.

### §2.3 gc_tracked Helper — GC Assistance

When tracked structs are created dynamically (e.g., one per parsed entity in a query-based compiler), old structs may become unreachable. Their TrackedCell fields — which are registered in the Runtime's cell array — must be cleaned up.

Currently, incr has no GC mechanism (see roadmap Phase 4). The `gc_tracked` helper provides a lightweight, opt-in mechanism for tracked struct cleanup without requiring the full subscriber-link infrastructure.

```moonbit
/// Marks all cells of a Trackable struct as GC roots.
///
/// Call this when a tracked struct is "alive" — referenced by the
/// current computation. Cells not marked as roots during a GC cycle
/// can be swept (reclaimed).
///
/// This function is a no-op until GC infrastructure is added to Runtime
/// (Phase 4 of the roadmap). It is provided now so that user code
/// includes the correct call sites, enabling a zero-change migration
/// when GC lands.
pub fn[T : Trackable] gc_tracked(rt : Runtime, tracked : T) -> Unit {
  // Phase 4 implementation will mark these CellIds as reachable
  // in the Runtime's GC root set.
  let _ids = tracked.cell_ids()
  ignore(rt)
  // Future: rt.mark_gc_roots(ids)
}
```

The function takes `Runtime` explicitly, following incr's existing convention where `batch`, `create_signal`, and `create_memo` are module-level functions accepting a `Database` or `Runtime` parameter. Placing GC marking on the trait itself (e.g., `Trackable::mark_gc(self, rt)`) would conflate the struct's contract with runtime operations.

---

## §3 User-Facing Example

This section shows the complete user experience for defining and using a tracked struct.

### §3.1 Defining a Tracked Struct

```moonbit
/// A source file in a language server.
/// Each field is independently tracked — changing `content` does not
/// invalidate Memos that only read `path`.
struct SourceFile {
  path : @incr.TrackedCell[String]
  content : @incr.TrackedCell[String]
  version : @incr.TrackedCell[Int]
}

/// Manual Trackable implementation.
/// A future derive macro would generate this automatically.
impl @incr.Trackable for SourceFile with cell_ids(self) {
  [self.path.id(), self.content.id(), self.version.id()]
}
```

### §3.2 Construction Helper (Factory Function Pattern)

Following incr's existing pattern of factory functions with optional parameters (see `create_signal` in `traits.mbt`):

```moonbit
fn SourceFile::new(
  rt : @incr.Runtime,
  path : String,
  content : String,
  version~ : Int = 0,
  durability? : @incr.Durability,
) -> SourceFile {
  {
    path: @incr.TrackedCell::new(rt, path, durability?, label="SourceFile.path"),
    content: @incr.TrackedCell::new(rt, content, label="SourceFile.content"),
    version: @incr.TrackedCell::new(rt, version, label="SourceFile.version"),
  }
}
```

### §3.3 Using Tracked Structs with Memos

```moonbit
fn main {
  let rt = @incr.Runtime::new()

  let file = SourceFile::new(rt, "/src/main.mbt", "fn main { 42 }")

  // This Memo only depends on `content`, not `path` or `version`.
  let word_count = @incr.Memo::new(rt, () => {
    file.content.get().split(" ").fold(init=0, (acc, _s) => acc + 1)
  }, label="word_count")

  // This Memo only depends on `path`.
  let is_test = @incr.Memo::new(rt, () => {
    file.path.get().ends_with("_test.mbt")
  }, label="is_test")

  // Initial evaluation
  inspect(word_count.get(), content="4")
  inspect(is_test.get(), content="false")

  // Change `version` — neither Memo recomputes (neither depends on version)
  file.version.set(1)
  inspect(word_count.get(), content="4")   // cache hit
  inspect(is_test.get(), content="false")  // cache hit

  // Change `content` — only word_count recomputes
  file.content.set("fn main { let x = 42\n  x }")
  inspect(word_count.get(), content="8")   // recomputed
  inspect(is_test.get(), content="false")  // cache hit (path unchanged)

  // GC marking (no-op until Phase 4, but establishes call site)
  @incr.gc_tracked(rt, file)
}
```

### §3.4 Using with Database Trait

The tracked struct pattern composes cleanly with the existing `Database` trait:

```moonbit
struct MyDb {
  rt : @incr.Runtime
  files : Array[SourceFile]
}

impl @incr.Database for MyDb with runtime(self) {
  self.rt
}

fn MyDb::add_file(self : MyDb, path : String, content : String) -> SourceFile {
  let file = SourceFile::new(self.rt, path, content)
  self.files.push(file)
  file
}
```

### §3.5 Batch Updates on Tracked Structs

```moonbit
fn update_file(rt : @incr.Runtime, file : SourceFile, content : String) -> Unit {
  rt.batch(() => {
    file.content.set(content)
    file.version.set(file.version.get() + 1)
  })
  // Single revision bump for both field changes
}
```

---

## §4 File Placement and Package Structure

All new code integrates into the existing four-package structure. No new packages are created, and no `moon.pkg` files need modification (TrackedCell lives in `internal/`, which already imports `@incr_types` and `moonbitlang/core/hashset`).

### §4.1 New Files

```
internal/
├── tracked_cell.mbt          # NEW — TrackedCell struct + all methods
└── tracked_cell_wbtest.mbt   # NEW — whitebox tests (can access priv fields)

tests/
└── tracked_struct_test.mbt   # NEW — integration tests via public API
```

### §4.2 Modified Files

**`incr.mbt`** — Add TrackedCell to the `@internal` re-export block:

```moonbit
pub using @internal {
  type Runtime,
  type CellInfo,
  type Signal,
  type Memo,
  type CycleError,
  type TrackedCell,     // NEW
}
```

**`traits.mbt`** — Add after existing `Readable` implementations and helper functions:

```moonbit
// --- Tracked Struct Support ---

/// Readable implementation for TrackedCell, matching the pattern of
/// Signal and Memo implementations above.
pub impl[T] Readable for TrackedCell[T] with is_up_to_date(self) {
  TrackedCell::is_up_to_date(self)
}

/// Contract for types that contain TrackedCell fields.
pub(open) trait Trackable {
  cell_ids(Self) -> Array[CellId]
}

/// Creates a new TrackedCell using the database's runtime.
///
/// Follows the same pattern as create_signal and create_memo.
pub fn[Db : Database, T] create_tracked_cell(
  db : Db,
  value : T,
  durability? : Durability = Low,
  label? : String,
) -> TrackedCell[T] {
  TrackedCell::new(db.runtime(), value, durability~, label?)
}

/// Marks all cells of a Trackable struct as GC roots (no-op until Phase 4).
pub fn[T : Trackable] gc_tracked(rt : Runtime, tracked : T) -> Unit {
  let _ids = tracked.cell_ids()
  ignore(rt)
}
```

### §4.3 Unchanged Files

These files require **zero** modifications:
- `internal/signal.mbt` — TrackedCell wraps Signal, does not modify it.
- `internal/memo.mbt` — Memo's verification works transparently with TrackedCell's inner Signal.
- `internal/runtime.mbt` — Runtime sees only Signals. TrackedCell is invisible at the Runtime level.
- `internal/cell.mbt` — CellMeta, CellKind unchanged. No third cell kind needed.
- `internal/verify.mbt` — Verification algorithm unchanged.
- `internal/tracking.mbt` — ActiveQuery unchanged.
- `internal/cycle.mbt` — CycleError unchanged.
- `types/` — Revision, Durability, CellId unchanged.
- `pipeline/` — Pipeline traits unchanged.
- All `moon.pkg` files — No new dependencies.

This zero-change property for core engine files is a key advantage of Plan F.

---

## §5 Implementation Phases

### Phase 1: TrackedCell (Core)

**Goal**: Ship TrackedCell as a standalone, fully tested wrapper.

**Files to create**:
- `internal/tracked_cell.mbt` — struct definition and all methods listed in §2.1
- `internal/tracked_cell_wbtest.mbt` — whitebox tests (can access `priv` fields)

**Files to modify**:
- `incr.mbt` — add `type TrackedCell` to the `@internal` re-export block

**Acceptance criteria**:

1. `TrackedCell::new(rt, value)` creates a TrackedCell with inner Signal.
2. `TrackedCell::get()` records dependency (verified: create a Memo that reads a TrackedCell, change the TrackedCell, Memo recomputes).
3. `TrackedCell::set()` same-value optimization works (set to current value → no revision bump).
4. `TrackedCell::set_unconditional()` always bumps revision.
5. Optional params (`durability?`, `label?`) propagate to inner Signal.
6. `TrackedCell::on_change()` and `clear_on_change()` work correctly.
7. `TrackedCell::get_result()` returns `Ok(value)`.
8. `TrackedCell::as_signal()` returns the inner Signal for interop.
9. `derive(Debug(ignore=[Signal]))` compiles and produces output.
10. All existing tests still pass (zero regression).

**Test plan for Phase 1**:

```moonbit
// internal/tracked_cell_wbtest.mbt — whitebox tests accessing priv fields

test "TrackedCell wraps Signal" {
  let rt = Runtime::new()
  let cell = TrackedCell::new(rt, 42, label="test_field")
  // Access the priv signal field directly (whitebox)
  inspect(cell.signal.get(), content="42")
}

test "TrackedCell label propagates to CellMeta" {
  let rt = Runtime::new()
  let cell = TrackedCell::new(rt, 0, label="my_field")
  let info = rt.cell_info(cell.id())
  inspect(info.unwrap().label, content="Some(\"my_field\")")
}

test "TrackedCell durability propagates" {
  let rt = Runtime::new()
  let cell = TrackedCell::new(rt, "config", durability=High)
  inspect(cell.durability(), content="High")
}
```

```moonbit
// tests/tracked_struct_test.mbt — integration tests via public API

test "TrackedCell dependency tracking" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 10)
  let doubled = @incr.Memo::new(rt, () => cell.get() * 2)
  inspect(doubled.get(), content="20")
  cell.set(15)
  inspect(doubled.get(), content="30")
}

test "TrackedCell same-value optimization" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 5)
  let mut compute_count = 0
  let memo = @incr.Memo::new(rt, () => {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = memo.get()      // compute_count = 1
  cell.set(5)             // same value — no revision bump
  let _ = memo.get()      // should NOT recompute
  inspect(compute_count, content="1")
}

test "TrackedCell on_change callback" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut observed = 0
  cell.on_change(v => observed = v)
  cell.set(42)
  inspect(observed, content="42")
}

test "TrackedCell get_result returns Ok" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 99)
  match cell.get_result() {
    Ok(v) => inspect(v, content="99")
    Err(_) => abort("unexpected Err")
  }
}

test "TrackedCell batch integration" {
  let rt = @incr.Runtime::new()
  let a = @incr.TrackedCell::new(rt, 1)
  let b = @incr.TrackedCell::new(rt, 2)
  let sum = @incr.Memo::new(rt, () => a.get() + b.get())
  inspect(sum.get(), content="3")
  rt.batch(() => {
    a.set(10)
    b.set(20)
  })
  inspect(sum.get(), content="30")
}

test "TrackedCell batch revert detection" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut compute_count = 0
  let memo = @incr.Memo::new(rt, () => {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = memo.get()      // compute_count = 1
  rt.batch(() => {
    cell.set(99)
    cell.set(0)           // revert to original
  })
  let _ = memo.get()      // should NOT recompute (net change = 0)
  inspect(compute_count, content="1")
}

test "TrackedCell as_signal interop" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 7)
  let sig = cell.as_signal()
  // A Memo using the raw Signal still tracks the same dependency
  let memo = @incr.Memo::new(rt, () => sig.get() + 1)
  inspect(memo.get(), content="8")
  cell.set(10)
  inspect(memo.get(), content="11")
}

test "TrackedCell Readable trait" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  // check_up_to_date is defined at the top level of traits_test.mbt (same package)
  inspect(check_up_to_date(cell), content="true")
}
```

### Phase 2: Trackable Trait + gc_tracked Stub

**Goal**: Ship the trait contract and GC stub so user code can adopt tracked patterns immediately.

**Files to modify**:
- `traits.mbt` — add `Trackable` trait, `Readable` impl for TrackedCell, `create_tracked_cell` helper, `gc_tracked` stub

**Acceptance criteria**:
1. `Trackable` trait compiles and can be implemented by user structs.
2. `cell_ids()` returns correct CellIds for a struct with N TrackedCell fields.
3. `create_tracked_cell(db, value)` works with `Database`-implementing types.
4. `gc_tracked(rt, struct)` compiles and runs as no-op.
5. No changes to Runtime internals.
6. All existing tests still pass.

**Test plan for Phase 2**:

```moonbit
// tests/tracked_struct_test.mbt — continued

/// Test fixture: a tracked struct with three fields
struct TestTracked {
  name : @incr.TrackedCell[String]
  value : @incr.TrackedCell[Int]
  flag : @incr.TrackedCell[Bool]
}

impl @incr.Trackable for TestTracked with cell_ids(self) {
  [self.name.id(), self.value.id(), self.flag.id()]
}

fn TestTracked::new(rt : @incr.Runtime) -> TestTracked {
  {
    name: @incr.TrackedCell::new(rt, "default", label="name"),
    value: @incr.TrackedCell::new(rt, 0, label="value"),
    flag: @incr.TrackedCell::new(rt, false, label="flag"),
  }
}

test "Trackable cell_ids returns all field IDs" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  let ids = t.cell_ids()
  inspect(ids.length(), content="3")
  // IDs are distinct
  inspect(ids[0] == ids[1], content="false")
  inspect(ids[1] == ids[2], content="false")
}

test "Trackable cell_ids ordering is stable" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  let ids1 = t.cell_ids()
  let ids2 = t.cell_ids()
  inspect(ids1[0] == ids2[0], content="true")
  inspect(ids1[1] == ids2[1], content="true")
  inspect(ids1[2] == ids2[2], content="true")
}

test "field-level dependency isolation" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  let mut name_reads = 0
  let mut value_reads = 0
  let name_len = @incr.Memo::new(rt, () => {
    name_reads = name_reads + 1
    t.name.get().length()
  })
  let value_doubled = @incr.Memo::new(rt, () => {
    value_reads = value_reads + 1
    t.value.get() * 2
  })

  // Initial computation
  let _ = name_len.get()       // name_reads = 1
  let _ = value_doubled.get()  // value_reads = 1

  // Change only `value` — name_len should NOT recompute
  t.value.set(10)
  let _ = name_len.get()       // name_reads still 1
  let _ = value_doubled.get()  // value_reads = 2
  inspect(name_reads, content="1")
  inspect(value_reads, content="2")

  // Change only `name` — value_doubled should NOT recompute
  t.name.set("hello")
  let _ = name_len.get()       // name_reads = 2
  let _ = value_doubled.get()  // value_reads still 2
  inspect(name_reads, content="2")
  inspect(value_reads, content="2")
}

test "gc_tracked compiles and runs (no-op)" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  @incr.gc_tracked(rt, t)
  // No crash, no effect — just verifying call compiles
}

test "create_tracked_cell with Database" {
  // TestDb is defined at the top level of traits_test.mbt (same package)
  let db = TestDb::new()
  let cell = @incr.create_tracked_cell(db, 42, label="db_cell")
  inspect(cell.get(), content="42")
}

test "TrackedCell introspection via Runtime::cell_info" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  let ids = t.cell_ids()
  for i = 0; i < ids.length(); i = i + 1 {
    let info = rt.cell_info(ids[i])
    inspect(info is None, content="false")
    // All fields should have labels
    inspect(info.unwrap().label is None, content="false")
  }
}
```

### Phase 3: Documentation and Cookbook

**Goal**: Add user-facing documentation and a cookbook recipe.

**Files to create/modify**:
- `docs/api-reference.md` — add TrackedCell, Trackable, gc_tracked sections
- `docs/cookbook.md` — add "Tracked Struct" recipe
- `docs/concepts.md` — add "Field-Level Tracking" concept section
- `README.md` — mention tracked structs in feature list

**Cookbook recipe outline**:
1. When to use TrackedCell vs plain Signal (decision criteria)
2. Defining a tracked struct step-by-step
3. The Trackable trait implementation pattern
4. Composing tracked structs with Memos
5. Batch updates across multiple fields
6. Migration path: converting a `Signal[MyStruct]` to field-level tracking

### Phase 4: GC Integration (Future — Depends on Roadmap Phase 4)

**Goal**: Make `gc_tracked` functional by adding GC root tracking to Runtime.

**Prerequisite**: Subscriber (reverse) links from roadmap Phase 4.

**Sketch of Runtime modifications** (in `internal/runtime.mbt`):

```moonbit
// New fields added to Runtime struct:
priv mut gc_roots : @hashset.HashSet[CellId]
priv mut gc_enabled : Bool

// New public API:
pub fn Runtime::gc_collect(self : Runtime) -> Int {
  // 1. Swap gc_roots to empty set (becomes the mark set)
  // 2. Walk all marked roots and their transitive dependents
  //    (requires subscriber links for reachability)
  // 3. Remove unreachable CellMeta entries from self.cells (set to None)
  // 4. Return count of collected cells
}
```

The `gc_tracked` function body changes from no-op to:

```moonbit
pub fn[T : Trackable] gc_tracked(rt : Runtime, tracked : T) -> Unit {
  if rt.gc_enabled {
    for id in tracked.cell_ids() {
      rt.gc_roots.add(id)
    }
  }
}
```

This phase is explicitly **out of scope** for the current implementation. The stub exists to establish call sites in user code today, allowing zero-change migration when GC lands.

---

## §6 Design Rationale

### §6.1 Why TrackedCell Instead of a New Cell Type

TrackedCell wraps Signal rather than introducing a third cell kind in CellMeta. This means:

- **Zero changes** to the verification algorithm (`maybe_changed_after` in `verify.mbt`).
- **Zero changes** to CellMeta, CellKind, Runtime internals, or the tracking stack.
- TrackedCell fields work with **all existing features** (batch, durability, on_change, backdating, introspection, dep diffing) automatically.
- The type system distinguishes "struct field" from "standalone input" at the user API level while the runtime sees only Signals.

### §6.2 Why a Trait Instead of a Base Struct

Alternative: require tracked structs to embed a base struct like `struct TrackedBase { ids: Array[CellId] }`. This was rejected because:

- MoonBit structs do not support inheritance. A base struct would be a field, creating awkward `self.base.ids` access patterns.
- A trait is more flexible — it works with any struct shape and imposes no structural requirement.
- The trait approach aligns with incr's existing patterns: `Database` and `Readable` are both `pub(open) trait`.

### §6.3 Why gc_tracked Is a Free Function

Following incr's convention where `batch`, `create_signal`, and `create_memo` are module-level functions that accept a `Database` or `Runtime` parameter. Placing GC marking on the trait itself would conflate the struct's contract with runtime operations.

### §6.4 Why TrackedCell has derive(Debug(ignore=[Signal]))

Signal itself uses `derive(Debug(ignore=[Runtime, CellId]))` and Memo uses `derive(Debug(ignore=[Runtime, Fn, CellId]))`. TrackedCell wraps a Signal, so ignoring Signal in the Debug derive avoids recursive or redundant debug output. When users debug-print a TrackedCell, they get a clean wrapper representation rather than the full Signal internals.

### §6.5 Migration Path

When MoonBit adds procedural macro support, a `#[tracked]` derive macro could auto-generate:
- TrackedCell fields from regular struct field declarations
- The `Trackable` implementation
- A `::new()` factory function with appropriate labels
- `gc_tracked` call sites in derived computations

User code written against TrackedCell today will require no changes — the macro would simply automate what users currently write manually.

---

## §7 Sync Strategy Freedom

Plan F deliberately does not prescribe how user code synchronizes field values from external sources. Users are free to choose any strategy:

**Strategy A — Direct set**: Call `field.set(value)` directly. Simplest approach.

```moonbit
fn update_from_lsp(file : SourceFile, change : TextChange) -> Unit {
  file.content.set(apply_change(file.content.get(), change))
  file.version.set(file.version.get() + 1)
}
```

**Strategy B — Batch set**: Wrap multiple field updates in a batch for atomicity.

```moonbit
fn update_from_lsp(rt : @incr.Runtime, file : SourceFile, change : TextChange) -> Unit {
  rt.batch(() => {
    file.content.set(apply_change(file.content.get(), change))
    file.version.set(file.version.get() + 1)
  })
}
```

**Strategy C — Whole-struct diff**: Compare an external DTO against current field values and set only changed fields. This naturally leverages same-value optimization.

```moonbit
fn sync_from_dto(file : SourceFile, dto : FileDTO) -> Unit {
  file.path.set(dto.path)         // no-op if unchanged
  file.content.set(dto.content)   // no-op if unchanged
  file.version.set(dto.version)   // no-op if unchanged
}
```

**Strategy D — CRDT merge**: For collaborative editing, merge CRDT state into individual fields.

All strategies compose cleanly because TrackedCell delegates to Signal, which handles same-value optimization and batch semantics automatically.

---

## §8 Relationship to Existing Roadmap

This feature fits between the completed work (Phases 1–3B, all ✓) and the planned advanced features (Phase 4). Specifically:

- **Depends on**: Nothing new. TrackedCell wraps Signal, which is fully implemented.
- **Enables**: Dynamic Memo creation per tracked struct, GC of unreachable tracked structs (roadmap Phase 4), and ECS integration where each entity's components are TrackedCells.
- **Does not require**: Subscriber links, push-pull hybrid, or interning. These are orthogonal future improvements that will benefit TrackedCell users automatically when implemented.

---

## §9 Checklist Summary

| Task | Phase | Files | Blocking? |
|---|---|---|---|
| TrackedCell struct + all methods | 1 | `internal/tracked_cell.mbt` | Yes |
| TrackedCell whitebox tests | 1 | `internal/tracked_cell_wbtest.mbt` | Yes |
| Re-export TrackedCell in facade | 1 | `incr.mbt` | Yes |
| Readable impl for TrackedCell | 2 | `traits.mbt` | No |
| Trackable trait | 2 | `traits.mbt` | No |
| create_tracked_cell helper | 2 | `traits.mbt` | No |
| gc_tracked stub | 2 | `traits.mbt` | No |
| Integration tests (all phases) | 1–2 | `tests/tracked_struct_test.mbt` | No |
| Documentation updates | 3 | `docs/*.md`, `README.md` | No |
| Runtime GC root tracking | 4 (future) | `internal/runtime.mbt` | No |
