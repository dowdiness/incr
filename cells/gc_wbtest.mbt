///|
test "add_gc_root: inserts new entry with count 1" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  rt.add_gc_root(sig.id())
  inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(1)")
}

///|
test "add_gc_root: increments existing entry" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  rt.add_gc_root(sig.id())
  rt.add_gc_root(sig.id())
  inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(2)")
}

///|
test "remove_gc_root: decrements and returns remaining" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  rt.add_gc_root(sig.id())
  rt.add_gc_root(sig.id())
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="1")
  inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(1)")
}

///|
test "remove_gc_root: removes entry at zero" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  rt.add_gc_root(sig.id())
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="0")
  inspect(rt.core.gc_root_counts.get(sig.id()), content="None")
}

///|
test "remove_gc_root: returns 0 for unknown cell" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="0")
}

///|
test "cell_id_at: reconstructs CellId from index" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let reconstructed = rt.cell_id_at(sig.id().id)
  inspect(reconstructed == sig.id(), content="true")
}

///|
test "in_push_propagation: false by default" {
  let rt = Runtime::new()
  inspect(rt.core.in_push_propagation, content="false")
}
