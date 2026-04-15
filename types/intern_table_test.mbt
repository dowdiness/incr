///|
test "intern same value returns same id" {
  let table : InternTable[String] = InternTable::new()
  let id1 = table.intern("hello")
  let id2 = table.intern("hello")
  inspect(id1 == id2, content="true")
}

///|
test "intern different values returns different ids" {
  let table : InternTable[String] = InternTable::new()
  let id1 = table.intern("hello")
  let id2 = table.intern("world")
  inspect(id1 == id2, content="false")
}

///|
test "get round-trips" {
  let table : InternTable[String] = InternTable::new()
  let id = table.intern("hello")
  inspect(table.get(id), content="hello")
}

///|
test "len tracks unique entries" {
  let table : InternTable[String] = InternTable::new()
  inspect(table.len(), content="0")
  let _ = table.intern("a")
  inspect(table.len(), content="1")
  let _ = table.intern("a") // duplicate
  inspect(table.len(), content="1")
  let _ = table.intern("b")
  inspect(table.len(), content="2")
}
