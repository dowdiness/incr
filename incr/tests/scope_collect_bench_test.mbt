///|
test "scope collect: 100 live keyed entries" (b : @bench.T) {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let source = scope.input(1)
  let by_key = scope.derived_map((key : Int) => source.get() + key)
  let terminal = scope.derived(() => {
    let mut sum = 0
    for key in 0..<100 {
      sum = sum + by_key.get_or_abort(key)
    }
    sum
  })
  let watch = scope.watch(terminal)
  ignore(watch.read_or_abort())
  b.bench(() => scope.collect())
  scope.dispose()
}

///|
/// This is an honest upper bound for stale maintenance: each iteration
/// recreates 100 unrooted entries before collecting and retiring them.
test "scope collect: refill and retire 100 stale keyed entries" (b : @bench.T) {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let by_key = scope.derived_map((key : Int) => key + 1)
  b.bench(() => {
    for key in 0..<100 {
      b.keep(by_key.read_or_abort(key))
    }
    scope.collect()
  })
  scope.dispose()
}

///|
test "scope collect: shared runtime with two 50-entry scopes" (b : @bench.T) {
  let rt = @incr.Runtime()
  let scope_a = @incr.Scope::new(rt)
  let scope_b = @incr.Scope::new(rt)
  let map_a = scope_a.derived_map((key : Int) => key + 1)
  let map_b = scope_b.derived_map((key : Int) => key + 2)
  let terminal_a = scope_a.derived(() => {
    let mut sum = 0
    for key in 0..<50 {
      sum = sum + map_a.get_or_abort(key)
    }
    sum
  })
  let terminal_b = scope_b.derived(() => {
    let mut sum = 0
    for key in 0..<50 {
      sum = sum + map_b.get_or_abort(key)
    }
    sum
  })
  let watch_a = scope_a.watch(terminal_a)
  let watch_b = scope_b.watch(terminal_b)
  ignore(watch_a.read_or_abort())
  ignore(watch_b.read_or_abort())
  b.bench(() => scope_a.collect())
  scope_a.dispose()
  scope_b.dispose()
}

///|
/// Runtime GC is included so every measured read exercises stale-entry
/// recreation instead of the live cache-hit path.
test "derived map: gc plus stale key self-heal" (b : @bench.T) {
  let rt = @incr.Runtime()
  let by_key = @incr.DerivedMap(rt, (key : Int) => key + 1)
  ignore(by_key.read_or_abort(1))
  b.bench(() => {
    rt.gc()
    b.keep(by_key.read_or_abort(1))
  })
}
