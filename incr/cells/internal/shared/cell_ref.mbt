///|
pub(all) enum CellRef {
  PullInput(Int)
  PullMemo(Int)
  PushReactive(Int)
  PushEffect(Int)
  HybridMemo(Int)
  Disposed
  Relation(Int)
  FunctionalRelation(Int)
  Rule(Int)
}
