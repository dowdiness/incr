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
/// unique; duplicates degrade gracefully rather than crash: a duplicate new key
/// reuses one old node then creates the rest, and a duplicate old key reuses its
/// first occurrence and removes the rest. O(n*m) — child lists are small in
/// practice; a two-ended / LIS pass is a follow-up if a benchmark justifies it.
#cfg(target="js")
fn plan_keyed_diff(
  old_keys : Array[String],
  new_keys : Array[String],
) -> KeyedPlan {
  let consumed = Array::make(old_keys.length(), false)
  let steps = []
  for new_key in new_keys {
    let mut matched = -1
    for i in 0..<old_keys.length() {
      if !consumed[i] && old_keys[i] == new_key {
        matched = i
        break
      }
    }
    if matched >= 0 {
      consumed[matched] = true
      steps.push(Some(matched))
    } else {
      steps.push(None)
    }
  }
  let removals = []
  for i in 0..<old_keys.length() {
    if !consumed[i] {
      removals.push(i)
    }
  }
  { steps, removals }
}
