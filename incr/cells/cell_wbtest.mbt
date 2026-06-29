///|
// CellId::hash must be non-commutative: swapping runtime_id and id should
// produce different hashes, preventing spurious collisions in HashSet[CellId]
// when multiple runtimes share the same cell index space.
test "CellId::hash is non-commutative" {
  let a = CellId::{ runtime_id: @incr_types.RuntimeId(1), id: 2 }
  let b = CellId::{ runtime_id: @incr_types.RuntimeId(2), id: 1 }
  debug_inspect(a.hash() == b.hash(), content="false")
}

///|
// Sanity check: equal CellIds must produce equal hashes (Hash law).
test "CellId::hash equal inputs produce equal hashes" {
  let a = CellId::{ runtime_id: @incr_types.RuntimeId(3), id: 7 }
  let b = CellId::{ runtime_id: @incr_types.RuntimeId(3), id: 7 }
  inspect(a.hash() == b.hash(), content="true")
}

///|
test "input label stored in PullInputData" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0, label="my_input")
  let data = rt.get_pull_input(sig.id())
  debug_inspect(
    data.meta.label,
    content=(
      "Some(\"my_input\")"
    ),
  )
}

///|
test "input None label stored in PullInputData" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let data = rt.get_pull_input(sig.id())
  debug_inspect(data.meta.label, content="None")
}
