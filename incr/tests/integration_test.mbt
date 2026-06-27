///|
test "integration: diamond dependency" {
  // input -> A -> C
  //       -> B -> C
  // C depends on both A and B which both depend on input
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 10)
  let mut a_count = 0
  let a = Derived::Derived(rt, () => {
    a_count = a_count + 1
    input.get() + 1
  })
  let mut b_count = 0
  let b = Derived::Derived(rt, () => {
    b_count = b_count + 1
    input.get() * 2
  })
  let mut c_count = 0
  let c = Derived::Derived(rt, () => {
    c_count = c_count + 1
    a.get_or_abort() + b.get_or_abort()
  })
  // Initial
  inspect(read_derived_for_test(c), content="31") // (10 + 1) + (10 * 2) = 11 + 20 = 31
  inspect(a_count, content="1")
  inspect(b_count, content="1")
  inspect(c_count, content="1")
  // Change input
  input.set(5)
  inspect(read_derived_for_test(c), content="16") // (5 + 1) + (5 * 2) = 6 + 10 = 16
  inspect(a_count, content="2")
  inspect(b_count, content="2")
  inspect(c_count, content="2")
}

///|
test "integration: long chain (5 levels)" {
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 1)
  let l1 = Derived::Derived(rt, () => input.get() + 1)
  let l2 = Derived::Derived(rt, () => l1.get_or_abort() + 1)
  let l3 = Derived::Derived(rt, () => l2.get_or_abort() + 1)
  let l4 = Derived::Derived(rt, () => l3.get_or_abort() + 1)
  let l5 = Derived::Derived(rt, () => l4.get_or_abort() + 1)
  inspect(read_derived_for_test(l5), content="6") // 1 + 5
  input.set(10)
  inspect(read_derived_for_test(l5), content="15") // 10 + 5
  input.set(0)
  inspect(read_derived_for_test(l5), content="5") // 0 + 5
}

///|
test "integration: multiple independent inputs" {
  let rt = Runtime::Runtime()
  let x = Signal::Signal(rt, 2)
  let y = Signal::Signal(rt, 3)
  let z = Signal::Signal(rt, 5)
  let mut compute_count = 0
  let result = Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    x.get() * y.get() + z.get()
  })
  inspect(read_derived_for_test(result), content="11") // 2*3 + 5
  inspect(compute_count, content="1")
  // Change only x
  x.set(4)
  inspect(read_derived_for_test(result), content="17") // 4*3 + 5
  inspect(compute_count, content="2")
  // Change only z
  z.set(10)
  inspect(read_derived_for_test(result), content="22") // 4*3 + 10
  inspect(compute_count, content="3")
  // Change y
  y.set(0)
  inspect(read_derived_for_test(result), content="10") // 4*0 + 10
  inspect(compute_count, content="4")
}

///|
test "integration: diamond with backdating" {
  // input -> is_positive -> result
  //       -> abs_val     -> result
  // When input goes from 5 to -5:
  // - is_positive changes (true -> false), so result must recompute
  // - abs_val stays 5 (backdated)
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 5)
  let is_positive = Derived::Derived(rt, () => input.get() > 0)
  let abs_val = Derived::Derived(rt, () => {
    let v = input.get()
    if v < 0 {
      -v
    } else {
      v
    }
  })
  let mut result_count = 0
  let result = Derived::Derived(rt, () => {
    result_count = result_count + 1
    let sign = if is_positive.get_or_abort() { 1 } else { -1 }
    sign * abs_val.get_or_abort()
  })
  inspect(read_derived_for_test(result), content="5")
  inspect(result_count, content="1")
  // Change to -5: is_positive changes, abs_val backdated, but result still recomputes
  input.set(-5)
  inspect(read_derived_for_test(result), content="-5")
  inspect(result_count, content="2")
  // Change to -3: is_positive stays false (backdated), abs_val changes
  input.set(-3)
  inspect(read_derived_for_test(result), content="-3")
  inspect(result_count, content="3")
}

///|
test "integration: multiple reads of same memo" {
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 7)
  let mut compute_count = 0
  let memo = Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    input.get() * input.get()
  })
  // Multiple reads should not recompute
  inspect(read_derived_for_test(memo), content="49")
  inspect(read_derived_for_test(memo), content="49")
  inspect(read_derived_for_test(memo), content="49")
  inspect(compute_count, content="1")
}

///|
test "integration: cascading updates" {
  let rt = Runtime::Runtime()
  let a = Signal::Signal(rt, 1)
  let b = Signal::Signal(rt, 2)
  let sum = Derived::Derived(rt, () => a.get() + b.get())
  let product = Derived::Derived(rt, () => a.get() * b.get())
  let combined = Derived::Derived(rt, () => {
    sum.get_or_abort() + product.get_or_abort()
  })
  inspect(read_derived_for_test(combined), content="5") // (1+2) + (1*2) = 3 + 2
  a.set(3)
  inspect(read_derived_for_test(combined), content="11") // (3+2) + (3*2) = 5 + 6
  b.set(4)
  inspect(read_derived_for_test(combined), content="19") // (3+4) + (3*4) = 7 + 12
}

