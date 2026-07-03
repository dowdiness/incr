///|
/// Premise-1 anchor for the per-mode Runtime split investigation
/// (memory/project_per_mode_redesign_question.md). Measures the cost of
/// allocating one full Runtime including the PushState + DatalogState
/// luggage that a pull-only consumer never touches. Compare against
/// `input: get` and `input: set new value` below to size the luggage
/// against the per-cell costs that already dominate any real workload.
test "runtime: new (full, all modes)" (b : @bench.T) {
  b.bench(fn() { b.keep(Runtime::Runtime()) })
}

///|
test "input: get" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  b.bench(fn() { b.keep(sig.get()) })
}

///|
test "input: set same value (no-op)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  b.bench(fn() { sig.set(0) })
}

///|
test "input: set new value" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
  })
}

///|
test "memo: get warm (up-to-date, no recompute)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  let m = Derived::Derived(rt, () => sig.get() * 2)
  ignore(read_derived_for_test(m)) // prime
  b.bench(fn() { b.keep(read_derived_for_test(m)) })
}

///|
test "memo: get stale (input changed, recompute)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let m = Derived::Derived(rt, () => sig.get() * 2)
  ignore(read_derived_for_test(m)) // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    b.keep(read_derived_for_test(m))
  })
}

///|
test "memo: deep chain get (100 levels, stale)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let depth = 100
  let memos : Array[Derived[Int]] = []
  memos.push(Derived::Derived(rt, () => sig.get()))
  for i = 1; i < depth; i = i + 1 {
    let prev = memos[i - 1]
    memos.push(Derived::Derived(rt, () => prev.get_or_abort() + 1))
  }
  let leaf = memos[depth - 1]
  ignore(read_derived_for_test(leaf)) // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    b.keep(read_derived_for_test(leaf))
  })
}

///|
test "memo: wide fanout get (1 input, 50 memos, stale)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let width = 50
  let memos : Array[Derived[Int]] = []
  for i = 0; i < width; i = i + 1 {
    let multiplier = i + 1
    memos.push(Derived::Derived(rt, () => sig.get() * multiplier))
  }
  for i = 0; i < width; i = i + 1 {
    ignore(read_derived_for_test(memos[i])) // prime all
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    for i = 0; i < width; i = i + 1 {
      b.keep(read_derived_for_test(memos[i]))
    }
  })
}

///|
/// T1b Phase 2 anchor: pure pull-mode memo recompute fanout that touches
/// no accumulator APIs. Tracks the commit hot-path overhead added by the
/// MemoCommitPhase dispatch + AccumulatorCommitHook. With the
/// `accumulator_slots.is_empty()` fast-path in place, this workload pays
/// only a length check per recompute and runs faster than pre-T1b (which
/// always allocated HashSets and called rt.accumulator_contributions ops
/// unconditionally on every memo recompute regardless of whether any
/// accumulator was touched).
///
/// Numbers below from 2026-05-17 on branch refactor/t1b-memo-commit-phase
/// (rt: AMD WSL2; high run-to-run variance on push benches is environmental,
/// not real perf):
///   bench                                    pre-T1b     Phase 1     Phase 2+fast-path
///   memo: no-accumulator recompute fanout    26.70 µs    25.41 µs    19.82 µs
///   memo: wide fanout (1 input, 50 memos)   25.81 µs    25.37 µs    21.37 µs
///   memo: deep chain (100 levels, stale)     39.24 µs    40.52 µs    29.50 µs
///   baseline: push propagation 100 live      22.27 µs    21.24 µs    20-32 µs (noisy)
///
/// Pre-T1b reference was cherry-picked onto main 12a6042. Phase 2 commit
/// at 5290fef regressed these rows ~+17%; perf-fix at HEAD restores via
/// AccumulatorCommitHook's lazy-entry pattern (push paths use
/// ensure_for_cell; before_recompute/after_* skip when slots empty).
test "memo: no-accumulator recompute fanout" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let width = 50
  let memos : Array[Derived[Int]] = []
  for i = 0; i < width; i = i + 1 {
    memos.push(Derived::Derived(rt, () => sig.get()))
  }
  for i = 0; i < width; i = i + 1 {
    ignore(read_derived_for_test(memos[i])) // prime all
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    for i = 0; i < width; i = i + 1 {
      b.keep(read_derived_for_test(memos[i]))
    }
  })
}

