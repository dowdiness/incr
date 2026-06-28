///|
/// Cross-runtime guard regression tests (issue #174).
///
/// `Memo::get_result_inner_impl` is reached by *direct* read paths
/// (`read_permissive`, `MemoMap::read_honest` / `DerivedMap::read`) that bypass
/// the strict `check_cross_runtime` pre-check in `read_honest_impl`. The repair
/// branch there must clear only a stale *own-runtime* sentinel; a *foreign*
/// sentinel — a cell read inside an active computation on another runtime — must
/// abort, regardless of the read cell's (empty) tracking stack.

///|
test "panic cross-runtime: read_permissive of a foreign cell aborts inside an active compute" {
  // rt_a is actively computing (sentinel = A, A's stack non-empty). Reading a
  // cell owned by rt_b through the permissive path lands in
  // get_result_inner_impl with rt_b's stack empty — the empty-stack hole. It
  // must abort on the foreign sentinel, not silently clear it and proceed.
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let m_b = Derived(rt_b, () => 42)
  let m_a = Derived(rt_a, () => m_b.inner.read_permissive())
  let _ = m_a.inner.read_permissive()
}

///|
test "panic cross-runtime: MemoMap read of a foreign cell aborts inside an active compute" {
  // Same hole via the MemoMap direct read path (DerivedMap::read).
  let rt_a = Runtime::Runtime()
  let rt_b = Runtime::Runtime()
  let map_b : MemoMap[Int, Int] = MemoMap::MemoMap(rt_b, k => k + 1)
  let m_a = Derived(rt_a, () => {
    ignore(map_b.read_honest(0))
    0
  })
  let _ = m_a.inner.read_permissive()
}

///|
test "cross-runtime repair: stale own-runtime sentinel is cleared, not aborted" {
  // A stale *own-runtime* sentinel (e.g. left by static-derived fixed-dep
  // restore, or a prior aborted compute) with an empty tracking stack must be
  // repaired — cleared and the read allowed to proceed — never aborted.
  let rt = Runtime::Runtime()
  let m = Derived(rt, () => 42)
  let _ = m.inner.read_permissive() // prime: cache the value, leaving the sentinel None
  @kernel.set_current_computing_runtime_id(Some(rt.core.runtime_id))
  let v = m.inner.read_permissive()
  inspect(v, content="42")
  inspect(@kernel.get_current_computing_runtime_id() is None, content="true")
}
