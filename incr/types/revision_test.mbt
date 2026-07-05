///|
test "revision monotonicity: next strictly increases" {
  let r0 = Revision::initial()
  let r1 = r0.next()
  let r2 = r1.next()
  inspect(r0 < r1, content="true")
  inspect(r1 < r2, content="true")
  inspect(r0 == r0.next(), content="false")
}

///|
test "revision field stays readable cross-package" {
  // `Revision` is `pub` (not `pub(all)`): construction is confined to the
  // defining package, but field reads from consumers must keep compiling.
  let r = Revision::initial()
  inspect(r.value, content="0")
  inspect(r.next().value, content="1")
}
