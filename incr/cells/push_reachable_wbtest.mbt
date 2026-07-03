///|
test "push_reachable_count: new input starts at 0" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let idx = match rt.core.cell_index[s.id().id] {
    PullInput(i) => i
    _ => abort("expected PullInput")
  }
  inspect(rt.pull.inputs[idx].meta.push_reachable_count, content="0")
}

///|
/// Helper: read push_reachable_count from any cell via CellOps trait dispatch.
fn get_count(rt : Runtime, id : CellId) -> Int {
  rt.core.cell_ops[id.id].push_reachable_count()
}

///|
test "push_reachable_count: input with direct reactive counts 1" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let _r = EagerDerived::EagerDerived(rt, () => s.get())
  inspect(get_count(rt, s.id()), content="1")
}

///|
test "push_reachable_count: input with reactive through hybrid memo" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let h = ReachableDerived(rt, () => s.get())
  let _r = EagerDerived::EagerDerived(rt, () => h.read_or_abort())
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, h.id()), content="1")
}

///|
test "push_reachable_count: two-deep memo chain" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let mA = Derived(rt, () => s.get())
  let mB = Derived(rt, () => mA.get_or_abort())
  let _r = EagerDerived::EagerDerived(rt, () => mB.read_or_abort())
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, mA.id()), content="1")
  inspect(get_count(rt, mB.id()), content="1")
}

///|
test "push_reachable_count: diamond topology" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let mA = Derived(rt, () => s.get() + 1)
  let mB = Derived(rt, () => s.get() + 2)
  let _r = EagerDerived::EagerDerived(rt, () => mA.read_or_abort() + mB.read_or_abort())
  // Two paths: s->mA->r and s->mB->r
  inspect(get_count(rt, s.id()), content="2")
  inspect(get_count(rt, mA.id()), content="1")
  inspect(get_count(rt, mB.id()), content="1")
}

///|
test "push_reachable_count: reactive dispose returns counts to 0" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let r = EagerDerived::EagerDerived(rt, () => s.get())
  inspect(get_count(rt, s.id()), content="1")
  r.dispose()
  inspect(get_count(rt, s.id()), content="0")
}

///|
test "push_reachable_count: diamond dispose returns to 0" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let mA = Derived(rt, () => s.get() + 1)
  let mB = Derived(rt, () => s.get() + 2)
  let r = EagerDerived::EagerDerived(rt, () => mA.read_or_abort() + mB.read_or_abort())
  inspect(get_count(rt, s.id()), content="2")
  r.dispose()
  inspect(get_count(rt, s.id()), content="0")
  inspect(get_count(rt, mA.id()), content="0")
  inspect(get_count(rt, mB.id()), content="0")
}

///|
test "push_reachable_count: relation-to-reactive" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let mut count = 0
  let r = EagerDerived::EagerDerived(rt, () => {
    count = count + 1
    rel.iter().fold(init=0, fn(acc, x) { acc + x })
  })
  ignore(r) // r is alive
  inspect(get_count(rt, rel.id()), content="1")
  r.dispose()
  inspect(get_count(rt, rel.id()), content="0")
}

///|
test "push_reachable_count: reactive-to-reactive chain" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let r1 = EagerDerived::EagerDerived(rt, () => s.get() + 1)
  let _r2 = EagerDerived::EagerDerived(rt, () => r1.get() + 1)
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, r1.id()), content="1")
}

///|
test "push_reachable_count: effect increments and dispose decrements" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let e = Effect::new(rt, () => ignore(s.get()))
  inspect(get_count(rt, s.id()), content="1")
  e.dispose()
  inspect(get_count(rt, s.id()), content="0")
}

///|
test "push_reachable_count: source change on reactive recompute" {
  let rt = Runtime::Runtime()
  let s1 = Input::Input(rt, 0)
  let s2 = Input::Input(rt, 0)
  // reactive starts reading s1
  let flag : Ref[Bool] = Ref(true)
  let _r = EagerDerived::EagerDerived(rt, () => if flag.val { s1.get() } else { s2.get() })
  inspect(get_count(rt, s1.id()), content="1")
  inspect(get_count(rt, s2.id()), content="0")
  // switch reactive to read s2 by changing flag and triggering recompute
  flag.val = false
  s1.set(1) // triggers push propagation -> r recomputes -> now reads s2
  inspect(get_count(rt, s1.id()), content="0")
  inspect(get_count(rt, s2.id()), content="1")
}

///|
test "push_reachable_count: memo dep change updates upstream input counts" {
  let rt = Runtime::Runtime()
  let s1 = Input::Input(rt, 0)
  let s2 = Input::Input(rt, 0)
  let flag : Ref[Bool] = Ref(true)
  // memoA conditionally reads s1 or s2
  let mA = Derived(rt, () => if flag.val { s1.get() } else { s2.get() })
  // reactive reads memoA (forces memoA to compute -> deps=[s1])
  let _r = EagerDerived::EagerDerived(rt, () => mA.read_or_abort())
  inspect(get_count(rt, s1.id()), content="1")
  inspect(get_count(rt, s2.id()), content="0")
  // switch memoA to read s2: change flag, trigger recompute via input change
  flag.val = false
  s1.set(1) // reactive recomputes -> pull_verify memoA -> memo recomputes -> s2 added
  inspect(get_count(rt, s1.id()), content="0")
  inspect(get_count(rt, s2.id()), content="1")
}

