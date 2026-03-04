///|
test "pull_signal_data: can be constructed" {
  let id = CellId::{ runtime_id: 0, id: 0 }
  let data = PullSignalData::{
    cell_id: id,
    label: None,
    changed_at: Revision::initial(),
    durability: Low,
    subscribers: @hashset.new(),
    on_change: None,
    commit_pending: None,
    rollback_pending: None,
  }
  inspect(data.label, content="None")
}

///|
test "signal_id_memo_id: newtype handles wrap CellId" {
  let cid = CellId::{ runtime_id: 0, id: 5 }
  let sid : SignalId[Int] = SignalId::{ id: cid }
  let mid : MemoId[Int] = MemoId::{ id: cid }
  inspect(sid.id.id, content="5")
  inspect(mid.id.id, content="5")
}

///|
test "cell_ref: PullSignal and PullMemo variants pattern-match correctly" {
  let a : CellRef = CellRef::PullSignal(0)
  let b : CellRef = CellRef::PullMemo(3)
  let ia = match a { PullSignal(i) => i; _ => -1 }
  let ib = match b { PullMemo(i) => i; _ => -1 }
  inspect(ia, content="0")
  inspect(ib, content="3")
}
