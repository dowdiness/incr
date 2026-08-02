///|
using @incr_types {type CellId, type Durability, type Revision, type RuntimeId}

///|
/// Metadata discriminated by the runtime cell's public semantic kind.
/// Facade compositions such as AcceptedDerived remain compositions rather
/// than pretending to be one runtime cell kind.
pub(all) enum CellSnapshotDetails {
  Input(changed_at~ : Revision, durability~ : Durability)
  Derived(
    changed_at~ : Revision,
    verified_at~ : Revision,
    durability~ : Durability,
    dependencies~ : ReadOnlyArray[CellId]
  )
  ReachableDerived(
    changed_at~ : Revision,
    verified_at~ : Revision,
    durability~ : Durability,
    dependencies~ : ReadOnlyArray[CellId]
  )
  EagerDerived(
    changed_at~ : Revision,
    level~ : Int,
    dependencies~ : ReadOnlyArray[CellId]
  )
  Effect(level~ : Int, dependencies~ : ReadOnlyArray[CellId])
  Relation(changed_at~ : Revision)
  MapRelation(changed_at~ : Revision)
  Rule
} derive(Debug)

///|
/// Candidate replacement responsibility for the pull-only `CellInfo` adapter.
/// Reverse edges and root ownership remain on their existing interfaces.
pub struct CellSnapshot {
  id : CellId
  label : String?
  details : CellSnapshotDetails
} derive(Debug)

///|
fn readonly_ids(ids : Array[CellId]) -> ReadOnlyArray[CellId] {
  ReadOnlyArray::from_array(ids)
}

///|
/// Builds the complete prototype fixture inside the provider package.
/// Downstream code can inspect snapshots but cannot construct an invalid
/// `CellSnapshot` struct literal.
pub fn sample_snapshots() -> Array[CellSnapshot] {
  let runtime_id = RuntimeId(435)
  let input_id : CellId = { runtime_id, id: 1 }
  let pull_id : CellId = { runtime_id, id: 2 }
  let reachable_id : CellId = { runtime_id, id: 3 }
  let eager_id : CellId = { runtime_id, id: 4 }
  let effect_id : CellId = { runtime_id, id: 5 }
  let relation_id : CellId = { runtime_id, id: 6 }
  let map_relation_id : CellId = { runtime_id, id: 7 }
  let rule_id : CellId = { runtime_id, id: 8 }
  let r1 = Revision::initial()
  let r2 = r1.next()
  let r3 = r2.next()
  [
    {
      id: input_id,
      label: Some("source"),
      details: Input(changed_at=r3, durability=High),
    },
    {
      id: pull_id,
      label: Some("pull"),
      details: Derived(
        changed_at=r2,
        verified_at=r3,
        durability=Low,
        dependencies=readonly_ids([input_id]),
      ),
    },
    {
      id: reachable_id,
      label: Some("reachable"),
      details: ReachableDerived(
        changed_at=r2,
        verified_at=r3,
        durability=Low,
        dependencies=readonly_ids([pull_id]),
      ),
    },
    {
      id: eager_id,
      label: None,
      details: EagerDerived(
        changed_at=r3,
        level=3,
        dependencies=readonly_ids([reachable_id]),
      ),
    },
    {
      id: effect_id,
      label: None,
      details: Effect(level=4, dependencies=readonly_ids([eager_id])),
    },
    { id: relation_id, label: Some("facts"), details: Relation(changed_at=r2) },
    {
      id: map_relation_id,
      label: Some("values"),
      details: MapRelation(changed_at=r2),
    },
    { id: rule_id, label: Some("derive values"), details: Rule },
  ]
}
