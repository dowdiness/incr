///|
/// Encodes a register in the versioned compact wire schema.
pub fn encode_register(register : CellRegister) -> String {
  match register {
    Source(text) =>
      Json::object({
        "v": Json::number(1.0),
        "kind": Json::string("source"),
        "text": Json::string(text),
      }).stringify()
    Deleted =>
      Json::object({ "v": Json::number(1.0), "kind": Json::string("deleted") }).stringify()
  }
}

// Json's object Map necessarily overwrites duplicate keys. This preflight is
// therefore a lexer-only member counter over already-valid JSON: it preserves
// duplicate-key detection without parsing values or becoming a second decoder.

///|
fn root_member_count(text : String) -> Int {
  let mut quoted = false
  let mut escaped = false
  let mut depth = 0
  let mut members = 0
  let mut has_content = false
  for ch in text {
    if quoted {
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        quoted = false
      }
    } else if ch == '"' {
      quoted = true
      has_content = true
    } else if ch == '{' || ch == '[' {
      depth += 1
      if depth == 1 {
        has_content = false
      }
    } else if (ch == '}' || ch == ']') && depth > 0 {
      if ch == '}' && depth == 1 && has_content {
        members += 1
      }
      depth -= 1
    } else if depth == 1 && ch == ',' {
      members += 1
      has_content = false
    } else if depth == 1 && ch != ' ' && ch != '\n' && ch != '\r' && ch != '\t' {
      has_content = true
    }
  }
  members
}

///|
fn extra_names(
  object : Map[String, Json],
  expected : Array[String],
) -> ReadOnlyArray[String] {
  let xs = object.keys().to_array().filter(name => !expected.contains(name))
  xs.sort_by(String::compare)
  ReadOnlyArray::from_array(xs)
}

///|
/// Strictly decodes one register payload. `None` is the transport's unset
/// value and is not a JSON document.
pub fn decode_register(
  address : String,
  payload : String?,
) -> RegisterObservation {
  match payload {
    None => Unset
    Some(text) => {
      let parsed = @json.parse(text) catch {
        @json.ParseError::InvalidChar(_, _)
        | @json.ParseError::InvalidEof
        | @json.ParseError::InvalidNumber(_, _)
        | @json.ParseError::InvalidIdentEscape(_)
        | @json.ParseError::DepthLimitExceeded =>
          return Invalid(ProjectionDiagnostic::MalformedJson(address))
      }
      match parsed {
        Json::Object(object) => {
          if root_member_count(text) != object.length() {
            return Invalid(ProjectionDiagnostic::DuplicateFields(address))
          }
          let kind = match object.get_from_string("kind".view()) {
            None =>
              return Invalid(
                ProjectionDiagnostic::MissingField(address, "kind"),
              )
            Some(Json::String(value)) => value
            Some(_) =>
              return Invalid(
                ProjectionDiagnostic::InvalidFieldType(address, "kind"),
              )
          }
          let version = match object.get_from_string("v".view()) {
            None =>
              return Invalid(ProjectionDiagnostic::MissingField(address, "v"))
            Some(Json::Number(value, ..)) => value
            Some(_) =>
              return Invalid(
                ProjectionDiagnostic::InvalidFieldType(address, "v"),
              )
          }
          if version != 1.0 {
            return Invalid(
              ProjectionDiagnostic::UnsupportedNumericVersion(address, version),
            )
          }
          match kind {
            "source" => {
              let extra = extra_names(object, ["v", "kind", "text"])
              if extra.length() > 0 {
                return Invalid(
                  ProjectionDiagnostic::ExtraFields(address, extra),
                )
              }
              let source = match object.get_from_string("text".view()) {
                None =>
                  return Invalid(
                    ProjectionDiagnostic::MissingField(address, "text"),
                  )
                Some(Json::String(value)) => value
                Some(_) =>
                  return Invalid(
                    ProjectionDiagnostic::InvalidFieldType(address, "text"),
                  )
              }
              Decoded(Source(source))
            }
            "deleted" => {
              let extra = extra_names(object, ["v", "kind"])
              if extra.length() > 0 {
                return Invalid(
                  ProjectionDiagnostic::ExtraFields(address, extra),
                )
              }
              Decoded(Deleted)
            }
            other => Invalid(ProjectionDiagnostic::UnknownTag(address, other))
          }
        }
        _ => Invalid(ProjectionDiagnostic::NonObject(address))
      }
    }
  }
}
