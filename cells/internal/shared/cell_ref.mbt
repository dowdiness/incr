///|
pub(all) enum CellRef {
  PullSignal(Int)
  PullMemo(Int)
  PushReactive(Int)
  PushEffect(Int)
  HybridMemo(Int)
  Disposed
  Relation(Int)
  FunctionalRelation(Int)
  Rule(Int)
}
