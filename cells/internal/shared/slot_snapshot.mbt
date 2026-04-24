///|
/// Verify-side view of an accumulator slot.
///
/// The kernel (and verification paths) need to query two pieces of slot
/// state without depending on the typed `Accumulator[T]` handle or the
/// private `SlotMeta` struct (both of which live in the coordinator
/// package `cells/`). This trait erases the handle's type and narrows
/// the surface to exactly what verify/validate-style code needs.
///
/// `cells/accumulator.mbt` implements this trait for `SlotMeta`, and
/// `Runtime` caches an `Array[&SlotSnapshot]` parallel to its
/// `accumulator_slots : Array[SlotMeta]`. Kernel-resident code accesses
/// slot data through the cached array, never through `SlotMeta` directly.
pub(open) trait SlotSnapshot {
  disposed(Self) -> Bool
  push_revised_at_for(Self, CellId) -> Revision
}
