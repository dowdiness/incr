///|
test "runtime: cell_info() returns metadata for signal" {
  let rt = Runtime::new()
  let sig = Signal::new_with_durability(rt, 42, High)

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
  x.set(20)  // Bump revision to 1
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
  let invalid_id : CellId = { id: 999 }

  match rt.cell_info(invalid_id) {
    Some(_) => abort("Expected None for invalid ID")
    None => ()
  }
}

///|
test "runtime: cell_info() returns None for unused slot" {
  let rt = Runtime::new()
  // Create and verify we have at least one cell
  let _sig = Signal::new(rt, 1)

  // Try to access a slot far beyond what's been allocated
  let beyond_id : CellId = { id: 1000 }

  match rt.cell_info(beyond_id) {
    Some(_) => abort("Expected None for unused slot")
    None => ()
  }
}
