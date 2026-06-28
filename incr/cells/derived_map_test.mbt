///|
test "derived_map: cache hit for same key" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 10)
  let mut compute_count = 0
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => {
    compute_count = compute_count + 1
    source.get() + key
  })

  inspect(by_key.read_or_abort(1), content="11")
  inspect(compute_count, content="1")
  inspect(by_key.read_or_abort(1), content="11")
  inspect(compute_count, content="1")
}

///|
test "derived_map: independent caching per key" {
  let rt = Runtime::Runtime()
  let mut compute_count = 0
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => {
    compute_count = compute_count + 1
    key * 10
  })

  inspect(by_key.has_cached(1), content="false")
  inspect(by_key.cache_len(), content="0")
  inspect(by_key.read_or_abort(1), content="10")
  inspect(by_key.read_or_abort(2), content="20")
  inspect(by_key.read_or_abort(1), content="10")
  inspect(compute_count, content="2")
  inspect(by_key.has_cached(1), content="true")
  inspect(by_key.has_cached(2), content="true")
  inspect(by_key.has_cached(3), content="false")
  inspect(by_key.cache_len(), content="2")
}

///|
test "derived_map: source change triggers lazy recompute per key" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 100)
  let mut compute_count = 0
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => {
    compute_count = compute_count + 1
    source.get() + key
  })

  inspect(by_key.read_or_abort(1), content="101")
  inspect(by_key.read_or_abort(2), content="102")
  inspect(compute_count, content="2")

  source.set(200)
  inspect(compute_count, content="2")

  inspect(by_key.read_or_abort(1), content="201")
  inspect(compute_count, content="3")
  inspect(by_key.read_or_abort(2), content="202")
  inspect(compute_count, content="4")
}

///|
test "derived_map: read mirrors read" {
  let rt = Runtime::Runtime()
  let mut compute_count = 0
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => {
    compute_count = compute_count + 1
    key + 5
  })

  match by_key.read(10) {
    Ok(v) => inspect(v, content="15")
    Err(_) => abort("unexpected error")
  }
  match by_key.read(10) {
    Ok(v) => inspect(v, content="15")
    Err(_) => abort("unexpected error")
  }
  inspect(compute_count, content="1")
}

///|
test "derived_map: read_or and read_or_else mirror successful read" {
  let rt = Runtime::Runtime()
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => key + 5)
  let mut fallback_called = 0

  inspect(by_key.read_or(10, -1), content="15")
  inspect(
    by_key.read_or_else(10, _ => {
      fallback_called = fallback_called + 1
      -2
    }),
    content="15",
  )
  inspect(fallback_called, content="0")
}

///|
test "derived_map: sweep removes disposed entries" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 10)
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => source.get() + key)
  // Force creation of 3 entries by reading them
  inspect(by_key.read_or_abort(1), content="11")
  inspect(by_key.read_or_abort(2), content="12")
  inspect(by_key.read_or_abort(3), content="13")
  inspect(by_key.cache_len(), content="3")
  // All 3 memos are Interior with no observers, so gc collects all 3.
  rt.gc()
  let swept = by_key.sweep_cache()
  inspect(swept, content="3")
  inspect(by_key.cache_len(), content="0")
}

///|
test "derived_map: sweep on empty map returns 0" {
  let rt = Runtime::Runtime()
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => key * 10)
  inspect(by_key.sweep_cache(), content="0")
}

///|
test "derived_map: sweep with all entries alive returns 0" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 1)
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => source.get() + key)
  ignore(by_key.read_or_abort(1))
  ignore(by_key.read_or_abort(2))
  // No gc, no disposal — all entries alive
  inspect(by_key.sweep_cache(), content="0")
  inspect(by_key.cache_len(), content="2")
}

///|
test "derived_map: clear disposes every wrapper and empties the map" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 1)
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => source.get() + key)
  ignore(by_key.read_or_abort(1))
  ignore(by_key.read_or_abort(2))
  ignore(by_key.read_or_abort(3))
  inspect(by_key.cache_len(), content="3")
  // Capture the wrapper memo for key=1 before clearing so we can assert
  // it was actually disposed (not just evicted from the HashMap).
  // Note: can't directly access the inner Memo from DerivedMap's public API
  // without inner access, so we verify indirectly via has_cached + re-read.
  by_key.clear_cache()
  inspect(by_key.cache_len(), content="0")
  inspect(by_key.has_cached(1), content="false")
  // Re-creating an entry after clear() yields a fresh wrapper that recomputes.
  inspect(by_key.read_or_abort(1), content="2")
  inspect(by_key.cache_len(), content="1")
}

///|
test "derived_map: clear is idempotent on an empty map" {
  let rt = Runtime::Runtime()
  let by_key : DerivedMap[Int, Int] = DerivedMap::DerivedMap(rt, key => key * 10)
  by_key.clear_cache()
  inspect(by_key.cache_len(), content="0")
}

///|
test "panic derived_map: get_tracked at top level aborts" {
  // Regression guard: get_tracked must delegate to Memo::get (which
  // aborts outside a tracked context), not read_permissive. Without this
  // test, a refactor that reroutes through read_permissive would preserve
  // in-memo dep recording but silently lose the top-level contract.
  let rt = Runtime::Runtime()
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => key * 10)
  ignore(by_key.get_or_abort(1))
}

///|
test "derived_map: get_tracked records per-key dep, not cross-key" {
  let rt = Runtime::Runtime()
  let src1 = Signal::Signal(rt, 10)
  let src2 = Signal::Signal(rt, 20)
  let by_key = DerivedMap::DerivedMap(rt, (key : Int) => {
    if key == 1 {
      src1.get()
    } else {
      src2.get()
    }
  })
  let mut downstream_count = 0
  let view = Derived::Derived(rt, () => {
    downstream_count = downstream_count + 1
    by_key.get_or_abort(1) * 2
  })
  inspect(view.read_or_abort(), content="20")
  inspect(downstream_count, content="1")
  // Instantiate key=2's memo so the src2 change has a concrete
  // downstream target distinct from view.
  inspect(by_key.read_or_abort(2), content="20")
  // src2 change touches key=2's memo only — view tracks key=1, must not recompute.
  src2.set(99)
  inspect(by_key.read_or_abort(2), content="99")
  inspect(view.read_or_abort(), content="20")
  inspect(downstream_count, content="1")
  // src1 change propagates through key=1's memo to view.
  src1.set(15)
  inspect(view.read_or_abort(), content="30")
  inspect(downstream_count, content="2")
}
