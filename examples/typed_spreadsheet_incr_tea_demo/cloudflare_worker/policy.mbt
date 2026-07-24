///|
/// PRODUCTION CORE: deterministic admission policy for room requests.
const MIN_ROOM_CAPABILITY_LENGTH : Int = 22

///|
const MAX_ROOM_CAPABILITY_LENGTH : Int = 128

///|
fn is_capability_char(value : Char) -> Bool {
  value.is_ascii_alphabetic() ||
  value.is_ascii_digit() ||
  value == '-' ||
  value == '_'
}

///|
fn parse_room_capability(pathname : String) -> Result[String, String] {
  match pathname.split_once("/api/rooms/") {
    Some((prefix, suffix)) if prefix.is_empty() && !suffix.is_empty() =>
      if suffix.length() < MIN_ROOM_CAPABILITY_LENGTH {
        Err("room capability is too short")
      } else if suffix.length() > MAX_ROOM_CAPABILITY_LENGTH {
        Err("room capability is too long")
      } else if !suffix.all(is_capability_char) {
        Err("room capability contains unsupported characters")
      } else {
        Ok(suffix.to_owned())
      }
    _ => Err("room capability is missing")
  }
}

///|
fn loopback_origins_equivalent(left : String, right : String) -> Bool {
  (
    left.has_prefix("http://localhost:") &&
    right.has_prefix("http://127.0.0.1:")
  ) ||
  (
    left.has_prefix("http://127.0.0.1:") &&
    right.has_prefix("http://localhost:")
  )
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
) -> Result[String, String] {
  guard http_method == "GET" else { return Err("room endpoint requires GET") }
  guard origin_allowed(origin, request_origin) else {
    return Err("origin is not allowed")
  }
  parse_room_capability(pathname)
}