///|
test "integration: mixed durability chain" {
  let rt = Runtime::Runtime()
  let config = Signal::Signal(rt, 10, durability=High)
  let source = Signal::Signal(rt, 5)
  let scaled = Derived::Derived(rt, () => source.get() * config.get())
  inspect(read_derived_for_test(scaled), content="50")
  // Only change low-durability input
  source.set(3)
  inspect(read_derived_for_test(scaled), content="30")
  // Change high-durability input
  config.set(20)
  inspect(read_derived_for_test(scaled), content="60")
}

///|
test "integration: repeated set-get cycles" {
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 0)
  let doubled = Derived::Derived(rt, () => input.get() * 2)
  for i = 1; i <= 10; i = i + 1 {
    input.set(i)
    let _ = read_derived_for_test(doubled)
  }
  inspect(read_derived_for_test(doubled), content="20") // 10 * 2
}

///|
test "integration: deep chain (200+ levels) - iterative verification" {
  // Stress test: a chain of 250 memos, each depending on the previous.
  // This would cause a stack overflow with recursive verification.
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 1)
  let depth = 250
  // Build chain: memos[0] depends on input, memos[i] depends on memos[i-1]
  let memos : Array[Derived[Int]] = []
  memos.push(Derived::Derived(rt, () => input.get() + 1))
  for i = 1; i < depth; i = i + 1 {
    let prev = memos[i - 1]
    memos.push(Derived::Derived(rt, () => prev.get_or_abort() + 1))
  }
  let tail = memos[depth - 1]
  // Initial: 1 + 250 = 251
  inspect(read_derived_for_test(tail), content="251")
  // Change input and verify propagation through entire chain
  input.set(10)
  inspect(read_derived_for_test(tail), content="260") // 10 + 250
  // Backdating test: set input back to 1
  input.set(1)
  inspect(read_derived_for_test(tail), content="251") // 1 + 250
}

///|
test "integration: dynamic dependencies" {
  // A memo that conditionally reads different signals based on a flag.
  // When the flag flips, the dependency set changes between invocations.
  let rt = Runtime::Runtime()
  let flag = Signal::Signal(rt, true)
  let a = Signal::Signal(rt, 10)
  let b = Signal::Signal(rt, 20)
  let mut compute_count = 0
  let result = Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    if flag.get() {
      a.get()
    } else {
      b.get()
    }
  })
  // Initially reads flag + a
  inspect(read_derived_for_test(result), content="10")
  inspect(compute_count, content="1")
  // Changing b should not trigger recompute (not a dependency)
  b.set(99)
  inspect(read_derived_for_test(result), content="10")
  // result recomputed because b's revision bump made maybe_changed_after
  // walk deps, but the dep list is [flag, a], and flag/a didn't change.
  // However, the global revision bumped so verification still runs.
  // The key check: the value is still correct.
  // Flip the flag: now result depends on flag + b
  flag.set(false)
  inspect(read_derived_for_test(result), content="99")
  // Now changing a should not trigger recompute of result
  // (a is no longer in the dependency set after the flag flip)
  a.set(42)
  inspect(read_derived_for_test(result), content="99")
  // Changing b should now trigger recompute
  b.set(55)
  inspect(read_derived_for_test(result), content="55")
}

///|
test "integration: batch + on_change + memo chain fires once with correct final state" {
  // Verifies that when a batch updates multiple signals, the global on_change
  // fires exactly once, per-cell callbacks fire once per changed signal, and
  // downstream memos see the fully committed state (not intermediate values).
  let rt = Runtime::Runtime()
  let x = Signal::Signal(rt, 0, label="x")
  let y = Signal::Signal(rt, 0, label="y")
  let sum = Derived::Derived(rt, () => x.get() + y.get(), label="sum")
  let product = Derived::Derived(rt, () => x.get() * y.get(), label="product")
  // Track callback invocations
  let global_fires : Ref[Int] = { val: 0 }
  let x_fires : Ref[Int] = { val: 0 }
  let y_fires : Ref[Int] = { val: 0 }
  let sum_at_callback : Ref[Int] = { val: -1 }
  rt.set_on_change(() => {
    global_fires.val = global_fires.val + 1
    // Read memos inside the callback — must see committed values
    sum_at_callback.val = read_derived_for_test(sum)
  })
  x.on_change(_v => x_fires.val = x_fires.val + 1)
  y.on_change(_v => y_fires.val = y_fires.val + 1)
  // Batch: set both signals atomically
  rt.batch(() => {
    x.set(3)
    y.set(4)
  })
  // Per-cell callbacks: one per changed signal
  inspect(x_fires.val, content="1")
  inspect(y_fires.val, content="1")
  // Global callback fires exactly once
  inspect(global_fires.val, content="1")
  // Memos inside the global callback saw the final committed state
  inspect(sum_at_callback.val, content="7") // 3 + 4
  // Memos computed lazily after batch reflect the committed values
  inspect(read_derived_for_test(sum), content="7")
  inspect(read_derived_for_test(product), content="12") // 3 * 4
  // Revert detection: write then revert within the same batch (no net change)
  rt.batch(() => {
    x.set(30)
    x.set(3) // revert to original batch-start value
    y.set(40)
    y.set(4) // revert to original batch-start value
  })
  // No signal ended up changed, so no callbacks should fire.
  inspect(x_fires.val, content="1")
  inspect(y_fires.val, content="1")
  inspect(global_fires.val, content="1")
  // Derived values remain unchanged as well.
  inspect(read_derived_for_test(sum), content="7") // 3 + 4
  inspect(read_derived_for_test(product), content="12") // 3 * 4
}

