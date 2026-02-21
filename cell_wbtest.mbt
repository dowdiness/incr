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
