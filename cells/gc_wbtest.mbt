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
test "dispose_cell: removes gc_root_counts entry for observed cell" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs = m.observe()
  // gc_root_counts has entry
  inspect(rt.core.gc_root_counts.get(m.id()) is None, content="false")
  // manually dispose the memo
  m.dispose()
  // gc_root_counts entry should be cleaned up
  inspect(rt.core.gc_root_counts.get(m.id()), content="None")
  // observer dispose should not abort (skips on_unobserve for dead cell)
  obs.dispose()
}

///|
test "dispose_cell: clears gc_root_counts with multiple observers" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { sig.get() })
  let obs1 = m.observe()
  let obs2 = m.observe()
  inspect(rt.core.gc_root_counts.get(m.id()), content="Some(2)")
  m.dispose()
  inspect(rt.core.gc_root_counts.get(m.id()), content="None")
  obs1.dispose()
  obs2.dispose()
}

///|
test "in_push_propagation: false by default" {
  let rt = Runtime::new()
  inspect(rt.core.in_push_propagation, content="false")
}