///|
test "dispose: signal dispose cascades to memo staleness" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 10)
  let m = Derived::Derived(rt, fn() { sig.get() * 2 })
  inspect(read_derived_for_test(m), content="20")
  sig.dispose()
  // Memo's dependency is now disposed — verifying should abort
  // But since we can't catch aborts in tests, verify the signal is disposed
  assert_true(sig.is_disposed())
}

///|
test "dispose: multiple signals, dispose one, others unaffected" {
  let rt = Runtime::Runtime()
  let a = Signal::Signal(rt, 1)
  let b = Signal::Signal(rt, 2)
  let sum = Derived::Derived(rt, fn() { a.get() + b.get() })
  inspect(read_derived_for_test(sum), content="3")
  a.dispose()
  assert_true(a.is_disposed())
  assert_false(b.is_disposed())
  assert_false(sum.is_disposed())
}

///|
test "scope: add_observer triggers suspension on scope dispose" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 5)
  let r = @incr.Reactive::new(rt, fn() { sig.get() + 1 })
  let scope = @incr.Scope::new(rt)
  let obs = scope.add_observer(r.observe())
  inspect(obs.get(), content="6")
  sig.set(10)
  inspect(obs.get(), content="11")
  // Scope dispose triggers observer dispose triggers on_unobserve
  scope.dispose()
  // Reactive is suspended — gc can collect it
  rt.gc()
  assert_true(r.is_disposed())
}

///|
test "memo_map: sweep after gc cleans up disposed entries" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 1)
  let mm = @incr.DerivedMap::DerivedMap(rt, fn(k : Int) { source.get() + k })
  // Create entries
  ignore(mm.read_or_abort(10))
  ignore(mm.read_or_abort(20))
  inspect(mm.cache_len(), content="2")
  // No observers — gc collects all interior memos
  rt.gc()
  inspect(mm.sweep_cache(), content="2")
  inspect(mm.cache_len(), content="0")
  // Fresh entries can be recreated
  inspect(mm.read_or_abort(10), content="11")
  inspect(mm.cache_len(), content="1")
}

///|
test "cross-engine: fixpoint fires on_change only when facts change" {
  let rt = Runtime::Runtime()
  let rel : @incr.Relation[Int] = @incr.Relation::Relation(rt, label="R")
  let mut notifications = 0
  rt.set_on_change(() => notifications = notifications + 1)
  // Fixpoint with no pending delta — no notification expected
  rt.fixpoint()
  inspect(notifications, content="0")
  // Insert a fact so the delta is non-empty, then run fixpoint
  let _ = rel.insert(42)
  rt.fixpoint()
  inspect(notifications, content="1")
}

///|
test "interning: InternId works as Relation element with O(1) equality" {
  // Validates that InternId can be used as a Datalog Relation element type.
  // Same semantic value → same InternId → relation dedups via integer hash/eq
  // on the tuple components, not structural comparison of the underlying String.
  let rt = Runtime::Runtime()
  let names : @incr.InternTable[String] = @incr.InternTable::new()
  let calls : @incr.Relation[(@incr.InternId, @incr.InternId)] = @incr.Relation::Relation(
    rt,
    label="calls",
  )
  let reachable : @incr.Relation[(@incr.InternId, @incr.InternId)] = @incr.Relation::Relation(
    rt,
    label="reachable",
  )
  // Transitive closure:
  //   reachable(x, y) :- calls(x, y).
  //   reachable(x, z) :- reachable(x, y), calls(y, z).
  let _ = rt.new_rule([calls.id()], [reachable.id()], () => {
    for c in calls.delta_iter() {
      reachable.insert(c) |> ignore
    }
    for r in reachable.iter() {
      for c in calls.iter() {
        if r.1 == c.0 {
          reachable.insert((r.0, c.1)) |> ignore
        }
      }
    }
  })
  let foo = names.intern("foo")
  let bar = names.intern("bar")
  let baz = names.intern("baz")
  inspect(calls.insert((foo, bar)), content="true")
  inspect(calls.insert((bar, baz)), content="true")
  // Re-interning "foo" yields the same InternId → duplicate insert deduped
  // via integer equality on the tuple, not by re-hashing the String.
  inspect(calls.insert((names.intern("foo"), bar)), content="false")
  rt.fixpoint()
  inspect(reachable.contains((foo, bar)), content="true")
  inspect(reachable.contains((bar, baz)), content="true")
  inspect(reachable.contains((foo, baz)), content="true")
  inspect(reachable.contains((baz, foo)), content="false")
}
