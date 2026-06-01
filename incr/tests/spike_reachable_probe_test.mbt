// Equivalence baseline pinning the finding of ADR 2026-05-30
// (docs/decisions/2026-05-30-reachable-derived-differentiate-or-collapse.md):
// today `Derived` (PullMemo) and `ReachableDerived` (HybridMemo) behave
// identically under a downstream push `Effect` anchor — both stay lazy with no
// anchor, both recompute eagerly with one. The `content=` values encode that
// equivalence. If ADR option (b) is ever commissioned (differentiate
// `ReachableDerived` into a genuine eager-when-reachable memo), the
// `reachable_derived` cases here are the sentinel that must be re-baselined.

///|
test "spike: Derived with no anchor stays lazy after input change" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let a = scope.input(10)
  let recomputes = [0]
  let b = scope.derived(fn() {
    recomputes[0] = recomputes[0] + 1
    a.get() + 1
  })
  let _ = b.read() // force initial compute
  let base = recomputes[0]
  a.set(20)
  // WITHOUT reading b again:
  inspect(b.is_fresh(), content="false")
  inspect(recomputes[0] - base, content="0")
}

///|
test "spike: Derived WITH effect anchor recomputes eagerly on input change" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let a = scope.input(10)
  let recomputes = [0]
  let b = scope.derived(fn() {
    recomputes[0] = recomputes[0] + 1
    a.get() + 1
  })
  let eff_runs = [0]
  let _eff = scope.effect(fn() {
    eff_runs[0] = eff_runs[0] + 1
    let _ = b.read()
  })
  let base_rc = recomputes[0]
  let base_eff = eff_runs[0]
  a.set(20)
  // WITHOUT manually reading b: did the effect re-run and b recompute eagerly?
  inspect(eff_runs[0] - base_eff, content="1")
  inspect(recomputes[0] - base_rc, content="1")
  inspect(b.is_fresh(), content="true")
}

///|
test "spike: ReachableDerived with no anchor stays lazy after input change" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let a = scope.input(10)
  let recomputes = [0]
  let b = scope.reachable_derived(fn() {
    recomputes[0] = recomputes[0] + 1
    a.get() + 1
  })
  let _ = b.read()
  let base = recomputes[0]
  a.set(20)
  inspect(b.is_fresh(), content="false")
  inspect(recomputes[0] - base, content="0")
}

///|
test "spike: ReachableDerived WITH effect anchor recomputes eagerly on input change" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let a = scope.input(10)
  let recomputes = [0]
  let b = scope.reachable_derived(fn() {
    recomputes[0] = recomputes[0] + 1
    a.get() + 1
  })
  let eff_runs = [0]
  let _eff = scope.effect(fn() {
    eff_runs[0] = eff_runs[0] + 1
    let _ = b.read()
  })
  let base_rc = recomputes[0]
  let base_eff = eff_runs[0]
  a.set(20)
  inspect(eff_runs[0] - base_eff, content="1")
  inspect(recomputes[0] - base_rc, content="1")
  inspect(b.is_fresh(), content="true")
}