///|
test "hybrid: get warm (up-to-date, no recompute)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  let h = @incr.ReachableDerived::ReachableDerived(rt, () => sig.get() * 2)
  ignore(read_reachable_for_test(h)) // prime
  b.bench(fn() { b.keep(read_reachable_for_test(h)) })
}

///|
test "hybrid: get stale (input changed, recompute)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let h = @incr.ReachableDerived::ReachableDerived(rt, () => sig.get() * 2)
  ignore(read_reachable_for_test(h)) // prime
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    sig.set(v)
    b.keep(read_reachable_for_test(h))
  })
}

///|
test "batch: 10 inputs, single revision" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sigs : Array[Input[Int]] = []
  for i = 0; i < 10; i = i + 1 {
    sigs.push(Input::Input(rt, i))
  }
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    let cv = v
    rt.batch(fn() {
      for i = 0; i < 10; i = i + 1 {
        sigs[i].set(cv)
      }
    })
  })
}

///|
test "baseline: input.set with clean runtime" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
}

///|
test "baseline: input.set with 10k unreferenced memos" (b : @bench.T) {
  // Memos are created and immediately dropped. They persist in the SoA
  // arrays because they are not explicitly disposed. This measures whether
  // accumulated SoA entries affect input.set performance.
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  for i = 0; i < 10_000; i = i + 1 {
    let idx = i
    ignore(Derived::Derived(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
}

///|
test "baseline: memo creation cost (monotonic SoA growth)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  b.bench(fn() { ignore(Derived::Derived(rt, fn() { sig.get() })) })
}

///|
test "baseline: push propagation with 100 live reactives" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let reactives : Array[@incr.EagerDerived[Int]] = []
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    reactives.push(@incr.EagerDerived::EagerDerived(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
  ignore(reactives)
}

///|
test "baseline: push propagation with 100 disposed reactives" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    let r = @incr.EagerDerived::EagerDerived(rt, fn() { sig.get() + idx })
    r.dispose()
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
}

///|
test "baseline: push propagation with 100 abandoned reactives (handle dropped)" (
  b : @bench.T,
) {
  // User dropped handle but reactive is still live in SoA — push still
  // propagates through it. This is the CPU waste GC should eliminate.
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    ignore(@incr.EagerDerived::EagerDerived(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
}

///|
test "baseline: reactive create-dispose cycle (existing free list)" (
  b : @bench.T,
) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  b.bench(fn() {
    let r = @incr.EagerDerived::EagerDerived(rt, fn() { sig.get() })
    r.dispose()
  })
}

///|
test "layer1: memo create-dispose cycle (free list)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  b.bench(fn() {
    let m = Derived::Derived(rt, fn() { sig.get() })
    ignore(read_derived_for_test(m))
    rt.dispose_cell(m.id())
  })
}

///|
test "layer1: input create-dispose cycle (free list)" (b : @bench.T) {
  let rt = Runtime::Runtime()
  b.bench(fn() {
    let sig = Input::Input(rt, 0)
    sig.dispose()
  })
}

///|
test "layer2: scope create and dispose (empty)" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  b.bench(fn() {
    let scope = @incr.Scope::new(rt)
    scope.dispose()
  })
}

///|
test "layer2: scope create 10 inputs and dispose" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  b.bench(fn() {
    let scope = @incr.Scope::new(rt)
    for i in 0..<10 {
      let _ = scope.input(i)
    }
    scope.dispose()
  })
}

///|
test "layer2: scope bulk dispose 100 mixed cells" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  b.bench(fn() {
    let scope = @incr.Scope::new(rt)
    for i in 0..<50 {
      let _ = scope.input(i)
    }
    for _ in 0..<50 {
      let _ = scope.derived(fn() { 0 })
    }
    scope.dispose()
  })
}

