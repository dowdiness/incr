///|
test "Script snapshots both caller-owned arrays" {
  let initial_sources = [@model.SourceInit::{ id: 0, value: 1 }]
  let operations = [@model.Operation::Read(0)]
  let script = @model.Script::Script(initial_sources, operations)
  initial_sources[0] = @model.SourceInit::{ id: 0, value: 9 }
  operations[0] = @model.Operation::Set(0, 9)
  assert_eq(script.initial_sources(), [@model.SourceInit::{ id: 0, value: 1 }])
  assert_eq(script.operations(), [@model.Operation::Read(0)])
}

///|
test "Script accessors return defensive copies" {
  let script = @model.Script::Script([@model.SourceInit::{ id: 0, value: 1 }], [
    @model.Operation::Read(0),
  ])
  let initial_sources = script.initial_sources()
  let operations = script.operations()
  initial_sources[0] = @model.SourceInit::{ id: 0, value: 9 }
  operations[0] = @model.Operation::Set(0, 9)
  assert_eq(script.initial_sources(), [@model.SourceInit::{ id: 0, value: 1 }])
  assert_eq(script.operations(), [@model.Operation::Read(0)])
}
