///|
// When a memo has stable dependencies (same cells read every recompute),
// its durability must be preserved correctly across multiple recomputations.
test "dep diff: stable deps preserve durability" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1, durability=High)
  let m = Memo::new(rt, () => a.get() + 1)
  let _ = m.get()
  let memo_data = rt.get_memo_data(m.id())
  inspect(memo_data.meta.durability, content="High")
  // a changes value but dep list stays [a] — durability must stay High
  a.set(2)
  let _ = m.get()
  inspect(memo_data.meta.durability, content="High")
  inspect(memo_data.dependencies.length(), content="1")
}

///|
// When a conditional memo switches which signal it reads, the dependency
// list and durability must both reflect the new set of dependencies.
test "dep diff: dynamic deps update dep list and durability" {
  let rt = Runtime::new()
  let flag = Signal::new(rt, true, durability=High)
  let a = Signal::new(rt, 1, durability=High)
  let b = Signal::new(rt, 2, durability=Low)
  let m = Memo::new(rt, () => if flag.get() { a.get() } else { b.get() })
  // Initial: reads flag(High) and a(High) → min durability = High
  let _ = m.get()
  let memo_data = rt.get_memo_data(m.id())
  inspect(memo_data.meta.durability, content="High")
  inspect(memo_data.dependencies.length(), content="2")
  // Switch: reads flag(High) and b(Low) → min durability = Low
  flag.set(false)
  let _ = m.get()
  inspect(memo_data.meta.durability, content="Low")
  inspect(memo_data.dependencies.length(), content="2")
}
