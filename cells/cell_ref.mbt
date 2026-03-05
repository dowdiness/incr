///|
pub struct SignalId[T] {
  id : CellId
}

///|
pub struct MemoId[T] {
  id : CellId
}

///|
pub enum CellRef {
  PullSignal(Int)
  PullMemo(Int)
  PushReactive(Int)
  PushEffect(Int)
  HybridMemo(Int)
  Disposed
  // Relation, Rule added in Phase 4
}
