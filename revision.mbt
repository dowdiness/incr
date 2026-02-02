///|
/// Monotonically increasing revision counter.
/// Bumped each time an input Signal changes.
pub(all) struct Revision {
  value : Int
} derive(Show, Eq, Compare)

///|
pub fn Revision::initial() -> Revision {
  { value: 0 }
}

///|
pub fn Revision::next(self : Revision) -> Revision {
  { value: self.value + 1 }
}

///|
/// Returns true if self is after other (self > other).
pub fn Revision::after(self : Revision, other : Revision) -> Bool {
  self.value > other.value
}

///|
/// Classifies how often an input changes.
/// High = rarely changes (e.g., config), Low = frequently changes (e.g., source text).
/// Enables skipping verification for stable subgraphs.
pub(all) enum Durability {
  Low
  Medium
  High
} derive(Show, Eq)

///|
/// Returns the index for array-based durability tracking.
pub fn Durability::index(self : Durability) -> Int {
  match self {
    Low => 0
    Medium => 1
    High => 2
  }
}

///|
/// Number of durability levels.
pub let durability_count : Int = 3
