///|
test "room capability accepts the 128-bit base64url length boundary" {
  assert_true(validate_room_capability("abcdefghijklmnopqrstuv") is Ok(_))
  assert_true(
    validate_room_capability("abcdefghijklmnopqrstu")
    is Err(RoomCapabilityError::TooShort),
  )
}

///|
test "room capability accepts only the URL-safe alphabet" {
  assert_true(validate_room_capability("ABCdef0123456789_-wxyz") is Ok(_))
  assert_true(
    validate_room_capability("abcdefghijklmnopqrstu+")
    is Err(RoomCapabilityError::UnsupportedCharacter),
  )
  assert_true(
    validate_room_capability("abcdefghijklmnopqrstu/")
    is Err(RoomCapabilityError::UnsupportedCharacter),
  )
  assert_true(
    validate_room_capability("abcdefghijklmnopqrstu=")
    is Err(RoomCapabilityError::UnsupportedCharacter),
  )
}

///|
test "room capability rejects values above the transport bound" {
  let oversized = "a".repeat(129)
  assert_true(
    validate_room_capability(oversized) is Err(RoomCapabilityError::TooLong),
  )
}
