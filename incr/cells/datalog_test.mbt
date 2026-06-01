///|
test "relation: insert adds to delta, not current" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let inserted = rel.insert(42)
  inspect(inserted, content="true")
  inspect(rel.contains(42), content="false") // not in current yet
}

///|
test "relation: duplicate insert returns false" {
  let rt = Runtime::Runtime()
  let rel : Relation[Int] = Relation::Relation(rt)
  let _ = rel.insert(1)
  let dup = rel.insert(1)
  inspect(dup, content="false")
}
