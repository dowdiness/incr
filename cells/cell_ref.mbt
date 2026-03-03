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
  // PushReactive, PushEffect, Disposed added in Phase 3
  // Relation, Rule added in Phase 4
  // HybridMemo added in Phase 5
}
