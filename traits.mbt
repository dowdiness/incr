///|
/// An incremental database providing access to its runtime.
///
/// This is the core trait that all incremental systems must implement.
/// It connects user-defined database types to the incr runtime,
/// enabling generic helper functions like `create_signal` and `create_memo`.
///
/// This trait corresponds to Salsa's `#[salsa::db]` trait, but without
/// macro magic — users implement it explicitly.
///
/// # Example
///
/// ```moonbit
/// struct MyDb {
///   rt : @incr.Runtime
/// }
///
/// impl @incr.IncrDb for MyDb with runtime(self) {
///   self.rt
/// }
/// ```
pub(open) trait IncrDb {
  runtime(Self) -> Runtime
}

///|
/// A readable incremental node (Signal or Memo).
///
/// This trait provides a common interface for checking whether
/// a node's cached value is current with the latest revision.
/// Both Signal and Memo implement this trait.
///
/// Use the trait bound in generic functions to write code that
/// works with any readable node:
///
/// ```moonbit
/// fn[R : Readable] check(node : R) -> Bool {
///   node.is_up_to_date()
/// }
/// ```
pub(open) trait Readable {
  /// Returns true if the node's value is verified at the current revision.
  is_up_to_date(Self) -> Bool
}

///|
/// Returns true. Signals are always up-to-date since they are input cells
/// with directly-set values.
pub fn[T] Signal::is_up_to_date(self : Signal[T]) -> Bool {
  ignore(self)
  true
}

///|
/// Signals are always up-to-date since they are input cells
/// with directly-set values.
pub impl[T] Readable for Signal[T] with is_up_to_date(self) {
  self.is_up_to_date()
}

///|
/// Returns true if the memo has a cached value and its verified_at matches
/// the runtime's current revision. Returns false if the memo has never been
/// computed (value is None), even at the initial revision.
pub fn[T] Memo::is_up_to_date(self : Memo[T]) -> Bool {
  match self.value {
    None => false
    Some(_) => {
      let cell = self.rt.get_cell(self.cell_id)
      cell.verified_at == self.rt.current_revision
    }
  }
}

///|
/// A memo is up-to-date when its verified_at matches the
/// runtime's current revision.
pub impl[T] Readable for Memo[T] with is_up_to_date(self) {
  self.is_up_to_date()
}

///|
/// Creates a new signal with Low durability using the database's runtime.
///
/// This is a generic helper that works with any type implementing `IncrDb`.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `value`: The initial value of the signal
///
/// # Returns
///
/// A new signal associated with the database's runtime
pub fn[Db : IncrDb, T] create_signal(db : Db, value : T) -> Signal[T] {
  Signal::new(db.runtime(), value)
}

///|
/// Creates a new signal with explicit durability using the database's runtime.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `value`: The initial value of the signal
/// - `durability`: How often this signal is expected to change
///
/// # Returns
///
/// A new signal associated with the database's runtime
pub fn[Db : IncrDb, T] create_signal_durable(
  db : Db,
  value : T,
  durability : Durability,
) -> Signal[T] {
  Signal::new_with_durability(db.runtime(), value, durability)
}

///|
/// Creates a new memo using the database's runtime.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `f`: The compute function for the memo
///
/// # Returns
///
/// A new memo associated with the database's runtime
pub fn[Db : IncrDb, T : Eq] create_memo(db : Db, f : () -> T) -> Memo[T] {
  Memo::new(db.runtime(), f)
}

///|
/// Executes a batch of signal updates using the database's runtime.
///
/// All signal updates inside the closure are deferred until the batch ends,
/// resulting in a single revision bump.
///
/// # Parameters
///
/// - `db`: Any type implementing `IncrDb`
/// - `f`: The closure containing signal updates
pub fn[Db : IncrDb] batch(db : Db, f : () -> Unit) -> Unit {
  db.runtime().batch(f)
}

// === Pipeline Traits ===
// These traits define the stages of a compilation/processing pipeline.
// Users implement them for their own database types to get access to
// generic composition functions like `all_diagnostics` and `compile_and_run`.

///|
/// A system that has source text input.
///
/// Implement this trait to provide get/set access to source text
/// backed by an incremental Signal.
pub(open) trait Sourceable {
  set_source_text(Self, String) -> Unit
  source_text(Self) -> String
}

///|
/// A system that can parse and report parse errors.
pub(open) trait Parseable {
  parse_errors(Self) -> Array[String]
}

///|
/// A system that can check (type-check, lint, etc.) and report errors.
pub(open) trait Checkable {
  check_errors(Self) -> Array[String]
}

///|
/// A system that can execute/evaluate and produce output.
pub(open) trait Executable {
  run(Self) -> Array[String]
}

// === Composition Functions ===
// These generic functions combine multiple traits to provide
// higher-level operations. They replace default trait methods
// (which can't express multi-trait constraints in MoonBit).

///|
/// Returns all diagnostics (parse errors + check errors) from a system
/// that implements both Parseable and Checkable.
///
/// # Parameters
///
/// - `db`: Any type implementing both `Parseable` and `Checkable`
///
/// # Returns
///
/// Combined array of all parse and check errors
pub fn[D : Parseable + Checkable] all_diagnostics(db : D) -> Array[String] {
  let parse_errs = db.parse_errors()
  let check_errs = db.check_errors()
  let result : Array[String] = []
  for i = 0; i < parse_errs.length(); i = i + 1 {
    result.push(parse_errs[i])
  }
  for i = 0; i < check_errs.length(); i = i + 1 {
    result.push(check_errs[i])
  }
  result
}

///|
/// Compiles and runs a system that implements Parseable, Checkable,
/// and Executable.
///
/// Returns `Ok(output)` if there are no diagnostics, or
/// `Err(diagnostics)` if there are parse or check errors.
///
/// # Parameters
///
/// - `db`: Any type implementing `Parseable`, `Checkable`, and `Executable`
///
/// # Returns
///
/// `Ok(output)` on success, `Err(errors)` if diagnostics exist
pub fn[D : Parseable + Checkable + Executable] compile_and_run(
  db : D,
) -> Result[Array[String], Array[String]] {
  let diags = all_diagnostics(db)
  if diags.length() > 0 {
    Err(diags)
  } else {
    Ok(db.run())
  }
}
