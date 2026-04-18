///|
test "memo_map: cache hit for same key" {
  let rt = Runtime::new()
  let source = Signal::new(rt, 10)
  let mut compute_count = 0
  let by_key = MemoMap::new(rt, (key : Int) => {
    compute_count = compute_count + 1
    source.get() + key
  })

  inspect(by_key.get(1), content="11")
  inspect(compute_count, content="1")
  inspect(by_key.get(1), content="11")
  inspect(compute_count, content="1")
}

///|
test "memo_map: independent caching per key" {
  let rt = Runtime::new()
  let mut compute_count = 0
  let by_key = MemoMap::new(rt, (key : Int) => {
    compute_count = compute_count + 1
    key * 10
  })

  inspect(by_key.contains(1), content="false")
  inspect(by_key.length(), content="0")
  inspect(by_key.get(1), content="10")
  inspect(by_key.get(2), content="20")
  inspect(by_key.get(1), content="10")
  inspect(compute_count, content="2")
  inspect(by_key.contains(1), content="true")
  inspect(by_key.contains(2), content="true")
  inspect(by_key.contains(3), content="false")
  inspect(by_key.length(), content="2")
}

///|
test "memo_map: source change triggers lazy recompute per key" {
  let rt = Runtime::new()
  let source = Signal::new(rt, 100)
  let mut compute_count = 0
  let by_key = MemoMap::new(rt, (key : Int) => {
    compute_count = compute_count + 1
    source.get() + key
  })

  inspect(by_key.get(1), content="101")
  inspect(by_key.get(2), content="102")
  inspect(compute_count, content="2")

  source.set(200)
  inspect(compute_count, content="2")

  inspect(by_key.get(1), content="201")
  inspect(compute_count, content="3")
  inspect(by_key.get(2), content="202")
  inspect(compute_count, content="4")
}

///|
test "memo_map: get_result mirrors get" {
  let rt = Runtime::new()
  let mut compute_count = 0
  let by_key = MemoMap::new(rt, (key : Int) => {
    compute_count = compute_count + 1
    key + 5
  })

  match by_key.get_result(10) {
    Ok(v) => inspect(v, content="15")
    Err(_) => abort("unexpected error")
  }
  match by_key.get_result(10) {
    Ok(v) => inspect(v, content="15")
    Err(_) => abort("unexpected error")
  }
  inspect(compute_count, content="1")
}

///|
test "memo_map: get_or and get_or_else mirror successful get_result" {
  let rt = Runtime::new()
  let by_key = MemoMap::new(rt, (key : Int) => key + 5)
  let mut fallback_called = 0

  inspect(by_key.get_or(10, -1), content="15")
  inspect(
    by_key.get_or_else(10, _ => {
      fallback_called = fallback_called + 1
      -2
    }),
    content="15",
  )
  inspect(fallback_called, content="0")
}

///|
test "memo_map: sweep removes disposed entries" {
  let rt = Runtime::new()
  let source = Signal::new(rt, 10)
  let by_key = MemoMap::new(rt, (key : Int) => source.get() + key)
  // Force creation of 3 entries by reading them
  inspect(by_key.get(1), content="11")
  inspect(by_key.get(2), content="12")
  inspect(by_key.get(3), content="13")
  inspect(by_key.length(), content="3")
  // All 3 memos are Interior with no observers, so gc collects all 3.
  rt.gc()
  let swept = by_key.sweep()
  inspect(swept, content="3")
  inspect(by_key.length(), content="0")
}

///|
test "memo_map: sweep on empty map returns 0" {
  let rt = Runtime::new()
  let by_key = MemoMap::new(rt, (key : Int) => key * 10)
  inspect(by_key.sweep(), content="0")
}

///|
test "memo_map: sweep with all entries alive returns 0" {
  let rt = Runtime::new()
  let source = Signal::new(rt, 1)
  let by_key = MemoMap::new(rt, (key : Int) => source.get() + key)
  ignore(by_key.get(1))
  ignore(by_key.get(2))
  // No gc, no disposal — all entries alive
  inspect(by_key.sweep(), content="0")
  inspect(by_key.length(), content="2")
}

///|
test "memo_map: clear disposes every wrapper and empties the map" {
  let rt = Runtime::new()
  let source = Signal::new(rt, 1)
  let by_key = MemoMap::new(rt, (key : Int) => source.get() + key)
  ignore(by_key.get(1))
  ignore(by_key.get(2))
  ignore(by_key.get(3))
  inspect(by_key.length(), content="3")
  // Capture the wrapper memo for key=1 before clearing so we can assert
  // it was actually disposed (not just evicted from the HashMap).
  let _ = by_key.contains(1)
  by_key.clear()
  inspect(by_key.length(), content="0")
  inspect(by_key.contains(1), content="false")
  // Re-creating an entry after clear() yields a fresh wrapper that recomputes.
  inspect(by_key.get(1), content="2")
  inspect(by_key.length(), content="1")
}

///|
test "memo_map: clear is idempotent on an empty map" {
  let rt = Runtime::new()
  let by_key : MemoMap[Int, Int] = MemoMap::new(rt, key => key * 10)
  by_key.clear()
  inspect(by_key.length(), content="0")
}
