///|
/// Prototype-only cell identity.
pub(all) struct CellId {
  value : Int
} derive(Eq, Debug)

///|
pub fn CellId::CellId(value : Int) -> CellId {
  { value, }
}

///|
/// Prototype-only revision value.
pub(all) struct Revision {
  value : Int
} derive(Eq, Debug)

///|
pub fn Revision::Revision(value : Int) -> Revision {
  { value, }
}

///|
pub(all) enum Durability {
  Low
  Medium
  High
} derive(Eq, Debug)

///|
/// Compatibility shape copied from the current public `CellInfo` contract.
/// The prototype adds no field to this struct.
pub(all) struct CellInfo {
  label : String?
  id : CellId
  changed_at : Revision
  verified_at : Revision
  durability : Durability
  dependencies : Array[CellId]
  subscribers : Array[CellId]
} derive(Debug)

///|
/// Metadata meaningful for every live runtime cell.
pub struct CellSnapshotCommon {
  id : CellId
  label : String?
  subscribers : ReadOnlyArray[CellId]
  gc_root_count : Int
} derive(Debug)

///|
/// Metadata discriminated by the runtime cell's storage/engine kind.
/// Facade compositions such as AcceptedDerived remain compositions rather
/// than pretending to be one runtime cell kind.
pub(all) enum CellSnapshotDetails {
  Input(changed_at~ : Revision, durability~ : Durability)
  PullDerived(
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
  Rule(
    input_relations~ : ReadOnlyArray[CellId],
    output_relations~ : ReadOnlyArray[CellId]
  )
} derive(Debug)

///|
/// Candidate replacement responsibility for the pull-only `CellInfo` adapter.
pub struct CellSnapshot {
  common : CellSnapshotCommon
  details : CellSnapshotDetails
} derive(Debug)

///|
fn readonly_ids(ids : Array[CellId]) -> ReadOnlyArray[CellId] {
  ReadOnlyArray::from_array(ids)
}

///|
fn common(
  id : CellId,
  label : String?,
  subscribers : Array[CellId],
  gc_root_count : Int,
) -> CellSnapshotCommon {
  { id, label, subscribers: readonly_ids(subscribers), gc_root_count }
}

///|
/// Builds the complete prototype fixture inside the provider package.
/// Downstream code can inspect snapshots but cannot construct an invalid
/// `CellSnapshot` struct literal.
pub fn sample_snapshots() -> Array[CellSnapshot] {
  let input_id = CellId(1)
  let pull_id = CellId(2)
  let reachable_id = CellId(3)
  let eager_id = CellId(4)
  let effect_id = CellId(5)
  let relation_id = CellId(6)
  let map_relation_id = CellId(7)
  let rule_id = CellId(8)
  let r2 = Revision(2)
  let r3 = Revision(3)
  [
    {
      common: common(input_id, Some("source"), [pull_id], 0),
      details: Input(changed_at=r3, durability=High),
    },
    {
      common: common(pull_id, Some("pull"), [reachable_id], 1),
      details: PullDerived(
        changed_at=r2,
        verified_at=r3,
        durability=Low,
        dependencies=readonly_ids([input_id]),
      ),
    },
    {
      common: common(reachable_id, Some("reachable"), [eager_id], 0),
      details: ReachableDerived(
        changed_at=r2,
        verified_at=r3,
        durability=Low,
        dependencies=readonly_ids([pull_id]),
      ),
    },
    {
      common: common(eager_id, None, [effect_id], 0),
      details: EagerDerived(
        changed_at=r3,
        level=3,
        dependencies=readonly_ids([reachable_id]),
      ),
    },
    {
      common: common(effect_id, None, [], 0),
      details: Effect(level=4, dependencies=readonly_ids([eager_id])),
    },
    {
      common: common(relation_id, Some("facts"), [pull_id], 0),
      details: Relation(changed_at=r2),
    },
    {
      common: common(map_relation_id, Some("values"), [], 0),
      details: MapRelation(changed_at=r2),
    },
    {
      common: common(rule_id, Some("derive values"), [], 0),
      details: Rule(
        input_relations=readonly_ids([relation_id]),
        output_relations=readonly_ids([map_relation_id]),
      ),
    },
  ]
}
