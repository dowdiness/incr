///|
/// Minimum base64url encoding length for 128 random bits; generation supplies entropy.
const MIN_ROOM_CAPABILITY_LENGTH : Int = 22

///|
/// Bounds capability size before it reaches a transport or relay path.
const MAX_ROOM_CAPABILITY_LENGTH : Int = 128

///|
/// Deterministic room capability validation shared by browser and Worker shells.
pub suberror RoomCapabilityError {
  TooShort
  TooLong
  UnsupportedCharacter
}

///|
/// Accepts only bounded, unpadded URL-safe capability values.
pub fn validate_room_capability(
  value : String,
) -> Result[String, RoomCapabilityError] {
  if value.length() < MIN_ROOM_CAPABILITY_LENGTH {
    Err(RoomCapabilityError::TooShort)
  } else if value.length() > MAX_ROOM_CAPABILITY_LENGTH {
    Err(RoomCapabilityError::TooLong)
  } else if !value.all(char => {
      char.is_ascii_alphabetic() ||
      char.is_ascii_digit() ||
      char == '-' ||
      char == '_'
    }) {
    Err(RoomCapabilityError::UnsupportedCharacter)
  } else {
    Ok(value)
  }
}
