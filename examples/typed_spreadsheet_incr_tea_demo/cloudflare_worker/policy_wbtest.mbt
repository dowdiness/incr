///|
test "room capability policy accepts canonical capabilities" {
  match parse_room_capability("/api/rooms/abcdefghijklmnopqrstuv") {
    Ok(value) => assert_eq(value, "abcdefghijklmnopqrstuv")
    Err(error) => fail(error)
  }
}

///|
test "room capability policy rejects short and unsafe values" {
  assert_true(parse_room_capability("/api/rooms/short") is Err(_))
  assert_true(
    parse_room_capability("/api/rooms/abcdefghijklmnopqrstuv/") is Err(_),
  )
  assert_true(
    parse_room_capability("/api/rooms/abcdefghijklmnopqrst?x=1") is Err(_),
  )
}

///|
test "room request policy checks method and same-site origin" {
  let path = "/api/rooms/abcdefghijklmnopqrstuv"
  assert_true(
    room_request_allowed(path, "GET", "", "http://localhost:8787", true)
    is Ok(_),
  )
  assert_true(
    room_request_allowed(path, "POST", "", "http://localhost:8787", true)
    is Err(_),
  )
  assert_true(
    room_request_allowed(
      path, "GET", "https://attacker.example", "http://localhost:8787", true,
    )
    is Err(_),
  )
  assert_true(
    room_request_allowed(path, "GET", "", "http://localhost:8787", false)
    is Err(_),
  )
  assert_true(
    room_request_allowed(
      path, "GET", "http://127.0.0.1:8787", "http://localhost:8787", true,
    )
    is Ok(_),
  )
}
