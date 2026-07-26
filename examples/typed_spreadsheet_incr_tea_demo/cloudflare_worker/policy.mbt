///|
/// PRODUCTION CORE: deterministic admission policy for room requests.
fn is_room_path(pathname : String) -> Bool {
  pathname == "/api/rooms" || pathname.has_prefix("/api/rooms/")
}

///|
fn parse_room_capability(pathname : String) -> Result[String, String] {
  match pathname.split_once("/api/rooms/") {
    Some((prefix, suffix)) if prefix.is_empty() && !suffix.is_empty() =>
      match @collab_core.validate_room_capability(suffix.to_owned()) {
        Ok(capability) => Ok(capability)
        Err(@collab_core.RoomCapabilityError::TooShort) =>
          Err("room capability is too short")
        Err(@collab_core.RoomCapabilityError::TooLong) =>
          Err("room capability is too long")
        Err(@collab_core.RoomCapabilityError::UnsupportedCharacter) =>
          Err("room capability contains unsupported characters")
      }
    _ => Err("room capability is missing")
  }
}

///|
fn loopback_origins_equivalent(left : String, right : String) -> Bool {
  match
    (
      left.to_string_view().strip_prefix("http://localhost:"),
      right.to_string_view().strip_prefix("http://127.0.0.1:"),
    ) {
    (Some(left_port), Some(right_port)) => left_port.equal(right_port)
    _ =>
      match
        (
          left.to_string_view().strip_prefix("http://127.0.0.1:"),
          right.to_string_view().strip_prefix("http://localhost:"),
        ) {
        (Some(left_port), Some(right_port)) => left_port.equal(right_port)
        _ => false
      }
  }
}

///|
fn origin_allowed(origin : String, request_origin : String) -> Bool {
  origin.is_empty() ||
  origin == request_origin ||
  loopback_origins_equivalent(origin, request_origin)
}

///|
fn room_request_allowed(
  pathname : String,
  http_method : String,
  origin : String,
  request_origin : String,
  upgrade_requested : Bool,
) -> Result[String, String] {
  guard http_method == "GET" else { return Err("room endpoint requires GET") }
  guard upgrade_requested else {
    return Err("room endpoint requires websocket upgrade")
  }
  guard origin_allowed(origin, request_origin) else {
    return Err("origin is not allowed")
  }
  parse_room_capability(pathname)
}
