///|
/// Diffs old_deps against new_deps and updates subscriber links.
///
/// Removes `cell_id` from subscribers of dropped deps, adds `cell_id`
/// to subscribers of new deps. Accepts an optional pre-built `new_seen`
/// set (from `pop_tracking`) to avoid rebuilding it.
///
/// Returns true if dependencies actually changed.
fn Runtime::diff_and_update_subscribers(
  self : Runtime,
  cell_id : CellId,
  old_deps : Array[CellId],
  new_deps : Array[CellId],
  new_seen? : @hashset.HashSet[CellId],
) -> Bool {
  if old_deps.is_empty() && new_deps.is_empty() {
    return false
  }
  let new_seen = match new_seen {
    Some(s) => s
    None => {
      let s : @hashset.HashSet[CellId] = @hashset.new()
      for dep in new_deps {
        s.add(dep)
      }
      s
    }
  }
  let mut changed = new_deps.length() != old_deps.length()
  for dep in old_deps {
    if !new_seen.contains(dep) {
      changed = true
      break
    }
  }
  if changed {
    let old_seen : @hashset.HashSet[CellId] = @hashset.new()
    for dep in old_deps {
      old_seen.add(dep)
      if !new_seen.contains(dep) {
        self.remove_subscriber(dep, cell_id)
      }
    }
    for dep in new_deps {
      if !old_seen.contains(dep) {
        self.add_subscriber(dep, cell_id)
      }
    }
  }
  changed
}
