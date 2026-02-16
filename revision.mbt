///|
/// A monotonically increasing revision counter representing the system's logical clock.
///
/// Revisions are bumped each time an input signal changes. Every cell tracks two
/// revision timestamps:
///
/// - `changed_at`: When this cell's value last actually changed
/// - `verified_at`: When this cell was last confirmed up-to-date
///
/// A cell is stale when `verified_at < current_revision`. A cell has changed
/// (relative to an observer) when `changed_at > observer.verified_at`.
pub(all) struct Revision {
  value : Int
} derive(Eq)

///|
/// Returns the initial revision (revision 0).
///
/// All cells start with `changed_at` and `verified_at` set to this value.
///
/// # Returns
///
/// The initial revision
fn Revision::initial() -> Revision {
  { value: 0 }
}

///|
/// Returns the next revision in sequence.
///
/// # Returns
///
/// A new revision with value incremented by 1
fn Revision::next(self : Revision) -> Revision {
  { value: self.value + 1 }
}

///|
/// Returns true if this revision is after (greater than) the other revision.
///
/// Used in the verification algorithm to determine if a cell has changed
/// since another cell's last verification.
///
/// # Parameters
///
/// - `other`: The revision to compare against
///
/// # Returns
///
/// `true` if `self > other`, `false` otherwise
fn Revision::after(self : Revision, other : Revision) -> Bool {
  self.value > other.value
}

///|
/// Classifies how often an input is expected to change.
///
/// Durability enables a powerful optimization: when only low-durability inputs
/// change, memos that depend solely on high-durability inputs skip verification
/// entirely.
///
/// # Levels
///
/// - `Low`: Frequently changing values (user input, source text)
/// - `Medium`: Moderately stable values
/// - `High`: Rarely changing values (configuration, schemas)
///
/// # Inherited Durability
///
/// Memos inherit the **minimum** durability of their dependencies. A memo
/// depending on both Low and High durability signals has Low durability.
pub(all) enum Durability {
  Low
  Medium
  High
} derive(Show, Eq)

///|
/// Returns the numeric index of this durability level.
///
/// Used internally for array-based durability tracking. `Low` has the smallest
/// index (0), `High` has the largest (2).
///
/// # Returns
///
/// - `Low` → 0
/// - `Medium` → 1
/// - `High` → 2
fn Durability::index(self : Durability) -> Int {
  match self {
    Low => 0
    Medium => 1
    High => 2
  }
}

///|
/// The number of durability levels (3: Low, Medium, High).
///
/// Used internally to size the `durability_last_changed` array in Runtime.
let durability_count : Int = 3
