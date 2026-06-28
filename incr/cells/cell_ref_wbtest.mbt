///|
test "pull_signal_data: can be constructed" {
  let id = CellId::{ runtime_id: @incr_types.RuntimeId(0), id: 0 }
  let data = PullSignalData::{
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

///|
test "input_id_memo_id: newtype handles wrap CellId" {
  let cid = CellId::{ runtime_id: @incr_types.RuntimeId(0), id: 5 }
  let sid : @incr_types.InputId[Int] = @incr_types.InputId::{ id: cid }
  let mid : @incr_types.MemoId[Int] = @incr_types.MemoId::{ id: cid }
  inspect(sid.id.id, content="5")
  inspect(mid.id.id, content="5")
}

///|
test "cell_ref: PullSignal and PullMemo variants pattern-match correctly" {
  let a : CellRef = CellRef::PullSignal(0)
  let b : CellRef = CellRef::PullMemo(3)
  let ia = match a {
    PullSignal(i) => i
    _ => -1
  }
  let ib = match b {
    PullMemo(i) => i
    _ => -1
  }
  inspect(ia, content="0")
  inspect(ib, content="3")
}
