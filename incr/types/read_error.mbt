///|
/// Error type for the public read channel.
///
/// A read asks for a stored graph snapshot, so the only failures it can report
/// are *mechanism* failures — intrinsic to the read itself and unrecoverable by
/// any domain reader:
///
/// - `Cycle` — the cell transitively depends on itself.
/// - `Disposed` — the cell being read has been disposed.
///
/// Domain fallibility (a parse error, a validation failure) is *not* a read
/// error: it belongs in the value as `Result[V, E]` (see `Derived::fallible`),
/// where it is cached, change-detected, and replayed like any other value. A
/// retained compute `raise Failure` is a *defect*, not a domain error, and
/// still aborts.
///
/// Cross-runtime misuse and strict-context misuse are programmer defects and
/// abort rather than surfacing here.
///
/// See docs/design/specs/2026-05-28-honest-read-error-ownership.md.
pub enum ReadError {
  Cycle(CycleError)
  Disposed(CellId)
}

///|
/// Constructs a cycle read error. Exposed so the cells package (which detects
/// cycles) can build a `ReadError` without depending on variant-constructor
/// visibility — mirrors `CycleError::new`.
pub fn ReadError::cycle(e : CycleError) -> ReadError {
  Cycle(e)
}

///|
/// Constructs a disposed-cell read error.
pub fn ReadError::disposed(id : CellId) -> ReadError {
  Disposed(id)
}

///|
/// Renders this read error as a human-readable string. For a cycle, delegates
/// to `CycleError::format_path`; for a disposed read, names the cell.
pub fn ReadError::format_path(self : ReadError) -> String {
  match self {
    Cycle(e) => e.format_path()
    Disposed(id) => "Read on disposed cell: Cell[" + id.id.to_string() + "]"
  }
}

///|
/// Returns the cell this read error concerns: the cell at which the cycle was
/// detected, or the disposed cell that was read.
pub fn ReadError::cell(self : ReadError) -> CellId {
  match self {
    Cycle(e) => e.cell()
    Disposed(id) => id
  }
}

///|
/// Returns the cell path this read error concerns: the full dependency path
/// leading to the cycle, or the single disposed cell that was read.
pub fn ReadError::path(self : ReadError) -> Array[CellId] {
  match self {
    Cycle(e) => e.path()
    Disposed(id) => [id]
  }
}

///|
/// Returns true if this is a cycle error.
pub fn ReadError::is_cycle(self : ReadError) -> Bool {
  self is Cycle(_)
}

///|
/// Returns true if this is a disposed-cell error.
pub fn ReadError::is_disposed(self : ReadError) -> Bool {
  self is Disposed(_)
}

///|
pub impl Show for ReadError with fn output(self : ReadError, logger : &Logger) -> Unit {
  logger.write_string(self.format_path())
}
