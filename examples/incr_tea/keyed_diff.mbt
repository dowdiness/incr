///|
/// Pure, DOM-free keyed-child reconciliation planner for the renderer (#211).
///
/// Keyed children carry a stable business key (not an array index), following
/// Rabbita's keyed-children idiom. The planner matches old children to new
/// children by key so insert/remove/reorder reuse the existing DOM node (and its
/// listeners) for a key instead of re-patching by position. It is kept separate
/// from the DOM applier so the matching logic is unit-testable in Node, where no
/// `document` exists.

///|
/// Plan produced by `plan_keyed_diff`. `steps` has one entry per new child, in
/// new order: `Some(old_index)` reuses the old child at that index (its DOM node
/// rides along), `None` creates a fresh node. `removals` lists the old indices
/// whose key vanished and must be detached.
///
/// The step encoding is plain `Int?` so the planner needs no derived traits: both
/// `Array[Int?]` and `Array[Int]` are inspectable through core's `Debug`, which
/// keeps the unit tests readable without a test-only derive on a source type.
#cfg(target="js")
priv struct KeyedPlan {
  steps : Array[Int?]
  removals : Array[Int]
}

///|
/// Matches `old_keys` to `new_keys` by key, first-available-wins.
///
/// For each new key in order, the first not-yet-consumed old child with the same
/// key is reused (`Some(old_index)`); otherwise the new child is created
/// (`None`). Old children never reused are removals. Keys are expected to be
/// unique; duplicates degrade gracefully rather than crash. Tiny inputs use the
/// original scan because map setup dominates there; otherwise duplicate-free old
/// keys match through an O(1) index. If old keys are duplicated, the planner
/// falls back to the first-available scan so degradation semantics stay
/// unchanged. The duplicate-free large-list path is O(n + m).
#cfg(target="js")
fn plan_keyed_diff(
  old_keys : Array[String],
  new_keys : Array[String],
) -> KeyedPlan {
  // Empirical guard from the #241 benches: the scan wins at N=16, while the
  // map path pays for itself clearly by N=256 on reverse/prepend/unchanged.
  let small_scan_limit = 32
  guard old_keys.length() > small_scan_limit ||
    new_keys.length() > small_scan_limit else {
    return plan_keyed_diff_by_first_available_scan(old_keys, new_keys)
  }
  let old_index_by_key : @hashmap.HashMap[String, Int] = @hashmap.HashMap(
    [
      for old_index, old_key in old_keys => (old_key, old_index)
    ],
  )
  guard old_index_by_key.length() == old_keys.length() else {
    return plan_keyed_diff_by_first_available_scan(old_keys, new_keys)
  }
  let consumed = Array::make(old_keys.length(), false)
  let steps = new_keys.map(new_key => {
    let matched : Int? = match old_index_by_key.get(new_key) {
      Some(old_index) if !consumed[old_index] => Some(old_index)
      _ => None
    }
    match matched {
      Some(old_index) => {
        consumed[old_index] = true
        Some(old_index)
      }
      None => None
    }
  })
  let removals = [
    for old_index in 0..<old_keys.length() if !consumed[old_index] => old_index
  ]
  { steps, removals }
}

///|
/// Original first-available scan, retained for tiny lists and duplicate-old-key
/// degradation where preserving exact legacy behavior matters more than speed.
#cfg(target="js")
fn plan_keyed_diff_by_first_available_scan(
  old_keys : Array[String],
  new_keys : Array[String],
) -> KeyedPlan {
  let consumed = Array::make(old_keys.length(), false)
  let steps = new_keys.map(new_key => {
    let matched : Int? = for old_index, old_key in old_keys {
      if !consumed[old_index] && old_key == new_key {
        break Some(old_index)
      }
    } nobreak {
      None
    }
    match matched {
      Some(old_index) => {
        consumed[old_index] = true
        Some(old_index)
      }
      None => None
    }
  })
  let removals = [
    for old_index in 0..<old_keys.length() if !consumed[old_index] => old_index
  ]
  { steps, removals }
}
