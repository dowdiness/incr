///|
test "scope: create and dispose via public API" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = scope.input(42)
  let m = scope.derived(fn() { sig.get() * 2 })
  inspect(read_derived_for_test(m), content="84")
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
  inspect(m.is_disposed(), content="true")
}

///|
test "scope: nested scopes via public API" {
  let rt = @incr.Runtime::Runtime()
  let parent = @incr.Scope::new(rt)
  let child = parent.child()
  let sig = child.input(10)
  parent.dispose()
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: manual dispose before scope dispose is safe" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = scope.input(1)
  let m = scope.derived(fn() { sig.get() })
  // Manually dispose the memo before the scope
  rt.dispose_cell(m.id())
  inspect(m.is_disposed(), content="true")
  // Scope dispose should not abort — idempotent
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: scope does not interfere with unscoped cells" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let scoped_sig = scope.input(1)
  let unscoped_sig = @incr.Input::Input(rt, 2)
  scope.dispose()
  inspect(scoped_sig.is_disposed(), content="true")
  inspect(unscoped_sig.is_disposed(), content="false")
  // Unscoped input still works
  inspect(unscoped_sig.get(), content="2")
}

///|
test "scope: child scope cells disposed before parent cells" {
  let rt = @incr.Runtime::Runtime()
  let parent = @incr.Scope::new(rt)
  let parent_sig = parent.input(100)
  let child = parent.child()
  let child_sig = child.input(200)
  // Child reads parent — this is the typical pattern
  let child_memo = child.derived(fn() { parent_sig.get() + child_sig.get() })
  inspect(read_derived_for_test(child_memo), content="300")
  parent.dispose()
  inspect(child_sig.is_disposed(), content="true")
  inspect(child_memo.is_disposed(), content="true")
  inspect(parent_sig.is_disposed(), content="true")
}

///|
test "scope: dispose during batch — pending input writes discarded" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = scope.input(1)
  rt.batch(fn() {
    sig.set(99)
    // Dispose the scope mid-batch — pending write should be discarded
    scope.dispose()
  })
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: cell manually disposed before scope dispose is safe" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let sig1 = scope.input(1)
  let sig2 = scope.input(2)
  // Manually dispose one cell
  sig1.dispose()
  inspect(sig1.is_disposed(), content="true")
  inspect(sig2.is_disposed(), content="false")
  // Scope dispose should handle already-disposed cell gracefully
  scope.dispose()
  inspect(sig2.is_disposed(), content="true")
}

///|
test "scope: dispose after push propagation completes" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = scope.input(1)
  let count : Ref[Int] = { val: 0 }
  let eff = scope.effect(fn() { count.val = count.val + sig.get() })
  inspect(count.val, content="1")
  // Trigger push propagation
  sig.set(10)
  inspect(count.val, content="11")
  // Dispose after propagation completes — should be safe
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
  inspect(eff.is_disposed(), content="true")
}

///|
test "scope: map_eq-derived cell survives dispose without adopt" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let input = scope.input(42)
  let base = scope.derived(fn() { input.get() })
  let d = base.map(fn(v) { v + 1 })
  let id = d.id()
  // Precondition: cell is alive
  inspect(rt.cell_info(id) is Some(_), content="true")
  scope.dispose()
  // Cell survives because not registered with scope
  inspect(rt.cell_info(id) is Some(_), content="true")
}

///|
test "scope: adopt registers map_eq-derived cell for deterministic disposal" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let input = scope.input(42)
  let base = scope.derived(fn() { input.get() })
  let d = base.map(fn(v) { v + 1 })
  let adopted = scope.adopt(d)
  let id = adopted.id()

  inspect(rt.cell_info(id) is Some(_), content="true")
  scope.dispose()
  // Postcondition: cell is disposed
  inspect(rt.cell_info(id) is None, content="true")
}

///|
test "panic scope: adopt on disposed scope aborts" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  scope.dispose()
  let input = @incr.Input::Input(rt, 0)
  let _ = scope.adopt(input)
}

///|
test "scope: derived_no_backdate accepts non-Eq output" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = scope.input(3)
  let derived = scope.derived_no_backdate(fn() { (x : Int) => x + sig.get() })

  inspect(derived.read_or_abort()(10), content="13")
  sig.set(4)
  inspect(derived.read_or_abort()(10), content="14")
  scope.dispose()
}

///|
test "scope: derived_no_backdate propagates equal output" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let input = scope.input(21)
  let normalized = scope.derived_no_backdate(fn() { input.get() / 10 })
  let mut downstream_runs = 0
  let downstream = @incr.Derived(rt, () => {
    downstream_runs = downstream_runs + 1
    normalized.get_or_abort()
  })

  inspect(downstream.read_or_abort(), content="2")
  input.set(29)
  inspect(downstream.read_or_abort(), content="2")
  inspect(downstream_runs, content="2")
  scope.dispose()
}

///|
test "scope: derived_no_backdate propagates label" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let input = scope.input(21)
  let derived = scope.derived_no_backdate(
    fn() { input.get() / 10 },
    label="scope-no-bd",
  )

  guard rt.cell_info(derived.id()) is Some(info) else {
    fail("expected derived cell info")
  }
  debug_inspect(info.label, content="Some(\"scope-no-bd\")")
  scope.dispose()
}

