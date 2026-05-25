///|
test "add_gc_root: inserts new entry with count 1 and returns 0" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 42)
  let prev = rt.add_gc_root(sig.id())
  inspect(prev, content="0")
  debug_inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(1)")
}

///|
test "add_gc_root: increments existing entry and returns previous count" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 42)
  let prev1 = rt.add_gc_root(sig.id())
  let prev2 = rt.add_gc_root(sig.id())
  inspect(prev1, content="0")
  inspect(prev2, content="1")
  debug_inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(2)")
}

///|
test "remove_gc_root: decrements and returns remaining" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 42)
  ignore(rt.add_gc_root(sig.id()))
  ignore(rt.add_gc_root(sig.id()))
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="1")
  debug_inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(1)")
}

///|
test "remove_gc_root: removes entry at zero" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 42)
  ignore(rt.add_gc_root(sig.id()))
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="0")
  debug_inspect(rt.core.gc_root_counts.get(sig.id()), content="None")
}

///|
test "remove_gc_root: returns 0 for unknown cell" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 42)
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="0")
}

///|
test "cell_id_at: reconstructs CellId from index" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 42)
  let reconstructed = @kernel.cell_id_at(rt.core, sig.id().id)
  inspect(reconstructed == sig.id(), content="true")
}

///|
test "dispose_cell: removes gc_root_counts entry for observed cell" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 1)
  let m = Memo::Memo(rt, fn() { sig.get() })
  let obs = m.observe()
  // gc_root_counts has entry
  inspect(rt.core.gc_root_counts.get(m.id()) is None, content="false")
  // manually dispose the memo
  m.dispose()
  // gc_root_counts entry should be cleaned up
  debug_inspect(rt.core.gc_root_counts.get(m.id()), content="None")
  // observer dispose should not abort (skips on_unobserve for dead cell)
  obs.dispose()
}

///|
test "dispose_cell: clears gc_root_counts with multiple observers" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 1)
  let m = Memo::Memo(rt, fn() { sig.get() })
  let obs1 = m.observe()
  let obs2 = m.observe()
  debug_inspect(rt.core.gc_root_counts.get(m.id()), content="Some(2)")
  m.dispose()
  debug_inspect(rt.core.gc_root_counts.get(m.id()), content="None")
  obs1.dispose()
  obs2.dispose()
}

///|
test "phase: Idle by default" {
  let rt = Runtime::Runtime()
  inspect(rt.core.phase, content="Idle")
}

// =============================================================================
// collect_gc_roots / mark_reachable / gc_sweep — kernel algorithm unit tests
//
// The high-level gc() path is covered by gc_test.mbt (integration) and the
// add/remove_gc_root tests above. These tests target the three kernel
// sub-functions directly: what gets collected as a root, which cells are
// reachable from a root set, and which Interior cells get passed to dispose_fn.
// =============================================================================

///|
test "collect_gc_roots: live observer puts memo in roots via gc_root_counts" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 1)
  let m = Memo::Memo(rt, fn() { sig.get() })
  let obs = m.observe()
  ignore(obs.get())
  let roots = @kernel.collect_gc_roots(rt.core)
  let contains_memo = for id in roots {
    if id == m.id() { break true }
  } nobreak {
    false
  }
  inspect(contains_memo, content="true")
  obs.dispose()
}

///|
test "collect_gc_roots: disposed observer is absent from roots" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 1)
  let m = Memo::Memo(rt, fn() { sig.get() })
  ignore(read_memo_for_test(m)) // observe-read-dispose cycle
  let roots = @kernel.collect_gc_roots(rt.core)
  let contains_memo = for id in roots {
    if id == m.id() { break true }
  } nobreak {
    false
  }
  inspect(contains_memo, content="false")
}

///|
test "mark_reachable: signal is reachable through dependent memo" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 1)
  let m = Memo::Memo(rt, fn() { sig.get() })
  ignore(read_memo_for_test(m)) // compute to establish m→sig dependency
  let reachable = @kernel.mark_reachable(rt.core, [m.id()])
  inspect(reachable.contains(m.id()), content="true")
  inspect(reachable.contains(sig.id()), content="true")
}

///|
test "mark_reachable: traversal stops at a disposed dependency" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 1)
  let m = Memo::Memo(rt, fn() { sig.get() })
  ignore(read_memo_for_test(m)) // establish m→sig dependency before disposing
  sig.dispose()
  let reachable = @kernel.mark_reachable(rt.core, [m.id()])
  inspect(reachable.contains(m.id()), content="true")
  inspect(reachable.contains(sig.id()), content="false") // disposed → skipped
}

///|
test "gc_sweep: unobserved interior cell is passed to dispose_fn" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 1)
  let m = Memo::Memo(rt, fn() { sig.get() })
  ignore(read_memo_for_test(m)) // compute but release observer
  let swept : Array[_] = []
  @kernel.gc_sweep(rt.core, fn(id) { swept.push(id) })
  let m_swept = for id in swept {
    if id == m.id() { break true }
  } nobreak {
    false
  }
  inspect(m_swept, content="true")
  // Source-role cells (signals) are never selected by gc_sweep
  let sig_swept = for id in swept {
    if id == sig.id() { break true }
  } nobreak {
    false
  }
  inspect(sig_swept, content="false")
}

///|
test "gc_sweep: observed interior cell is not passed to dispose_fn" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 1)
  let m = Memo::Memo(rt, fn() { sig.get() })
  let obs = m.observe()
  ignore(obs.get())
  let swept : Array[_] = []
  @kernel.gc_sweep(rt.core, fn(id) { swept.push(id) })
  let m_swept = for id in swept {
    if id == m.id() { break true }
  } nobreak {
    false
  }
  inspect(m_swept, content="false")
  obs.dispose()
}
