///|
fn bench_uncomputed_pull_fanout(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  for i in 0..<n {
    let offset = i
    ignore(@incr.Derived(rt, () => root.get() + offset))
  }
  assert_eq(rt.dependents(root.id()).length(), 0)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
  })
}

///|
fn bench_primed_pull_fanout_no_push(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  for i in 0..<n {
    let offset = i
    let derived = @incr.Derived(rt, () => root.get() + offset)
    ignore(derived.read_or_abort())
  }
  assert_eq(rt.dependents(root.id()).length(), n)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
  })
}

///|
fn bench_primed_pull_fanout_distant_push(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  let distant_root = @incr.Input(rt, 0, label="distant_root")
  for i in 0..<n {
    let offset = i
    let derived = @incr.Derived(rt, () => root.get() + offset)
    ignore(derived.read_or_abort())
  }
  let distant_live = @incr.EagerDerived(rt, () => distant_root.get())
  assert_eq(rt.dependents(root.id()).length(), n)
  assert_eq(rt.dependents(distant_root.id()).length(), 1)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
  })
  ignore(distant_live)
}

///|
fn bench_primed_pull_fanout_same_root_live_push(
  b : @bench.T,
  n : Int,
) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  for i in 0..<n {
    let offset = i
    let derived = @incr.Derived(rt, () => root.get() + offset)
    ignore(derived.read_or_abort())
  }
  let live = @incr.EagerDerived(rt, () => root.get())
  assert_eq(rt.dependents(root.id()).length(), n + 1)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
    b.keep(live.read())
  })
}

///|
fn bench_dynamic_subgraph_churn_same_root(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  let capture = Ref(true)
  let current : Ref[@incr.Derived[Int]?] = Ref(None)
  // Cell allocation inside compute is intentionally confined to setup. This
  // adversarial shape reproduces lifecycle orphaning without allocating in
  // the timed steady-state body.
  let live = @incr.EagerDerived(rt, () => {
    let inner = if capture.val {
      let next = @incr.Derived(rt, () => root.get())
      current.val = Some(next)
      next
    } else {
      current.val.unwrap()
    }
    inner.get_or_abort()
  })
  for value in 1..<=n {
    root.set(value)
  }
  capture.val = false
  assert_eq(rt.dependents(root.id()).length(), n + 1)
  let mut value = n
  b.bench(() => {
    value += 1
    root.set(value)
    b.keep(live.read())
  })
}

///|
fn bench_abandoned_eager_fanout(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  for i in 0..<n {
    let offset = i
    ignore(@incr.EagerDerived(rt, () => root.get() + offset))
  }
  assert_eq(rt.dependents(root.id()).length(), n)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
  })
}

///|
fn bench_scan_disposed_control(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  let stale : Array[@incr.Derived[Int]] = []
  for i in 0..<n {
    let offset = i
    let derived = @incr.Derived(rt, () => root.get() + offset)
    ignore(derived.read_or_abort())
    stale.push(derived)
  }
  let live = @incr.EagerDerived(rt, () => root.get())
  for derived in stale {
    derived.dispose()
  }
  assert_eq(rt.dependents(root.id()).length(), 1)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
    b.keep(live.read())
  })
}

///|
fn bench_scan_gc_control(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  for i in 0..<n {
    let offset = i
    let derived = @incr.Derived(rt, () => root.get() + offset)
    ignore(derived.read_or_abort())
  }
  let live = @incr.EagerDerived(rt, () => root.get())
  let watch = live.watch()
  ignore(watch.read_or_abort())
  rt.gc()
  let remaining = rt.dependents(root.id())
  assert_eq(remaining.length(), 1)
  assert_true(remaining.contains(live.id()))
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
    b.keep(watch.read_or_abort())
  })
  watch.dispose()
}

///|
fn bench_disposed_pull_no_push_control(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  let stale : Array[@incr.Derived[Int]] = []
  for i in 0..<n {
    let offset = i
    let derived = @incr.Derived(rt, () => root.get() + offset)
    ignore(derived.read_or_abort())
    stale.push(derived)
  }
  for derived in stale {
    derived.dispose()
  }
  assert_eq(rt.dependents(root.id()).length(), 0)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
  })
}