///|
test "panic scope: derived_no_backdate on disposed scope aborts" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  scope.dispose()
  let _ = scope.derived_no_backdate(fn() { 1 })
}

///|
// Scope::watch folds watch creation + scope registration + one priming read
// into a single call. The priming read computes the target so its
// gc_dependencies are recorded — a Runtime::gc() that runs before the first
// consumer read cannot sweep the upstream graph.
test "scope: watch primes upstream so gc before first read is safe" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = @incr.Input(rt, 1)
  let d1 = @incr.Derived(rt, fn() { sig.get() + 1 })
  let d2 = @incr.Derived(rt, fn() { d1.get_or_abort() * 2 })
  let w = scope.watch(d2)
  // gc before any consumer read — upstream must survive
  rt.gc()
  inspect(d1.is_disposed(), content="false")
  inspect(d2.is_disposed(), content="false")
  inspect(w.read_or_abort(), content="4")
  sig.set(2)
  inspect(w.read_or_abort(), content="6")
  // scope disposal releases the watch
  scope.dispose()
  inspect(w.is_disposed(), content="true")
}

///|
// Contrast test documenting the failure mode Scope::watch closes: a bare
// watch without a priming read GC-roots only the terminal cell. The
// uncomputed terminal has empty gc_dependencies, so gc() sweeps upstream.
test "scope: bare watch without priming loses upstream to gc" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = @incr.Input(rt, 1)
  let d1 = @incr.Derived(rt, fn() { sig.get() + 1 })
  let d2 = @incr.Derived(rt, fn() { d1.get_or_abort() * 2 })
  let w = scope.add_watch(d2.watch())
  rt.gc()
  // terminal survives (GC root), upstream is swept
  inspect(d2.is_disposed(), content="false")
  inspect(d1.is_disposed(), content="true")
  ignore(w)
  scope.dispose()
}

///|
test "panic scope: watch on disposed scope aborts" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let d = @incr.Derived(rt, fn() { 1 })
  scope.dispose()
  let _ = scope.watch(d)
}

///|
test "scope: on_dispose callback runs on dispose" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let mut ran = false
  scope.on_dispose(() => ran = true)
  scope.dispose()
  inspect(ran, content="true")
}

///|
test "scope: on_dispose callback runs at most once despite double dispose" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let mut count = 0
  scope.on_dispose(() => count = count + 1)
  scope.dispose()
  scope.dispose()
  inspect(count, content="1")
}

///|
test "scope: on_dispose child hooks fire before parent hooks" {
  let rt = @incr.Runtime()
  let parent = @incr.Scope::new(rt)
  let child = parent.child()
  let mut log = ""
  child.on_dispose(() => log = log + "child,")
  parent.on_dispose(() => log = log + "parent")
  parent.dispose()
  inspect(log, content="child,parent")
}

///|
test "scope: on_dispose is re-entrant-safe from child and parent hooks" {
  let rt = @incr.Runtime()
  let parent = @incr.Scope::new(rt)
  let child = parent.child()
  let child_sig = child.input(1)
  let parent_sig = parent.input(10)
  let mut child_log = ""
  let mut child_hooks = 0
  let mut parent_hooks = 0
  let mut parent_closed_in_child_hook = false
  let mut parent_closed_in_parent_hook = false
  let mut child_sig_alive_during_child_hook = false
  let mut child_sig_disposed_during_parent_hook = false
  let mut parent_sig_alive_during_parent_hook = false

  child.on_dispose(() => {
    child_hooks = child_hooks + 1
    child_log = child_log + "child,"
    child_sig_alive_during_child_hook = !child_sig.is_disposed()
    parent_closed_in_child_hook = parent.is_disposed()
    parent.dispose()
  })

  parent.on_dispose(() => {
    parent_hooks = parent_hooks + 1
    child_log = child_log + "parent"
    child_sig_disposed_during_parent_hook = child_sig.is_disposed()
    parent_sig_alive_during_parent_hook = !parent_sig.is_disposed()
    parent_closed_in_parent_hook = parent.is_disposed()
    parent.dispose()
  })

  parent.dispose()

  inspect(child_log, content="child,parent")
  inspect(child_hooks, content="1")
  inspect(parent_hooks, content="1")
  inspect(child_sig_alive_during_child_hook, content="true")
  inspect(child_sig_disposed_during_parent_hook, content="true")
  inspect(parent_sig_alive_during_parent_hook, content="true")
  inspect(parent_closed_in_child_hook, content="true")
  inspect(parent_closed_in_parent_hook, content="true")
  inspect(parent.is_disposed(), content="true")
  inspect(child_sig.is_disposed(), content="true")
  inspect(parent_sig.is_disposed(), content="true")

  parent.dispose()
  inspect(child_log, content="child,parent")
  inspect(child_hooks, content="1")
  inspect(parent_hooks, content="1")
}

///|
test "panic scope: on_dispose on already disposed scope aborts" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  scope.dispose()
  scope.on_dispose(() => ())
}
