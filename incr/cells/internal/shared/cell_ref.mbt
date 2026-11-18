///|
pub(all) enum CellRef {
  PullInput(Int32)
  PullMemo(Int32)
  PushReactive(Int32)
  PushEffect(Int32)
  HybridMemo(Int32)
  Disposed
  Relation(Int32)
  FunctionalRelation(Int32)
  Rule(Int32)
}