///|
fn bench_gc_pull_no_push_control(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  for i in 0..<n {
    let offset = i
    let derived = @incr.Derived(rt, () => root.get() + offset)
    ignore(derived.read_or_abort())
  }
  rt.gc()
  assert_eq(rt.dependents(root.id()).length(), 0)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
  })
}

///|
fn bench_eager_disposed_control(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  let abandoned : Array[@incr.EagerDerived[Int]] = []
  for i in 0..<n {
    let offset = i
    abandoned.push(@incr.EagerDerived(rt, () => root.get() + offset))
  }
  for eager in abandoned {
    eager.dispose()
  }
  assert_eq(rt.dependents(root.id()).length(), 0)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
  })
}

///|
fn bench_eager_gc_control(b : @bench.T, n : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  for i in 0..<n {
    let offset = i
    ignore(@incr.EagerDerived(rt, () => root.get() + offset))
  }
  assert_eq(rt.dependents(root.id()).length(), n)
  rt.gc()
  assert_eq(rt.dependents(root.id()).length(), 0)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
  })
}

///|
fn bench_chain_depth(b : @bench.T, n : Int, depth : Int) -> Unit raise {
  let rt = @incr.Runtime()
  let root = @incr.Input(rt, 0, label="root")
  for chain in 0..<n {
    let offset = chain
    let mut leaf = @incr.Derived(rt, () => root.get() + offset)
    for _ in 1..<depth {
      let previous = leaf
      leaf = @incr.Derived(rt, () => previous.get_or_abort() + 1)
    }
    ignore(leaf.read_or_abort())
  }
  let live = @incr.EagerDerived(rt, () => root.get())
  assert_eq(rt.dependents(root.id()).length(), n + 1)
  let mut value = 0
  b.bench(() => {
    value += 1
    root.set(value)
    b.keep(live.read())
  })
}

///|
fn make_fan_in_fixture(
  n : Int,
) -> (@incr.Runtime, Array[@incr.Input[Int]], Array[@incr.EagerDerived[Int]]) raise {
  let rt = @incr.Runtime()
  let roots : Array[@incr.Input[Int]] = []
  for i in 0..<12 {
    roots.push(@incr.Input(rt, i, label="root_\{i}"))
  }
  let outputs : Array[@incr.EagerDerived[Int]] = []
  for output in 0..<n {
    let offset = output
    outputs.push(
      @incr.EagerDerived(rt, () => {
        let mut total = offset
        for root in roots {
          total += root.get()
        }
        total
      }),
    )
  }
  for root in roots {
    assert_eq(rt.dependents(root.id()).length(), n)
  }
  (rt, roots, outputs)
}

///|
fn bench_fan_in_one_root(b : @bench.T, n : Int) -> Unit raise {
  let (_rt, roots, outputs) = make_fan_in_fixture(n)
  let mut value = 100
  b.bench(() => {
    value += 1
    roots[0].set(value)
    b.keep(outputs[0].read())
  })
}

///|
fn bench_fan_in_all_roots_batch(b : @bench.T, n : Int) -> Unit raise {
  let (rt, roots, outputs) = make_fan_in_fixture(n)
  let mut value = 100
  b.bench(() => {
    value += 12
    let next = value
    rt.batch(() => {
      for i, root in roots {
        root.set(next + i)
      }
    })
    b.keep(outputs[0].read())
  })
}

///|
test "retention 1: uncomputed pull fanout n=1k" (b : @bench.T) {
  bench_uncomputed_pull_fanout(b, 1_000)
}

///|
test "retention 1: uncomputed pull fanout n=10k" (b : @bench.T) {
  bench_uncomputed_pull_fanout(b, 10_000)
}

///|
test "retention 2: primed pull fanout no push n=1k" (b : @bench.T) {
  bench_primed_pull_fanout_no_push(b, 1_000)
}

///|
test "retention 2: primed pull fanout no push n=10k" (b : @bench.T) {
  bench_primed_pull_fanout_no_push(b, 10_000)
}

///|
test "retention 3: primed pull fanout distant push n=1k" (b : @bench.T) {
  bench_primed_pull_fanout_distant_push(b, 1_000)
}

