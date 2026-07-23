///|
test "codec compact source and deleted forms" {
  let source = CellRegister::Source("a\\\"b\\\\c")
  assert_eq(
    encode_register(source),
    "{\"v\":1,\"kind\":\"source\",\"text\":\"a\\\\\\\"b\\\\\\\\c\"}",
  )
  assert_eq(
    encode_register(CellRegister::Source("")),
    "{\"v\":1,\"kind\":\"source\",\"text\":\"\"}",
  )
  assert_eq(
    encode_register(CellRegister::Deleted),
    "{\"v\":1,\"kind\":\"deleted\"}",
  )
  assert_eq(decode_register("A1", None), RegisterObservation::Unset)
  assert_eq(
    decode_register("A1", Some(encode_register(source))),
    RegisterObservation::Decoded(source),
  )
  assert_eq(
    decode_register("A1", Some(encode_register(CellRegister::Deleted))),
    RegisterObservation::Decoded(CellRegister::Deleted),
  )
  let id = CollaborativeSheetId::CollaborativeSheetId("sheet-7")
  assert_eq(id.value(), "sheet-7")
}

///|
test "codec accepts order and semantic numeric versions" {
  for
    text in [
      "{\"kind\":\"deleted\",\"v\":1}", "{\"v\":1.0,\"kind\":\"deleted\"}", "{\"kind\":\"deleted\",\"v\":1e0}",
    ] {
    assert_eq(
      decode_register("A1", Some(text)),
      RegisterObservation::Decoded(CellRegister::Deleted),
    )
  }
}

///|
test "codec reports structural and semantic failures" {
  assert_eq(
    decode_register("A1", Some("{")),
    RegisterObservation::Invalid(ProjectionDiagnostic::MalformedJson("A1")),
  )
  assert_eq(
    decode_register("A1", Some("[]")),
    RegisterObservation::Invalid(ProjectionDiagnostic::NonObject("A1")),
  )
  assert_eq(
    decode_register("A1", Some("{}")),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::MissingField("A1", "kind"),
    ),
  )
  assert_eq(
    decode_register("A1", Some("{\"kind\":\"deleted\"}")),
    RegisterObservation::Invalid(ProjectionDiagnostic::MissingField("A1", "v")),
  )
  assert_eq(
    decode_register("A1", Some("{\"v\":1,\"kind\":\"source\"}")),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::MissingField("A1", "text"),
    ),
  )
  assert_eq(
    decode_register("A1", Some("{\"v\":\"1\",\"kind\":\"deleted\"}")),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::InvalidFieldType("A1", "v"),
    ),
  )
  assert_eq(
    decode_register("A1", Some("{\"v\":1,\"kind\":1}")),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::InvalidFieldType("A1", "kind"),
    ),
  )
  assert_eq(
    decode_register("A1", Some("{\"v\":1,\"kind\":\"source\",\"text\":1}")),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::InvalidFieldType("A1", "text"),
    ),
  )
  assert_eq(
    decode_register("A1", Some("{\"v\":2,\"kind\":\"deleted\"}")),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::UnsupportedNumericVersion("A1", 2.0),
    ),
  )
  assert_eq(
    decode_register("A1", Some("{\"v\":1,\"kind\":\"other\"}")),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::UnknownTag("A1", "other"),
    ),
  )
  assert_eq(
    decode_register(
      "A1",
      Some("{\"v\":1,\"kind\":\"deleted\",\"z\":0,\"a\":0}"),
    ),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::ExtraFields("A1", ["a", "z"]),
    ),
  )
  assert_eq(
    decode_register(
      "A1",
      Some("{\"v\":1,\"kind\":\"source\",\"text\":\"x\",\"z\":0}"),
    ),
    RegisterObservation::Invalid(ProjectionDiagnostic::ExtraFields("A1", ["z"])),
  )
}

///|
test "codec duplicate scanner handles strings and nested values" {
  let escaped = "{\"v\":1,\"kind\":\"deleted\",\"note\":\"comma, } and \\\"quote\\\"\"}"
  assert_eq(
    decode_register("A1", Some(escaped)),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::ExtraFields("A1", ["note"]),
    ),
  )
  let escaped_backslashes = "{\"v\":1,\"kind\":\"deleted\",\"note\":\"backslash \\\\, and brace }\"}"
  assert_eq(
    decode_register("A1", Some(escaped_backslashes)),
    RegisterObservation::Invalid(
      ProjectionDiagnostic::ExtraFields("A1", ["note"]),
    ),
  )
  let nested = "{\"v\":1,\"kind\":\"deleted\",\"x\":{\"a\":[1,2,{\"b\":true}]}}"
  assert_eq(
    decode_register("A1", Some(nested)),
    RegisterObservation::Invalid(ProjectionDiagnostic::ExtraFields("A1", ["x"])),
  )
  assert_eq(
    decode_register(
      "A1",
      Some("{\"v\":1,\"kind\":\"deleted\",\"kind\":\"deleted\"}"),
    ),
    RegisterObservation::Invalid(ProjectionDiagnostic::DuplicateFields("A1")),
  )
  assert_eq(
    decode_register("A1", Some("{\"v\":1,\"kind\":\"deleted\",\"v\":1}")),
    RegisterObservation::Invalid(ProjectionDiagnostic::DuplicateFields("A1")),
  )
}

///|
test "snapshot deduplicates canonical addresses and keeps first raw entries" {
  let snapshot = RawRegisterSnapshot::RawRegisterSnapshot(
    ["B1", "A1", "B1", "A1"],
    [
      RawRegisterEntry::RawRegisterEntry("A1", Some("first")),
      RawRegisterEntry::RawRegisterEntry("X1", Some("unknown")),
      RawRegisterEntry::RawRegisterEntry("A1", Some("second")),
      RawRegisterEntry::RawRegisterEntry("B1", None),
    ],
  )
  assert_eq(snapshot.addresses(), ["B1", "A1"])
  assert_eq(snapshot.entries().length(), 2)
  assert_eq(snapshot.entries()[0].address(), "B1")
  assert_eq(snapshot.entries()[1].address(), "A1")
  assert_eq(snapshot.entries()[0].payload(), None)
  assert_eq(snapshot.entries()[1].payload(), Some("first"))
}
