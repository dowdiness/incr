///|
/// Pure room chooser state; document and transport state do not enter here.
enum RoomSelectionState {
  Choosing
  Created
}

///|
/// Browser-shell inputs after URL normalization or random generation.
enum RoomSelectionEvent {
  CreateGenerated(String, String, String)
  JoinSubmitted(String)
}

///|
/// Semantic room-selection failures formatted only by the browser shell.
enum RoomSelectionRejection {
  SecureRoomCreationFailed
  InvalidWebSocketInvitation
} derive(Eq, Debug)

///|
/// Shell work selected by the deterministic room chooser reducer.
enum RoomSelectionDecision {
  PresentCreated(StartupMode, StartupMode)
  Navigate(StartupMode)
  Reject(RoomSelectionRejection)
}

///|
/// Validates one room selection event without reading browser state.
fn reduce_room_selection(
  state : RoomSelectionState,
  event : RoomSelectionEvent,
) -> (RoomSelectionState, RoomSelectionDecision) {
  match (state, event) {
    (
      _,
      RoomSelectionEvent::CreateGenerated(
        capability,
        host_peer_text,
        join_peer_text
      ),
    ) => {
      let capability = match @collab_core.validate_room_capability(capability) {
        Ok(value) => value
        Err(_) =>
          return (
            state,
            RoomSelectionDecision::Reject(
              RoomSelectionRejection::SecureRoomCreationFailed,
            ),
          )
      }
      let host_peer = match parse_peer_id(host_peer_text) {
        Ok(peer) => peer
        Err(_) =>
          return (
            state,
            RoomSelectionDecision::Reject(
              RoomSelectionRejection::SecureRoomCreationFailed,
            ),
          )
      }
      let join_peer = match parse_peer_id(join_peer_text) {
        Ok(peer) => peer
        Err(_) =>
          return (
            state,
            RoomSelectionDecision::Reject(
              RoomSelectionRejection::SecureRoomCreationFailed,
            ),
          )
      }
      let host = StartupMode::Host(
        host_peer,
        capability,
        CollabTransportKind::WebSocket,
      )
      let invite = StartupMode::Join(
        join_peer,
        capability,
        CollabTransportKind::WebSocket,
      )
      (
        RoomSelectionState::Created,
        RoomSelectionDecision::PresentCreated(host, invite),
      )
    }
    (
      RoomSelectionState::Choosing,
      RoomSelectionEvent::JoinSubmitted(startup_input),
    )
    | (
      RoomSelectionState::Created,
      RoomSelectionEvent::JoinSubmitted(startup_input),
    ) =>
      match parse_startup(startup_input) {
        Ok(StartupMode::Join(peer, room, CollabTransportKind::WebSocket)) =>
          (
            state,
            RoomSelectionDecision::Navigate(
              StartupMode::Join(peer, room, CollabTransportKind::WebSocket),
            ),
          )
        _ =>
          (
            state,
            RoomSelectionDecision::Reject(
              RoomSelectionRejection::InvalidWebSocketInvitation,
            ),
          )
      }
  }
}
