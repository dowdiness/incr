///|
test "signal: id() returns valid CellId" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let id = sig.id()
  inspect(id.id >= 0, content="true")
}

///|
test "signal: durability() returns construction durability" {
  let rt = Runtime::new()
  let low_sig = Signal::new(rt, 1)
  let high_sig = Signal::new(rt, 2, durability=High)

  inspect(low_sig.durability(), content="Low")
  inspect(high_sig.durability(), content="High")
}

///|
test "signal: multiple signals have distinct IDs" {
  let rt = Runtime::new()
  let a = Signal::new(rt, 10)
  let b = Signal::new(rt, 20)

  inspect(a.id() != b.id(), content="true")
}

///|
test "signal: label stored via optional param" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42, label="answer")
  match rt.cell_info(sig.id()) {
    Some(info) => inspect(info.label, content="Some(\"answer\")")
    None => abort("expected cell info")
  }
}

///|
test "signal: durability optional param works" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42, durability=High)
  inspect(sig.durability(), content="High")
}

///|
test "signal: no label gives None in cell_info" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  match rt.cell_info(sig.id()) {
    Some(info) => inspect(info.label, content="None")
    None => abort("expected cell info")
  }
}
