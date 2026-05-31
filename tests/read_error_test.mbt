// Tier 2 of the honest read-error migration: the read channel carries
// `ReadError = Cycle | Disposed`. A read of a *directly disposed* cell returns
// `Err(Disposed(_))` instead of an uncatchable abort; a cycle surfaces as
// `Err(Cycle(_))`. A retained compute `raise Failure` stays a defect (abort).
// Spec: docs/design/specs/2026-05-28-honest-read-error-ownership.md (Tier 2).

///|
test "Derived::read on a disposed cell returns Err(Disposed) instead of aborting" {
  let rt = @incr.Runtime::new()
  let x = @incr.Input(rt, 1, label="x")
  let scope = @incr.Scope::new(rt)
  let d = scope.derived(() => x.get() + 1, label="d")
  guard d.read() is Ok(2) else { fail("expected Ok(2) before disposal") }
  // Dispose the cell directly (scope owns d's underlying memo).
  scope.dispose()
  guard d.read() is Err(e) else { fail("expected Err on disposed read") }
  guard e.is_disposed() else { fail("expected Err(Disposed), got \{e}") }
}

///|
test "Derived::get inside a compute surfaces a self-cycle as Err(Cycle(_))" {
  let rt = @incr.Runtime::new()
  let saw_cycle : Ref[Bool] = { val: false }
  let self_ref : Ref[@incr.Derived[Int]?] = { val: None }
  let d = @incr.Derived(rt, () => {
    match self_ref.val {
      Some(s) =>
        match s.get() {
          Ok(v) => v + 1
          Err(e) =>
            if e.is_cycle() {
              saw_cycle.val = true
              -999
            } else {
              -1
            }
        }
      None => 0
    }
  })
  self_ref.val = Some(d)
  guard d.read_or_abort() == -999 else {
    fail("expected handled self-cycle sentinel -999")
  }
  guard saw_cycle.val else {
    fail("expected Derived::get to return Err(Cycle(_))")
  }
}

///|
test "ReachableDerived::read on a disposed cell returns Err(Disposed)" {
  let rt = @incr.Runtime::new()
  let x = @incr.Input(rt, 3, label="x")
  let scope = @incr.Scope::new(rt)
  let r = scope.reachable_derived(() => x.get() * 2, label="r")
  guard r.read() is Ok(6) else { fail("expected Ok(6) before disposal") }
  scope.dispose()
  guard r.read() is Err(e) else { fail("expected Err on disposed read") }
  guard e.is_disposed() else { fail("expected Err(Disposed), got \{e}") }
}

///|
test "Watch::read on a disposed cell returns Err(Disposed)" {
  let rt = @incr.Runtime::new()
  let x = @incr.Input(rt, 4, label="x")
  let scope = @incr.Scope::new(rt)
  let d = scope.derived(() => x.get() + 10, label="d")
  let w = d.watch()
  guard w.read() is Ok(14) else { fail("expected Ok(14) before disposal") }
  scope.dispose()
  guard w.read() is Err(e) else { fail("expected Err on disposed watch read") }
  guard e.is_disposed() else { fail("expected Err(Disposed), got \{e}") }
}

///|
test "Watch on a disposed EagerDerived returns Err(Disposed)" {
  // EagerDerived has no cycle/raise channel, but its Watch is uniformly honest
  // about disposal: a read after disposal returns Err(Disposed), not an abort.
  let rt = @incr.Runtime::new()
  let x = @incr.Input(rt, 7, label="x")
  let scope = @incr.Scope::new(rt)
  let e = scope.eager_derived(() => x.get() + 1)
  let w = e.watch()
  guard w.read() is Ok(8) else { fail("expected Ok(8) before disposal") }
  scope.dispose()
  guard w.read() is Err(err) else {
    fail("expected Err on disposed eager watch read")
  }
  guard err.is_disposed() else { fail("expected Err(Disposed), got \{err}") }
}

///|
test "DerivedMap::read on a gc-disposed per-key memo returns Err(Disposed)" {
  let rt = @incr.Runtime::new()
  let src = @incr.Input(rt, 100, label="src")
  let m = @incr.DerivedMap(rt, (k : Int) => src.get() + k, label="m")
  guard m.read(1) is Ok(101) else { fail("expected Ok(101)") }
  // The per-key memo has no persistent anchor, so gc disposes it while the
  // map still caches the (now disposed) entry.
  rt.gc()
  guard m.read(1) is Err(e) else {
    fail("expected Err on gc-disposed key read")
  }
  guard e.is_disposed() else { fail("expected Err(Disposed), got \{e}") }
}
