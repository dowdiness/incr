///|
test "pull_input_data: can be constructed" {
  let id = CellId::{ runtime_id: @incr_types.RuntimeId(0), id: 0 }
  let data = PullInputData::{
    meta: {
      cell_id: id,
      label: None,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.HashSet([]),
      push_reachable_count: 0,
    },
    on_change: None,
    commit_pending: None,
  }
  debug_inspect(data.meta.label, content="None")
}
