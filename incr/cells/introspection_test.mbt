// Input introspection

///|
test "input: id() returns valid CellId" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  let id = sig.id()
  inspect(id.id >= 0, content="true")
}

///|
test "input: durability() returns construction durability" {
  let rt = Runtime::Runtime()
  let low_sig = Input::Input(rt, 1)
  let high_sig = Input::Input(rt, 2, durability=High)

  inspect(low_sig.durability(), content="Low")
  inspect(high_sig.durability(), content="High")
}

///|
test "input: multiple inputs have distinct IDs" {
  let rt = Runtime::Runtime()
  let a = Input::Input(rt, 10)
  let b = Input::Input(rt, 20)

  inspect(a.id() != b.id(), content="true")
}

///|
test "input: label stored via optional param" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42, label="answer")
  match rt.cell_info(sig.id()) {
    Some(info) =>
      debug_inspect(
        info.label,
        content=(
          #|Some("answer")
        ),
      )
    None => abort("expected cell info")
  }
}

///|
test "input: durability optional param works" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42, durability=High)
  inspect(sig.durability(), content="High")
}

///|
test "input: no label gives None in cell_info" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  match rt.cell_info(sig.id()) {
    Some(info) => debug_inspect(info.label, content="None")
    None => abort("expected cell info")
  }
}

// Derived introspection

///|
test "derived: id() returns valid CellId" {
  let rt = Runtime::Runtime()
  let d = Derived::Derived(rt, () => 42)
  let id = d.id()
  inspect(id.id >= 0, content="true")
}

///|
test "derived: dependencies() returns empty before computation" {
  let rt = Runtime::Runtime()
  let d = Derived::Derived(rt, () => 10)
  debug_inspect(d.dependencies(), content="[]")
}

///|
test "derived: dependencies() includes all inputs after computation" {
  let rt = Runtime::Runtime()
  let x = Input::Input(rt, 1)
  let y = Input::Input(rt, 2)
  let sum = Derived::Derived(rt, () => x.get() + y.get())

  sum.read_or_abort() |> ignore
  let deps = sum.dependencies()
  inspect(deps.length(), content="2")
  inspect(deps.contains(x.id()), content="true")
  inspect(deps.contains(y.id()), content="true")
}

///|
test "derived: changed_at and verified_at track revisions" {
  let rt = Runtime::Runtime()
  let x = Input::Input(rt, 5)
  x.set(10) // Bump revision to 1
  let doubled = Derived::Derived(rt, () => x.get() * 2)

  doubled.read_or_abort() |> ignore
  let initial_changed = doubled.changed_at()
  let initial_verified = doubled.verified_at()

  inspect(initial_changed.value > 0, content="true")
  inspect(initial_verified.value > 0, content="true")

  // Change input
  x.set(20)
  doubled.read_or_abort() |> ignore

  inspect(doubled.changed_at().value > initial_changed.value, content="true")
  inspect(doubled.verified_at().value > initial_verified.value, content="true")
}

///|
test "derived: dependencies update on recomputation" {
  let rt = Runtime::Runtime()
  let cond = Input::Input(rt, true)
  let a = Input::Input(rt, 1)
  let b = Input::Input(rt, 2)

  let dynamic = Derived::Derived(rt, () => {
    if cond.get() {
      a.get()
    } else {
      b.get()
    }
  })

  dynamic.read_or_abort() |> ignore
  let deps1 = dynamic.dependencies()
  inspect(deps1.contains(a.id()), content="true")
  inspect(deps1.contains(b.id()), content="false")

  cond.set(false)
  dynamic.read_or_abort() |> ignore
  let deps2 = dynamic.dependencies()
  inspect(deps2.contains(a.id()), content="false")
  inspect(deps2.contains(b.id()), content="true")
}

///|
test "derived: label stored via optional param" {
  let rt = Runtime::Runtime()
  let x = Input::Input(rt, 1)
  let d = Derived::Derived(rt, () => x.get() * 2, label="doubled")
  let _ = d.read_or_abort()
  match rt.cell_info(d.id()) {
    Some(info) =>
      debug_inspect(
        info.label,
        content=(
          #|Some("doubled")
        ),
      )
    None => abort("expected cell info")
  }
}

///|
test "derived: no label gives None in cell_info" {
  let rt = Runtime::Runtime()
  let x = Input::Input(rt, 1)
  let d = Derived::Derived(rt, () => x.get() * 2)
  let _ = d.read_or_abort()
  match rt.cell_info(d.id()) {
    Some(info) => debug_inspect(info.label, content="None")
    None => abort("expected cell info")
  }
}

// Runtime cell_info

