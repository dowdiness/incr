///|
fn detail_name(details : @shape.CellSnapshotDetails) -> String {
  match details {
    Input(..) => "Input"
    Derived(..) => "Derived"
    ReachableDerived(..) => "ReachableDerived"
    EagerDerived(..) => "EagerDerived"
    Effect(..) => "Effect"
    Relation(..) => "Relation"
    MapRelation(..) => "MapRelation"
    Rule => "Rule"
  }
}

///|
fn dependency_count(details : @shape.CellSnapshotDetails) -> Int {
  match details {
    Derived(dependencies~, ..)
    | ReachableDerived(dependencies~, ..)
    | EagerDerived(dependencies~, ..)
    | Effect(dependencies~, ..) => dependencies.length()
    Input(..) | Relation(..) | MapRelation(..) | Rule => 0
  }
}

///|
fn print_snapshot(snapshot : @shape.CellSnapshot) -> Unit {
  let name = detail_name(snapshot.details)
  let dependency_total = dependency_count(snapshot.details)
  let id_text = @debug.to_string(snapshot.id)
  let label_text = @debug.to_string(snapshot.label)
  let details_text = @debug.to_string(snapshot.details)
  println("\n\{name}")
  println("  id: \{id_text}")
  println("  label: \{label_text}")
  println("  details: \{details_text}")
  println("  relevant edge count: \{dependency_total}")
}

///|
fn main {
  println("PROTOTYPE #435 — kind-aware per-cell snapshot shape")
  println(
    "Question: can one discriminated shape stay truthful for every live CellRef kind while preserving CellInfo literals?",
  )

  for snapshot in @shape.sample_snapshots() {
    print_snapshot(snapshot)
  }

  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1, label="actual source")
  let derived = @incr.Derived(rt, () => input.get() + 1, label="actual derived")
  ignore(derived.read_or_abort())
  let actual = match rt.cell_info(derived.id()) {
    Some(info) => info
    None => abort("prototype expected live CellInfo")
  }
  let legacy : @incr.CellInfo = @incr.CellInfo::{
    label: actual.label,
    id: actual.id,
    changed_at: actual.changed_at,
    verified_at: actual.verified_at,
    durability: actual.durability,
    dependencies: actual.dependencies.copy(),
    subscribers: actual.subscribers.copy(),
  }
  let legacy_dependency_count = legacy.dependencies.length()
  println("\nCompatibility probe")
  println("  actual external @incr.CellInfo literal compiles: true")
  println("  legacy dependency count: \{legacy_dependency_count}")

  let other_rt = @incr.Runtime()
  let foreign_is_none = other_rt.cell_info(derived.id()) is None
  println("  current cross-Runtime query returns None: \{foreign_is_none}")

  let mutable_source = actual.dependencies.copy()
  let owned_snapshot = ReadOnlyArray::from_array(mutable_source)
  let other_input = @incr.Input(rt, 9)
  mutable_source[0] = other_input.id()
  let copy_is_independent = owned_snapshot[0] == input.id()
  println("  ReadOnlyArray::from_array owns a copy: \{copy_is_independent}")

  let derived_id = derived.id()
  derived.dispose()
  let disposed_is_none = rt.cell_info(derived_id) is None
  println("  current disposed query returns None: \{disposed_is_none}")
}