///|
test "layer2: nested scope (3 levels) create and dispose" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  b.bench(fn() {
    let root = @incr.Scope::new(rt)
    let mid = root.child()
    let leaf = mid.child()
    let _ = root.input(1)
    let _ = mid.input(2)
    let _ = leaf.input(3)
    root.dispose()
  })
}

///|
// ─── Layer 4a: Observer + gc() ──────────────────────────────────────────────

///|
test "observer: get warm (memo)" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  let sig = @incr.Input::Input(rt, 42)
  let m = @incr.Derived::Derived(rt, fn() { sig.get() * 2 })
  let obs = m.observe()
  ignore(obs.get()) // prime
  b.bench(fn() { b.keep(obs.get()) })
  obs.dispose()
}

///|
test "observer: observe + dispose cycle" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  let sig = @incr.Input::Input(rt, 42)
  let m = @incr.Derived::Derived(rt, fn() { sig.get() * 2 })
  ignore(read_derived_for_test(m)) // prime
  b.bench(fn() {
    let obs = m.observe()
    b.keep(obs.get())
    obs.dispose()
  })
}

///|
test "gc: sweep 1k all-live" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  let sig = @incr.Input::Input(rt, 1)
  let observers : Array[@incr.Observer[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let m = @incr.Derived::Derived(rt, fn() { sig.get() + i })
    let obs = m.observe()
    ignore(obs.get())
    observers.push(obs)
  }
  b.bench(fn() { rt.gc() })
  for obs in observers {
    obs.dispose()
  }
}

///|
test "gc: sweep 1k all-dead" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  let sig = @incr.Input::Input(rt, 1)
  for i = 0; i < 1000; i = i + 1 {
    let m = @incr.Derived::Derived(rt, fn() { sig.get() + i })
    ignore(read_derived_for_test(m))
  }
  // First gc disposes all, subsequent gcs are sweeps over Disposed entries
  rt.gc()
  b.bench(fn() { rt.gc() })
}

///|
test "gc: sweep 1k 50pct dead" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  let sig = @incr.Input::Input(rt, 1)
  let observers : Array[@incr.Observer[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let m = @incr.Derived::Derived(rt, fn() { sig.get() + i })
    let obs = m.observe()
    ignore(obs.get())
    if i % 2 == 0 {
      obs.dispose()
    } else {
      observers.push(obs)
    }
  }
  b.bench(fn() { rt.gc() })
  for obs in observers {
    obs.dispose()
  }
}

///|
test "runtime: read one-shot" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  let sig = @incr.Input::Input(rt, 42)
  let m = @incr.Derived::Derived(rt, fn() { sig.get() * 2 })
  ignore(read_derived_for_test(m)) // prime
  b.bench(fn() { b.keep(read_derived_for_test(m)) })
}

///|
/// Measures fixpoint convergence on a stable relation (no pending delta).
/// This is the common driver pattern: drivers batch inserts, then call
/// fixpoint to check for convergence. After the prime run, deltas are empty
/// and fixpoint returns after detecting stable state. Gates Stage 3g of
/// the R1 kernel split plan.
test "fixpoint: one iteration, empty delta (stable convergence)" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  let rel : @incr.Relation[Int] = @incr.Relation::Relation(rt, label="R")
  let _ = rel.insert(42)
  rt.fixpoint() // prime: converge to stable state
  b.bench(fn() { rt.fixpoint() })
}

///|
/// Measures fixpoint with a non-empty delta each iteration: inserts a
/// fresh fact, runs one rule that copies the delta into a derived
/// relation, converges. Exercises the productive path through
/// `datalog_fixpoint.run_fixpoint` and its tail `publish_cell_changes`
/// call. Gates Stage 3g of the R1 kernel split plan.
test "fixpoint: one iteration, single fact delta (identity rule)" (b : @bench.T) {
  let rt = @incr.Runtime::Runtime()
  let rel : @incr.Relation[Int] = @incr.Relation::Relation(rt, label="R")
  let derived : @incr.Relation[Int] = @incr.Relation::Relation(rt, label="D")
  let _ = rt.new_rule([rel.id()], [derived.id()], () => {
    for d in rel.delta_iter() {
      derived.insert(d) |> ignore
    }
  })
  let mut v = 0
  b.bench(fn() {
    v = v + 1
    rel.insert(v) |> ignore
    rt.fixpoint()
  })
}