///|
test "runtime: cell_info() returns metadata for input" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42, durability=High)

  match rt.cell_info(sig.id()) {
    Some(info) => {
      inspect(info.id == sig.id(), content="true")
      inspect(info.durability, content="High")
      debug_inspect(info.dependencies, content="[]")
    }
    None => abort("Expected Some(info)")
  }
}

///|
test "runtime: cell_info() returns metadata for derived" {
  let rt = Runtime::Runtime()
  let x = Input::Input(rt, 10)
  x.set(20) // Bump revision to 1
  let doubled = Derived::Derived(rt, () => x.get() * 2)

  doubled.read_or_abort() |> ignore

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
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 0)
  let invalid_id : CellId = { runtime_id: sig.id().runtime_id, id: 999 }

  match rt.cell_info(invalid_id) {
    Some(_) => abort("Expected None for invalid ID")
    None => ()
  }
}

///|
test "runtime: cell_info() returns None for unused slot" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let beyond_id : CellId = { runtime_id: sig.id().runtime_id, id: 1000 }

  match rt.cell_info(beyond_id) {
    Some(_) => abort("Expected None for unused slot")
    None => ()
  }
}

///|
test "runtime: cell_info() returns None for negative CellId" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 42)
  let negative_id : CellId = { runtime_id: sig.id().runtime_id, id: -1 }

  match rt.cell_info(negative_id) {
    Some(_) => abort("Expected None for negative CellId")
    None => ()
  }
}

///|
test "runtime: cell_info() returns None for CellId from different runtime" {
  let rt1 = Runtime::Runtime()
  let rt2 = Runtime::Runtime()

  let sig1 = Input::Input(rt1, 100)
  let sig2 = Input::Input(rt2, 200)

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
test "integration: debug why derived recomputed" {
  let rt = Runtime::Runtime()
  let x = Input::Input(rt, 10)
  let y = Input::Input(rt, 20)
  let sum = Derived::Derived(rt, () => x.get() + y.get())

  sum.read_or_abort() |> ignore
  let initial_verified = sum.verified_at()

  // Same value - backdating means no effective change
  x.set(10)
  sum.read_or_abort() |> ignore
  inspect(sum.verified_at() == initial_verified, content="true")

  // Different value - should trigger recomputation
  y.set(30)
  sum.read_or_abort() |> ignore
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
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, 5)
  let step1 = Derived::Derived(rt, () => input.get() * 2)
  let step2 = Derived::Derived(rt, () => step1.get_or_abort() + 10)
  let step3 = Derived::Derived(rt, () => step2.get_or_abort() * 3)

  step3.read_or_abort() |> ignore

  inspect(step3.dependencies().contains(step2.id()), content="true")
  inspect(step2.dependencies().contains(step1.id()), content="true")
  inspect(step1.dependencies().contains(input.id()), content="true")

  // No cross-dependencies
  inspect(step3.dependencies().contains(input.id()), content="false")
  inspect(step3.dependencies().contains(step1.id()), content="false")
}

///|
test "integration: diamond dependency has no duplicates" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, 10)
  let left = Derived::Derived(rt, () => input.get() + 1)
  let right = Derived::Derived(rt, () => input.get() + 2)
  let merge = Derived::Derived(rt, () => {
    left.get_or_abort() + right.get_or_abort()
  })

  merge.read_or_abort() |> ignore

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
test "gc_root_count tracks Watch lifecycle" {
  let rt = Runtime::Runtime()
  let d = Derived::Derived(rt, fn() { 42 }, label="test_cell")
  let id = d.id()
  assert_eq(rt.gc_root_count(id), 0)
  let watch = d.watch()
  assert_eq(rt.gc_root_count(id), 1)
  watch.dispose()
  assert_eq(rt.gc_root_count(id), 0)
}

///|
test "gc_root_count returns 0 for an unknown CellId" {
  let rt = Runtime::Runtime()
  let d = Derived::Derived(rt, fn() { 0 }, label="anchor")
  let unknown : CellId = { id: d.id().id + 999, runtime_id: d.id().runtime_id }
  assert_eq(rt.gc_root_count(unknown), 0)
}

///|
test "integration: understanding backdating with introspection" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, 5)
  let abs_value = Derived::Derived(rt, () => {
    let val = input.get()
    if val < 0 {
      -val
    } else {
      val
    }
  })

  abs_value.read_or_abort() |> ignore
  let old_changed_at = abs_value.changed_at()
  let old_verified_at = abs_value.verified_at()

  // Change input from 5 to -5: different input, same output (5)
  input.set(-5)
  abs_value.read_or_abort() |> ignore

  // Backdating: changed_at didn't advance because output is still 5
  inspect(abs_value.changed_at() == old_changed_at, content="true")

  // But verified_at did advance
  inspect(abs_value.verified_at().value > old_verified_at.value, content="true")
}
