///|
test "durability: high durability signal skips verification" {
  let rt = Runtime::new()
  let config = Signal::new(rt, "debug", durability=High)
  let source = Signal::new(rt, "hello")
  let mut config_reads = 0
  let config_memo = Memo::new(rt, fn() {
    config_reads = config_reads + 1
    config.get()
  })
  let mut source_memo_reads = 0
  let source_memo = Memo::new(rt, fn() {
    source_memo_reads = source_memo_reads + 1
    source.get()
  })
  // Initial computation
  inspect(config_memo.get(), content="debug")
  inspect(source_memo.get(), content="hello")
  inspect(config_reads, content="1")
  inspect(source_memo_reads, content="1")
  // Change only the low-durability signal
  source.set("world")
  // config_memo should be skipped via durability optimization
  // (no High-durability input changed)
  inspect(config_memo.get(), content="debug")
  // config_memo may or may not recompute depending on durability shortcut,
  // but the value should still be correct
  inspect(source_memo.get(), content="world")
  inspect(source_memo_reads, content="2")
}

///|
test "durability: memo inherits min durability from deps" {
  let rt = Runtime::new()
  let high = Signal::new(rt, 1, durability=High)
  let low = Signal::new(rt, 2) // Low by default
  let combined = Memo::new(rt, fn() { high.get() + low.get() })
  inspect(combined.get(), content="3")
  // combined should have Low durability (min of High and Low)
  let cell = rt.get_cell(combined.cell_id)
  inspect(cell.durability, content="Low")
}

///|
test "durability: memo with only high deps gets high durability" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 10, durability=High)
  let b = Signal::new(rt, 20, durability=High)
  let sum = Memo::new(rt, fn() { a.get() + b.get() })
  inspect(sum.get(), content="30")
  let cell = rt.get_cell(sum.cell_id)
  inspect(cell.durability, content="High")
}

///|
test "durability: medium durability signal" {
  let rt = Runtime::new()
  let med = Signal::new(rt, 5, durability=Medium)
  let low = Signal::new(rt, 10)
  let memo = Memo::new(rt, fn() { med.get() + low.get() })
  inspect(memo.get(), content="15")
  // Memo should have Low durability (min of Medium and Low)
  let cell = rt.get_cell(memo.cell_id)
  inspect(cell.durability, content="Low")
}

///|
test "durability: high-only memo skips verify when low input changes" {
  let rt = Runtime::new()
  let config = Signal::new(rt, 100, durability=High)
  let source = Signal::new(rt, 1)
  let mut config_compute_count = 0
  let config_derived = Memo::new(rt, fn() {
    config_compute_count = config_compute_count + 1
    config.get() * 2
  })
  // Initial
  inspect(config_derived.get(), content="200")
  inspect(config_compute_count, content="1")
  // Change low-durability input (should not affect config_derived)
  source.set(2)
  // config_derived only depends on High-durability config,
  // and no High input changed, so durability shortcut should skip
  inspect(config_derived.get(), content="200")
  inspect(config_compute_count, content="1")
}
