///|
fn detail_name(details : @shape.CellSnapshotDetails) -> String {
  match details {
    Input(..) => "Input"
    PullDerived(..) => "PullDerived"
    ReachableDerived(..) => "ReachableDerived"
    EagerDerived(..) => "EagerDerived"
    Effect(..) => "Effect"
    Relation(..) => "Relation"
    MapRelation(..) => "MapRelation"
    Rule(..) => "Rule"
  }
}

///|
fn dependency_count(details : @shape.CellSnapshotDetails) -> Int {
  match details {
    PullDerived(dependencies~, ..)
    | ReachableDerived(dependencies~, ..)
    | EagerDerived(dependencies~, ..)
    | Effect(dependencies~, ..) => dependencies.length()
    Rule(input_relations~, output_relations~) =>
      input_relations.length() + output_relations.length()
    Input(..) | Relation(..) | MapRelation(..) => 0
  }
}

///|
fn print_snapshot(snapshot : @shape.CellSnapshot) -> Unit {
  let name = detail_name(snapshot.details)
  let dependency_total = dependency_count(snapshot.details)
  let common_text = @debug.to_string(snapshot.common)
  let details_text = @debug.to_string(snapshot.details)
  println("\n\{name}")
  println("  common: \{common_text}")
  println("  details: \{details_text}")
  println("  relevant edge count: \{dependency_total}")
}

///|
fn main {
  println("PROTOTYPE #435 — kind-aware per-cell snapshot shape")
  println(
    "Question: can one discriminated shape stay truthful for every live CellRef kind while preserving CellInfo literals?",
  )

  let input_id = @shape.CellId(1)
  let pull_id = @shape.CellId(2)
  let reachable_id = @shape.CellId(3)
  let rule_id = @shape.CellId(8)
  let r2 = @shape.Revision(2)
  let r3 = @shape.Revision(3)
  let snapshots = @shape.sample_snapshots()

  for snapshot in snapshots {
    print_snapshot(snapshot)
  }

  let legacy : @shape.CellInfo = @shape.CellInfo::{
    label: Some("legacy downstream literal"),
    id: pull_id,
    changed_at: r2,
    verified_at: r3,
    durability: Low,
    dependencies: [input_id],
    subscribers: [reachable_id],
  }
  let legacy_text = @debug.to_string(legacy)
  println("\nCompatibility probe")
  println("  external CellInfo literal still compiles: \{legacy_text}")

  let mutable_source = [input_id]
  let owned_snapshot = ReadOnlyArray::from_array(mutable_source)
  mutable_source[0] = rule_id
  let copy_is_independent = owned_snapshot[0] == input_id
  println("  ReadOnlyArray::from_array owns a copy: \{copy_is_independent}")
}
