///|
test "validate_script reports duplicate initial IDs" {
  assert_eq(
    validate_script(
      Scenario::Source,
      [SourceInit::{ id: 0, value: 1 }, SourceInit::{ id: 0, value: 2 }],
      [],
    ),
    Some("duplicate initial source id: 0"),
  )
}

///|
test "validate_script reports Set targets absent from initial sources" {
  assert_eq(
    validate_script(Scenario::Source, [SourceInit::{ id: 0, value: 1 }], [
      Operation::Set(1, 2),
    ]),
    Some("Set target is not an initial source: 1"),
  )
}

///|
test "validate_script permits reads of undefined sources" {
  assert_eq(
    validate_script(Scenario::Source, [SourceInit::{ id: 0, value: 1 }], [
      Operation::Read(1),
    ]),
    None,
  )
}

///|
test "validate_script enforces scenario-required initial IDs" {
  assert_eq(
    validate_script(Scenario::UnitQuery, [], []),
    Some("scenario requires initial source id: 0"),
  )
  assert_eq(
    validate_script(
      Scenario::DynamicBranch,
      [SourceInit::{ id: 0, value: 0 }],
      [],
    ),
    Some("scenario requires initial source id: 1"),
  )
}

///|
test "validate_script enforces operation shapes and fixed roots" {
  let root_sources = [
    SourceInit::{ id: 0, value: 0 },
    SourceInit::{ id: 1, value: 1 },
  ]
  assert_eq(
    validate_script(Scenario::UnitQuery, root_sources, [Operation::Read(1)]),
    Some("fixed-root scenario cannot Read present non-root source: 1"),
  )
  assert_eq(
    validate_script(Scenario::UnitQuery, [SourceInit::{ id: 0, value: 0 }], [
      Operation::Read(99),
    ]),
    None,
  )
  assert_eq(
    validate_script(Scenario::KeyedQuery, [SourceInit::{ id: 0, value: 0 }], [
      Operation::Read(0),
    ]),
    Some("KeyedQuery accepts ReadKey operations, not plain Read"),
  )
  assert_eq(
    validate_script(Scenario::Source, [], [Operation::ReadKey(0, 1)]),
    Some("ReadKey is only valid for KeyedQuery"),
  )
  assert_eq(
    validate_script(Scenario::Source, [], [Operation::DomainFailure(1)]),
    Some("DomainFailure operation requires the DomainFailure scenario"),
  )
  assert_eq(
    validate_script(Scenario::DomainFailure, [], [
      Operation::StructuralFailure(1),
    ]),
    Some("StructuralFailure operation requires the StructuralError scenario"),
  )
}
