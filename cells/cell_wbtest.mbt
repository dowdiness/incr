///|
// CellId::hash must be non-commutative: swapping runtime_id and id should
// produce different hashes, preventing spurious collisions in HashSet[CellId]
// when multiple runtimes share the same cell index space.
test "CellId::hash is non-commutative" {
  let a = CellId::{ runtime_id: 1, id: 2 }
  let b = CellId::{ runtime_id: 2, id: 1 }
  inspect(a.hash() == b.hash(), content="false")
}

///|
// Sanity check: equal CellIds must produce equal hashes (Hash law).
test "CellId::hash equal inputs produce equal hashes" {
  let a = CellId::{ runtime_id: 3, id: 7 }
  let b = CellId::{ runtime_id: 3, id: 7 }
  inspect(a.hash() == b.hash(), content="true")
}

///|
test "signal label stored in PullSignalData" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0, label="my_signal")
  let data = rt.get_pull_signal(sig.id())
  inspect(data.label, content="Some(\"my_signal\")")
}

///|
test "signal None label stored in PullSignalData" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let data = rt.get_pull_signal(sig.id())
  inspect(data.label, content="None")
}
