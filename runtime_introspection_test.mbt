///|
test "runtime: cell_info() returns metadata for signal" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42, durability=High)

  match rt.cell_info(sig.id()) {
    Some(info) => {
      inspect(info.id == sig.id(), content="true")
      inspect(info.durability, content="High")
      inspect(info.dependencies, content="[]")
    }
    None => abort("Expected Some(info)")
  }
}

///|
test "runtime: cell_info() returns metadata for memo" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 10)
  x.set(20) // Bump revision to 1
  let doubled = Memo::new(rt, fn() { x.get() * 2 })

  doubled.get() |> ignore

  match rt.cell_info(doubled.id()) {
    Some(info) => {
      inspect(info.id == doubled.id(), content="true")
      inspect(info.dependencies.contains(x.id()), content="true")
      inspect(info.changed_at.value > 0, content="true")
      inspect(info.verified_at.value > 0, content="true")
    }
    None => abort("Expected Some(info)")
  }
}

///|
test "runtime: cell_info() returns None for out-of-bounds CellId" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  let invalid_id : CellId = { runtime_id: sig.id().runtime_id, id: 999 }

  match rt.cell_info(invalid_id) {
    Some(_) => abort("Expected None for invalid ID")
    None => ()
  }
}

///|
test "runtime: cell_info() returns None for unused slot" {
  let rt = Runtime::new()
  // Create and verify we have at least one cell
  let sig = Signal::new(rt, 1)

  // Try to access a slot far beyond what's been allocated
  let beyond_id : CellId = { runtime_id: sig.id().runtime_id, id: 1000 }

  match rt.cell_info(beyond_id) {
    Some(_) => abort("Expected None for unused slot")
    None => ()
  }
}

///|
test "runtime: cell_info() returns None for negative CellId" {
  let rt = Runtime::new()
  // Create a cell to ensure runtime has some cells
  let sig = Signal::new(rt, 42)

  // Try to access with negative CellId
  let negative_id : CellId = { runtime_id: sig.id().runtime_id, id: -1 }

  match rt.cell_info(negative_id) {
    Some(_) => abort("Expected None for negative CellId")
    None => ()
  }
}

///|
test "runtime: cell_info() returns None for CellId from different runtime" {
  let rt1 = Runtime::new()
  let rt2 = Runtime::new()

  // Create a signal in rt1
  let sig1 = Signal::new(rt1, 100)

  // Also create a signal in rt2 (will have same numeric ID but different runtime_id)
  let sig2 = Signal::new(rt2, 200)

  // Querying rt1's cell ID against rt2 should return None
  match rt2.cell_info(sig1.id()) {
    Some(_) => abort("Expected None for CellId from different runtime")
    None => ()
  }

  // Querying rt2's cell ID against rt1 should return None
  match rt1.cell_info(sig2.id()) {
    Some(_) => abort("Expected None for CellId from different runtime")
    None => ()
  }

  // Querying each runtime with its own cell ID should work
  match rt1.cell_info(sig1.id()) {
    Some(info) => inspect(info.id == sig1.id(), content="true")
    None => abort("Expected Some for CellId from same runtime")
  }

  match rt2.cell_info(sig2.id()) {
    Some(info) => inspect(info.id == sig2.id(), content="true")
    None => abort("Expected Some for CellId from same runtime")
  }
}
