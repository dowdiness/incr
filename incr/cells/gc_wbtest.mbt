///|
test "add_gc_root: inserts new entry with count 1 and returns 0" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  let prev = rt.add_gc_root(sig.id())
  inspect(prev, content="0")
  debug_inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(1)")
}

///|
test "add_gc_root: increments existing entry and returns previous count" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  let prev1 = rt.add_gc_root(sig.id())
  let prev2 = rt.add_gc_root(sig.id())
  inspect(prev1, content="0")
  inspect(prev2, content="1")
  debug_inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(2)")
}

///|
test "remove_gc_root: decrements and returns remaining" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  ignore(rt.add_gc_root(sig.id()))
  ignore(rt.add_gc_root(sig.id()))
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="1")
  debug_inspect(rt.core.gc_root_counts.get(sig.id()), content="Some(1)")
}

///|
test "remove_gc_root: removes entry at zero" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  ignore(rt.add_gc_root(sig.id()))
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="0")
  debug_inspect(rt.core.gc_root_counts.get(sig.id()), content="None")
}

///|
test "remove_gc_root: returns 0 for unknown cell" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  let remaining = rt.remove_gc_root(sig.id())
  inspect(remaining, content="0")
}

///|
test "cell_id_at: reconstructs CellId from index" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  let reconstructed = @kernel.cell_id_at(rt.core, sig.id().id)
  inspect(reconstructed == sig.id(), content="true")
}

///|
test "dispose_cell: removes gc_root_counts entry for watched cell" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, fn() { sig.get() })
  let watch = m.watch()
  // gc_root_counts has entry
  inspect(rt.core.gc_root_counts.get(m.id()) is None, content="false")
  // manually dispose the memo
  m.dispose()
  // gc_root_counts entry should be cleaned up
  debug_inspect(rt.core.gc_root_counts.get(m.id()), content="None")
  // watch dispose should not abort (skips on_unobserve for dead cell)
  watch.dispose()
}

///|
test "dispose_cell: clears gc_root_counts with multiple watches" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, fn() { sig.get() })
  let watch1 = m.watch()
  let watch2 = m.watch()
  debug_inspect(rt.core.gc_root_counts.get(m.id()), content="Some(2)")
  m.dispose()
  debug_inspect(rt.core.gc_root_counts.get(m.id()), content="None")
  watch1.dispose()
  watch2.dispose()
}

///|
test "dispose preflight: pinned relation preserves root and watch state" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  rel.insert(1) |> ignore
  rt.fixpoint()
  let watched = Derived(rt, fn() { rel.contains(1) })
  let watch = watched.watch()
  inspect(watch.read_or_abort(), content="true")
  let previous_root_count = rt.add_gc_root(rel.id())
  inspect(previous_root_count, content="0")
  let rule = rt.new_rule([rel.id()], [], () => ())

  // Exercise the same private Result boundary used by Runtime::dispose_cell;
  // the public wrapper preserves its existing aborting rejection contract.
  let rejection = rt.try_dispose_cell(rel.id())
  let rejected = match rejection {
    Err(_) => true
    Ok(_) => false
  }
  inspect(rejected, content="true")
  debug_inspect(rt.core.gc_root_counts.get(rel.id()), content="Some(1)")
  inspect(rel.contains(1), content="true")
  inspect(watch.read_or_abort(), content="true")

  watch.dispose()
  ignore(rt.remove_gc_root(rel.id()))
  rt.dispose_rule(rule)
  rel.dispose()
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
test "collect_gc_roots: live watch puts memo in roots via gc_root_counts" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, fn() { sig.get() })
  let watch = m.watch()
  ignore(watch.read_or_abort())
  let roots = @kernel.collect_gc_roots(rt.core)
  let contains_memo = for id in roots {
    if id == m.id() {
      break true
    }
  } nobreak {
    false
  }
  inspect(contains_memo, content="true")
  watch.dispose()
}

///|
test "collect_gc_roots: disposed watch is absent from roots" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, fn() { sig.get() })
  let watch = m.watch()
  ignore(watch.read_or_abort())
  watch.dispose()
  let roots = @kernel.collect_gc_roots(rt.core)
  let contains_memo = for id in roots {
    if id == m.id() {
      break true
    }
  } nobreak {
    false
  }
  inspect(contains_memo, content="false")
}

///|
test "mark_reachable: input is reachable through dependent memo" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, fn() { sig.get() })
  ignore(m.read_or_abort()) // compute to establish m→sig dependency
  let reachable = @kernel.mark_reachable(rt.core, [m.id()])
  inspect(reachable.contains(m.id()), content="true")
  inspect(reachable.contains(sig.id()), content="true")
}

///|
test "mark_reachable: traversal stops at a disposed dependency" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, fn() { sig.get() })
  ignore(m.read_or_abort()) // establish m→sig dependency before disposing
  sig.dispose()
  let reachable = @kernel.mark_reachable(rt.core, [m.id()])
  inspect(reachable.contains(m.id()), content="true")
  inspect(reachable.contains(sig.id()), content="false") // disposed → skipped
}

///|
test "gc_sweep: unobserved interior cell is passed to dispose_fn" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, fn() { sig.get() })
  ignore(m.read_or_abort()) // compute but release observer
  let swept : Array[_] = []
  @kernel.gc_sweep(rt.core, fn(id) { swept.push(id) })
  let m_swept = for id in swept {
    if id == m.id() {
      break true
    }
  } nobreak {
    false
  }
  inspect(m_swept, content="true")
  // Source-role cells (inputs) are never selected by gc_sweep
  let sig_swept = for id in swept {
    if id == sig.id() {
      break true
    }
  } nobreak {
    false
  }
  inspect(sig_swept, content="false")
}

///|
test "gc_sweep: watched interior cell is not passed to dispose_fn" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, fn() { sig.get() })
  let watch = m.watch()
  ignore(watch.read_or_abort())
  let swept : Array[_] = []
  @kernel.gc_sweep(rt.core, fn(id) { swept.push(id) })
  let m_swept = for id in swept {
    if id == m.id() {
      break true
    }
  } nobreak {
    false
  }
  inspect(m_swept, content="false")
  watch.dispose()
}