///|
test "retention 3: primed pull fanout distant push n=10k" (b : @bench.T) {
  bench_primed_pull_fanout_distant_push(b, 10_000)
}

///|
test "retention 4: primed pull fanout same-root live push n=1k" (b : @bench.T) {
  bench_primed_pull_fanout_same_root_live_push(b, 1_000)
}

///|
test "retention 4: primed pull fanout same-root live push n=10k" (b : @bench.T) {
  bench_primed_pull_fanout_same_root_live_push(b, 10_000)
}

///|
test "retention 5: dynamic subgraph churn same-root n=1k" (b : @bench.T) {
  bench_dynamic_subgraph_churn_same_root(b, 1_000)
}

///|
test "retention 5: dynamic subgraph churn same-root n=10k" (b : @bench.T) {
  bench_dynamic_subgraph_churn_same_root(b, 10_000)
}

///|
test "retention 6: abandoned eager fanout n=1k" (b : @bench.T) {
  bench_abandoned_eager_fanout(b, 1_000)
}

///|
test "retention 6: abandoned eager fanout n=10k" (b : @bench.T) {
  bench_abandoned_eager_fanout(b, 10_000)
}

///|
test "retention 7a: scan disposed control n=1k" (b : @bench.T) {
  bench_scan_disposed_control(b, 1_000)
}

///|
test "retention 7a: scan disposed control n=10k" (b : @bench.T) {
  bench_scan_disposed_control(b, 10_000)
}

///|
test "retention 7b: scan gc control n=1k" (b : @bench.T) {
  bench_scan_gc_control(b, 1_000)
}

///|
test "retention 7b: scan gc control n=10k" (b : @bench.T) {
  bench_scan_gc_control(b, 10_000)
}

///|
test "retention 7c: eager disposed control n=1k" (b : @bench.T) {
  bench_eager_disposed_control(b, 1_000)
}

///|
test "retention 7c: eager disposed control n=10k" (b : @bench.T) {
  bench_eager_disposed_control(b, 10_000)
}

///|
test "retention 7d: eager gc control n=1k" (b : @bench.T) {
  bench_eager_gc_control(b, 1_000)
}

///|
test "retention 7d: eager gc control n=10k" (b : @bench.T) {
  bench_eager_gc_control(b, 10_000)
}

///|
test "retention 7e: disposed pull no push n=1k" (b : @bench.T) {
  bench_disposed_pull_no_push_control(b, 1_000)
}

///|
test "retention 7e: disposed pull no push n=10k" (b : @bench.T) {
  bench_disposed_pull_no_push_control(b, 10_000)
}

///|
test "retention 7f: gc pull no push n=1k" (b : @bench.T) {
  bench_gc_pull_no_push_control(b, 1_000)
}

///|
test "retention 7f: gc pull no push n=10k" (b : @bench.T) {
  bench_gc_pull_no_push_control(b, 10_000)
}

///|
test "retention 8a: chain depth=1 n=1k" (b : @bench.T) {
  bench_chain_depth(b, 1_000, 1)
}

///|
test "retention 8a: chain depth=1 n=10k" (b : @bench.T) {
  bench_chain_depth(b, 10_000, 1)
}

///|
test "retention 8a: chain depth=4 n=1k" (b : @bench.T) {
  bench_chain_depth(b, 1_000, 4)
}

///|
test "retention 8a: chain depth=4 n=10k" (b : @bench.T) {
  bench_chain_depth(b, 10_000, 4)
}

///|
test "retention 8b: fan-in one root n=1k" (b : @bench.T) {
  bench_fan_in_one_root(b, 1_000)
}

///|
test "retention 8b: fan-in one root n=10k" (b : @bench.T) {
  bench_fan_in_one_root(b, 10_000)
}

///|
test "retention 8b: fan-in all roots batch n=1k" (b : @bench.T) {
  bench_fan_in_all_roots_batch(b, 1_000)
}

///|
test "retention 8b: fan-in all roots batch n=10k" (b : @bench.T) {
  bench_fan_in_all_roots_batch(b, 10_000)
}