///|
test "push_reachable_count: hybrid memo dispose decrements upstream" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let h = ReachableDerived(rt, () => s.get())
  let _r = EagerDerived::EagerDerived(rt, () => h.read_or_abort())
  inspect(get_count(rt, s.id()), content="1")
  inspect(get_count(rt, h.id()), content="1")
  h.dispose()
  // After h is disposed, s should have count 0
  inspect(get_count(rt, s.id()), content="0")
}

///|
test "push_reachable_count: no push cells = zero everywhere" {
  let rt = Runtime::Runtime()
  let s = Input::Input(rt, 0)
  let _m = Derived(rt, () => s.get())
  inspect(get_count(rt, s.id()), content="0")
}

///|
/// Regression: a memo-INTERNAL diamond where one intermediate memo reads three
/// sibling memos that share a common ancestor `sig`, then drops one arm via a
/// dynamic dependency. Dropping the `c` arm must decrement the apex by exactly
/// one (3 -> 2), not zero it — the `a` and `b` arms still connect `sig` to the
/// fold. The old deduped "mass" model wrongly drove the apex to 0, after which
/// the push BFS O(1) gate (push_propagate.mbt) skipped the whole propagation and
/// the eager fold stopped recomputing on `sig` changes.
test "push_reachable_count: dropping one arm of a memo-internal diamond keeps the apex live" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let drop = Input::Input(rt, false)
  let a = Derived(rt, () => sig.get())
  let b = Derived(rt, () => sig.get())
  let c = Derived(rt, () => sig.get())
  // projected reads a,b always; reads c only when !drop (dynamic dependency).
  let projected = Derived(rt, () => {
    let base = a.get_or_abort() + b.get_or_abort()
    if drop.get() {
      base
    } else {
      base + c.get_or_abort()
    }
  })
  let candidate = Derived(rt, () => projected.get_or_abort())
  let runs : Ref[Int] = { val: 0 }
  // EagerDerived::EagerDerived computes eagerly, wiring the whole chain. Keep
  // it alive (no observe/unobserve cycle, which would suspend it).
  let fold = EagerDerived::EagerDerived(rt, () => {
    runs.val = runs.val + 1
    candidate.read_or_abort()
  })
  inspect(runs.val, content="1")
  // Three live direct subscribers of sig (a, b, c each reach the fold).
  inspect(get_count(rt, sig.id()), content="3")
  drop.set(true)
  let runs_after_drop = runs.val
  // c arm dropped; a and b remain, so the apex drops by one and stays live.
  inspect(get_count(rt, sig.id()), content="2")
  // The eager fold must still recompute on a sig change.
  sig.set(2)
  inspect(runs.val > runs_after_drop, content="true")
  ignore(fold)
}

///|
test "gate: input with count 0 does not trigger reactive on separate input" {
  let rt = Runtime::Runtime()
  let s1 = Input::Input(rt, 0)
  let s2 = Input::Input(rt, 0)
  let mut recomputes = 0
  let _r = EagerDerived::EagerDerived(rt, () => {
    recomputes = recomputes + 1
    s2.get()
  })
  let initial = recomputes
  // s1 has no downstream push cells (r reads s2, not s1)
  inspect(get_count(rt, s1.id()), content="0")
  // Changing s1 should NOT trigger r to recompute
  s1.set(1)
  inspect(recomputes, content=initial.to_string())
}

///|
/// Inner BFS pruning correctness proxy:
/// After reactive2 is disposed, memoB.count == 0. The live branch (memoA -> r1)
/// must still propagate correctly when sig changes.
test "push_reachable_count: inner pruning — live branch still fires after dead branch count reaches 0" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let mA = Derived(rt, () => sig.get() + 1)
  let mB = Derived(rt, () => sig.get() + 2)
  let mut r1_val = 0
  let r1 = EagerDerived::EagerDerived(rt, () => {
    r1_val = mA.read_or_abort()
    r1_val
  })
  let r2 = EagerDerived::EagerDerived(rt, () => mB.read_or_abort())
  inspect(get_count(rt, sig.id()), content="2")
  inspect(get_count(rt, mB.id()), content="1")
  r2.dispose()
  inspect(get_count(rt, mB.id()), content="0")
  inspect(get_count(rt, sig.id()), content="1")
  // The live branch must still work after the dead branch is pruned
  sig.set(10)
  inspect(r1_val, content="11") // mA.get() = sig.get() + 1 = 11
  ignore(r1)
}
