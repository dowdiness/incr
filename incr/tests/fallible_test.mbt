// Tier 1 of the honest read-error migration: a fallible memo expresses a
// domain failure as a *value* (`Result[V, E]`), never as an uncatchable abort.
// Spec: docs/design/specs/2026-05-28-honest-read-error-ownership.md

///|
test "Derived::fallible surfaces domain failure as a cached value, never aborts" {
  let rt = @incr.Runtime()
  let n = @incr.Input(rt, 0, label="n")
  let d : @incr.Derived[Result[Int, String]] = @incr.Derived::fallible(rt, () => {
    let v = n.get()
    if v < 0 {
      Err("negative")
    } else {
      Ok(v * 2)
    }
  })
  guard d.read() is Ok(Ok(0)) else { fail("expected Ok(Ok(0))") }
  n.set(5)
  guard d.read() is Ok(Ok(10)) else { fail("expected Ok(Ok(10)) after set(5)") }
  // Domain failure surfaces as a value (Ok(Err(_))) — not an uncatchable abort.
  n.set(-1)
  guard d.read() is Ok(Err("negative")) else {
    fail("expected Ok(Err(\"negative\")) after set(-1)")
  }
  // Recovery: flipping back to a valid input invalidates and recomputes,
  // proving the Err value is change-detected like any other value.
  n.set(2)
  guard d.read() is Ok(Ok(4)) else { fail("expected Ok(Ok(4)) after recovery") }
}

///|
test "DerivedMap::fallible surfaces per-key domain failure as a value" {
  let rt = @incr.Runtime()
  let m : @incr.DerivedMap[Int, Result[Int, String]] = @incr.DerivedMap::fallible(
    rt,
    k => if k < 0 { Err("neg key") } else { Ok(k * 10) },
  )
  guard m.read(3) is Ok(Ok(30)) else { fail("expected Ok(Ok(30))") }
  guard m.read(-2) is Ok(Err("neg key")) else {
    fail("expected Ok(Err(\"neg key\"))")
  }
}
