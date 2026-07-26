///|
let room_selection_capability = "abcdefghijklmnopqrstuv"

///|
test "room selection creates distinct host and join websocket modes" {
  let (state, decision) = reduce_room_selection(
    RoomSelectionState::Choosing,
    RoomSelectionEvent::CreateGenerated(
      room_selection_capability, "host-peer", "join-peer",
    ),
  )
  assert_true(state is RoomSelectionState::Created)
  match decision {
    RoomSelectionDecision::PresentCreated(
      StartupMode::Host(host, host_room, host_transport),
      StartupMode::Join(joiner, join_room, join_transport)
    ) => {
      assert_eq(host.0, "host-peer")
      assert_eq(joiner.0, "join-peer")
      assert_eq(host_room, room_selection_capability)
      assert_eq(join_room, room_selection_capability)
      assert_true(host_transport is CollabTransportKind::WebSocket)
      assert_true(join_transport is CollabTransportKind::WebSocket)
    }
    _ => fail("create did not present websocket room modes")
  }
}

///|
test "room selection reports typed creation failure" {
  let (_, decision) = reduce_room_selection(
    RoomSelectionState::Choosing,
    RoomSelectionEvent::CreateGenerated("short", "host-peer", "join-peer"),
  )
  assert_true(
    decision
    is RoomSelectionDecision::Reject(
      RoomSelectionRejection::SecureRoomCreationFailed
    ),
  )
}

///|
test "room selection invitation validation fails closed" {
  let join = "/collab?role=join&room=abcdefghijklmnopqrstuv&peer=join&transport=websocket"
  let (_, accepted) = reduce_room_selection(
    RoomSelectionState::Choosing,
    RoomSelectionEvent::JoinSubmitted(join),
  )
  assert_true(accepted is RoomSelectionDecision::Navigate(_))
  let rejected = [
    "/collab?role=join&room=short&peer=join&transport=websocket", "/collab?role=host&room=abcdefghijklmnopqrstuv&peer=host&transport=websocket",
    "/collab?role=join&room=abcdefghijklmnopqrstuv&peer=join&transport=broadcast",
    "/collab?role=join&room=abcdefghijklmnopqrstuv&peer=one&peer=two&transport=websocket",
    "/collab?role=join&room=abcdefghijklmnopqrstuv/&peer=join&transport=websocket",
    "/collab", "not a URL",
  ]
  for value in rejected {
    let (_, decision) = reduce_room_selection(
      RoomSelectionState::Choosing,
      RoomSelectionEvent::JoinSubmitted(value),
    )
    assert_true(
      decision
      is RoomSelectionDecision::Reject(
        RoomSelectionRejection::InvalidWebSocketInvitation
      ),
    )
  }
}
