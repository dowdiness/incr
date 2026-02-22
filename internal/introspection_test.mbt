// Signal introspection

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

// Memo introspection

///|
test "memo: id() returns valid CellId" {
  let rt = Runtime::new()
  let m = Memo::new(rt, fn() { 42 })
  let id = m.id()
  inspect(id.id >= 0, content="true")
}

///|
test "memo: dependencies() returns empty before computation" {
  let rt = Runtime::new()
  let m = Memo::new(rt, fn() { 10 })
  inspect(m.dependencies(), content="[]")
}

///|
test "memo: dependencies() includes all inputs after computation" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let y = Signal::new(rt, 2)
  let sum = Memo::new(rt, fn() { x.get() + y.get() })

  sum.get() |> ignore
  let deps = sum.dependencies()
  inspect(deps.length(), content="2")
  inspect(deps.contains(x.id()), content="true")
  inspect(deps.contains(y.id()), content="true")
}

///|
test "memo: changed_at and verified_at track revisions" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 5)
  x.set(10) // Bump revision to 1
  let doubled = Memo::new(rt, fn() { x.get() * 2 })

  doubled.get() |> ignore
  let initial_changed = doubled.changed_at()
  let initial_verified = doubled.verified_at()

  inspect(initial_changed.value > 0, content="true")
  inspect(initial_verified.value > 0, content="true")

  // Change input
  x.set(20)
  doubled.get() |> ignore

  inspect(doubled.changed_at().value > initial_changed.value, content="true")
  inspect(doubled.verified_at().value > initial_verified.value, content="true")
}

///|
test "memo: dependencies update on recomputation" {
  let rt = Runtime::new()
  let cond = Signal::new(rt, true)
  let a = Signal::new(rt, 1)
  let b = Signal::new(rt, 2)

  let dynamic = Memo::new(rt, fn() {
    if cond.get() {
      a.get()
    } else {
      b.get()
    }
  })

  dynamic.get() |> ignore
  let deps1 = dynamic.dependencies()
  inspect(deps1.contains(a.id()), content="true")
  inspect(deps1.contains(b.id()), content="false")

  cond.set(false)
  dynamic.get() |> ignore
  let deps2 = dynamic.dependencies()
  inspect(deps2.contains(a.id()), content="false")
  inspect(deps2.contains(b.id()), content="true")
}

///|
test "memo: label stored via optional param" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { x.get() * 2 }, label="doubled")
  let _ = m.get()
  match rt.cell_info(m.id()) {
    Some(info) => inspect(info.label, content="Some(\"doubled\")")
    None => abort("expected cell info")
  }
}

///|
test "memo: no label gives None in cell_info" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let m = Memo::new(rt, fn() { x.get() * 2 })
  let _ = m.get()
  match rt.cell_info(m.id()) {
    Some(info) => inspect(info.label, content="None")
    None => abort("expected cell info")
  }
}

// Runtime cell_info

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
  let sig = Signal::new(rt, 1)
  let beyond_id : CellId = { runtime_id: sig.id().runtime_id, id: 1000 }

  match rt.cell_info(beyond_id) {
    Some(_) => abort("Expected None for unused slot")
    None => ()
  }
}

///|
test "runtime: cell_info() returns None for negative CellId" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
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

  let sig1 = Signal::new(rt1, 100)
  let sig2 = Signal::new(rt2, 200)

  match rt2.cell_info(sig1.id()) {
    Some(_) => abort("Expected None for CellId from different runtime")
    None => ()
  }

  match rt1.cell_info(sig2.id()) {
    Some(_) => abort("Expected None for CellId from different runtime")
    None => ()
  }

  match rt1.cell_info(sig1.id()) {
    Some(info) => inspect(info.id == sig1.id(), content="true")
    None => abort("Expected Some for CellId from same runtime")
  }

  match rt2.cell_info(sig2.id()) {
    Some(info) => inspect(info.id == sig2.id(), content="true")
    None => abort("Expected Some for CellId from same runtime")
  }
}

// Integration: introspection with real computation patterns

///|
test "integration: debug why memo recomputed" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 10)
  let y = Signal::new(rt, 20)
  let sum = Memo::new(rt, fn() { x.get() + y.get() })

  sum.get() |> ignore
  let initial_verified = sum.verified_at()

  // Same value - backdating means no effective change
  x.set(10)
  sum.get() |> ignore
  inspect(sum.verified_at() == initial_verified, content="true")

  // Different value - should trigger recomputation
  y.set(30)
  sum.get() |> ignore
  inspect(sum.verified_at().value > initial_verified.value, content="true")

  // Identify which dependency caused recomputation
  let mut found_culprit = false
  for dep_id in sum.dependencies() {
    match rt.cell_info(dep_id) {
      Some(info) =>
        if info.changed_at.value > initial_verified.value {
          inspect(dep_id == y.id(), content="true")
          found_culprit = true
        }
      None => ()
    }
  }
  inspect(found_culprit, content="true")
}

///|
test "integration: analyze dependency chain" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 5)
  let step1 = Memo::new(rt, fn() { input.get() * 2 })
  let step2 = Memo::new(rt, fn() { step1.get() + 10 })
  let step3 = Memo::new(rt, fn() { step2.get() * 3 })

  step3.get() |> ignore

  inspect(step3.dependencies().contains(step2.id()), content="true")
  inspect(step2.dependencies().contains(step1.id()), content="true")
  inspect(step1.dependencies().contains(input.id()), content="true")

  // No cross-dependencies
  inspect(step3.dependencies().contains(input.id()), content="false")
  inspect(step3.dependencies().contains(step1.id()), content="false")
}

///|
test "integration: diamond dependency has no duplicates" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 10)
  let left = Memo::new(rt, fn() { input.get() + 1 })
  let right = Memo::new(rt, fn() { input.get() + 2 })
  let merge = Memo::new(rt, fn() { left.get() + right.get() })

  merge.get() |> ignore

  let merge_deps = merge.dependencies()
  inspect(merge_deps.contains(left.id()), content="true")
  inspect(merge_deps.contains(right.id()), content="true")

  // Input appears exactly once in each branch's dependencies
  let mut input_count_left = 0
  for dep in left.dependencies() {
    if dep == input.id() {
      input_count_left = input_count_left + 1
    }
  }
  inspect(input_count_left, content="1")

  let mut input_count_right = 0
  for dep in right.dependencies() {
    if dep == input.id() {
      input_count_right = input_count_right + 1
    }
  }
  inspect(input_count_right, content="1")
}

///|
test "integration: understanding backdating with introspection" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 5)
  let abs_value = Memo::new(rt, fn() {
    let val = input.get()
    if val < 0 {
      -val
    } else {
      val
    }
  })

  abs_value.get() |> ignore
  let old_changed_at = abs_value.changed_at()
  let old_verified_at = abs_value.verified_at()

  // Change input from 5 to -5: different input, same output (5)
  input.set(-5)
  abs_value.get() |> ignore

  // Backdating: changed_at didn't advance because output is still 5
  inspect(abs_value.changed_at() == old_changed_at, content="true")

  // But verified_at did advance
  inspect(abs_value.verified_at().value > old_verified_at.value, content="true")
}
