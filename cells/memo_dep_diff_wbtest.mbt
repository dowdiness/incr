///|
// When a memo has stable dependencies (same cells read every recompute),
// its durability must be preserved correctly across multiple recomputations.
test "dep diff: stable deps preserve durability" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 1, durability=High)
  let m = Memo::new(rt, () => a.get() + 1)
  let _ = m.get()
  let meta = rt.get_cell(m.id())
  inspect(meta.durability, content="High")
  // a changes value but dep list stays [a] — durability must stay High
  a.set(2)
  let _ = m.get()
  inspect(meta.durability, content="High")
  inspect(meta.dependencies.length(), content="1")
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
  let meta = rt.get_cell(m.id())
  inspect(meta.durability, content="High")
  inspect(meta.dependencies.length(), content="2")
  // Switch: reads flag(High) and b(Low) → min durability = Low
  flag.set(false)
  let _ = m.get()
  inspect(meta.durability, content="Low")
  inspect(meta.dependencies.length(), content="2")
}
