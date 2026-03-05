///|
test "runtime: push arrays start empty" {
  let rt = Runtime::new()
  inspect(rt.push_reactives.length(), content="0")
  inspect(rt.push_effects.length(), content="0")
  inspect(rt.free_push_reactives.length(), content="0")
  inspect(rt.free_push_effects.length(), content="0")
}

///|
test "cell_ref: PushReactive, PushEffect, Disposed variants exist" {
  let a : CellRef = CellRef::PushReactive(0)
  let b : CellRef = CellRef::PushEffect(2)
  let c : CellRef = CellRef::Disposed
  let ia = match a { PushReactive(i) => i; _ => -1 }
  let ib = match b { PushEffect(i) => i; _ => -1 }
  let ok = match c { Disposed => true; _ => false }
  inspect(ia, content="0")
  inspect(ib, content="2")
  inspect(ok, content="true")
}