///|
/// Diagnostic: is the 100-disposed-reactives cost (24 µs) caused by something
/// proportional to disposed-cell count? Compare set-with-no-reactives-ever-created
/// vs set-with-100-disposed. If the disposed setup is much slower, work scales
/// with disposed SoA entries somehow (free-list? cell_index iteration?).
test "diagnostic: input set with cold runtime (no reactives ever created)" (
  b : @bench.T,
) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
}

///|
/// Diagnostic: input set with 100 disposed REACTIVES on a SEPARATE input.
/// If this matches the 100-disposed bench, the cost is global (SoA-size driven).
/// If it matches the cold runtime, the cost is from sig's own state.
test "diagnostic: input set with 100 disposed reactives on separate input" (
  b : @bench.T,
) {
  let rt = Runtime::Runtime()
  let sig_a = Input::Input(rt, 0)
  let sig_b = Input::Input(rt, 0)
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    let r = @incr.EagerDerived::EagerDerived(rt, fn() { sig_b.get() + idx })
    r.dispose()
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig_a.set(v)
  })
}

///|
/// push-engine link-list port investigation — N=500 fanout, steady-state set.
///
/// One input with N=500 reactives. Each set walks the input's subscriber
/// HashSet once (alien-inputs Link-list candidate site #1: replace HashSet
/// iter with intrusive linked-list traversal). Per-iter cost = ~N hashset-iter
/// steps + N compute invocations + N priority-queue ops + N
/// diff_and_update_subscribers calls (1-element new_seen each).
test "linklist-port: fanout 500 reactives, steady-state set" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let reactives : Array[@incr.EagerDerived[Int]] = []
  for i = 0; i < 500; i = i + 1 {
    let idx = i
    reactives.push(@incr.EagerDerived::EagerDerived(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
  ignore(reactives)
}

///|
/// push-engine link-list port investigation — N=1000 fanout (Vue 3.6 driver).
///
/// Scales the steady-state fanout bench to match alien-inputs' reference
/// benchmark size. If per-iter cost scales linearly with N (vs. 100-baseline),
/// the inner loop is dominated by per-subscriber work — Link-list port has
/// headroom. If it grows superlinearly, hash collisions / resize / GC pressure
/// are also implicated.
test "linklist-port: fanout 1000 reactives, steady-state set" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let reactives : Array[@incr.EagerDerived[Int]] = []
  for i = 0; i < 1000; i = i + 1 {
    let idx = i
    reactives.push(@incr.EagerDerived::EagerDerived(rt, fn() { sig.get() + idx }))
  }
  let mut v = 0
  b.bench(fn() {
    v += 1
    sig.set(v)
  })
  ignore(reactives)
}

///|
/// push-engine link-list port investigation — branchy-rebind, N=100.
///
/// Each reactive picks between two inputs based on a toggling flag, so every
/// iteration N reactives churn their source set. This is the
/// diff_and_update_subscribers (subscriber_diff.mbt) hot path: HashSet
/// contains/add/remove_and_check on every dep diff. Link-list candidate
/// site #2 — but the cost shares with propagate_liveness, which is
/// independent of the Link-list change.
test "linklist-port: branchy-rebind 100 reactives" (b : @bench.T) {
  let rt = Runtime::Runtime()
  let sig_a = Input::Input(rt, 0)
  let sig_b = Input::Input(rt, 1)
  let flag = Input::Input(rt, true)
  let reactives : Array[@incr.EagerDerived[Int]] = []
  for i = 0; i < 100; i = i + 1 {
    let idx = i
    reactives.push(
      @incr.EagerDerived::EagerDerived(rt, fn() {
        if flag.get() {
          sig_a.get() + idx
        } else {
          sig_b.get() + idx
        }
      }),
    )
  }
  let mut toggle = true
  b.bench(fn() {
    toggle = !toggle
    flag.set(toggle)
  })
  ignore(reactives)
}
