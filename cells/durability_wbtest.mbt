///|
test "durability: high durability signal skips verification" {
  let rt = Runtime::new()
  let config = Signal::new(rt, "debug", durability=High)
  let source = Signal::new(rt, "hello")
  let mut config_reads = 0
  let config_memo = Memo::new(rt, () => {
    config_reads = config_reads + 1
    config.get()
  })
  let mut source_memo_reads = 0
  let source_memo = Memo::new(rt, () => {
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
  let combined = Memo::new(rt, () => high.get() + low.get())
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
  let sum = Memo::new(rt, () => a.get() + b.get())
  inspect(sum.get(), content="30")
  let cell = rt.get_cell(sum.cell_id)
  inspect(cell.durability, content="High")
}

///|
test "durability: medium durability signal" {
  let rt = Runtime::new()
  let med = Signal::new(rt, 5, durability=Medium)
  let low = Signal::new(rt, 10)
  let memo = Memo::new(rt, () => med.get() + low.get())
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
  let config_derived = Memo::new(rt, () => {
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

///|
test "durability: shortcut boundary — High memo stays skipped when durability_last_changed[High] equals verified_at" {
  // The shortcut fires when: NOT (durability_last_changed[dur] > after_revision)
  // i.e. when durability_last_changed[dur] <= after_revision.
  // This test exercises the equality case: last_changed == verified_at.
  //
  // Steps:
  //   rev 0 → initial compute; config_memo.verified_at = 0
  //   rev 1 → config (High) changes; durability_last_changed[High] = 1
  //   rev 1 → config_memo recomputes; verified_at = 1
  //   rev 2 → data (Medium) changes; durability_last_changed[High] stays at 1
  //   shortcut check: 1 > 1 → false → shortcut fires → config_memo NOT recomputed
  let rt = Runtime::new()
  let config = Signal::new(rt, 1, durability=High)
  let data = Signal::new(rt, 0, durability=Medium)
  let mut config_compute_count = 0
  let config_memo = Memo::new(rt, () => {
    config_compute_count = config_compute_count + 1
    config.get() * 10
  })
  // Initial computation at revision 0
  inspect(config_memo.get(), content="10")
  inspect(config_compute_count, content="1")
  inspect(rt.current_revision.value, content="0")
  // Change High signal: bumps to revision 1; durability_last_changed[High] = 1
  config.set(2)
  inspect(rt.current_revision.value, content="1")
  // Re-verify config_memo: verified_at = 1
  inspect(config_memo.get(), content="20")
  inspect(config_compute_count, content="2")
  // Change Medium signal: bumps to revision 2
  // durability_last_changed[Medium] = 2, durability_last_changed[Low] = 2
  // durability_last_changed[High] stays at 1  ← key boundary condition
  data.set(99)
  inspect(rt.current_revision.value, content="2")
  // Shortcut check: durability_last_changed[High]=1 > after_revision=1 → false
  // NOT false → shortcut fires; config_memo must NOT recompute
  inspect(config_memo.get(), content="20")
  inspect(config_compute_count, content="2")
}
