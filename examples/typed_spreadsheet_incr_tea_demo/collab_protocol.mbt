///|
/// Transport-only peer identity. It is never used as an EGW replica id.
struct PeerId(String) derive(Eq, Debug)

///|
/// EGW identity is generated independently for every page.
struct ReplicaId(String) derive(Eq, Debug)

///|
/// Startup configuration errors are shown without starting a document.
suberror StartupConfigError {
  InvalidPath(String)
  MissingRole
  InvalidRole(String)
  InvalidTransport(String)
  MissingRoom
  InvalidRoomCapability
  MissingPeer
  EmptyValue(String)
  DuplicateParameter(String)
  UnexpectedParameter(String)
}

///|
/// Protocol decoding errors are expected untrusted-input failures.
suberror CollabProtocolError {
  InvalidJson(String)
  InvalidShape
  InvalidTag(String)
  InvalidPeer(String)
  InvalidRoom(String)
  InvalidSheet
  InvalidGeneration(String)
  InvalidNode
  InvalidSync(String)
  WrongSchema
}

///|
/// The browser transport selected at the imperative shell boundary.
enum CollabTransportKind {
  Broadcast
  WebSocket
} derive(Eq, Debug)

///|
/// The only supported startup modes.
enum StartupMode {
  Standalone
  RoomChooser
  Host(PeerId, String, CollabTransportKind)
  Join(PeerId, String, CollabTransportKind)
} derive(Eq, Debug)

///|
/// Authority inputs selected by the collaboration shell before app creation.
enum SheetStartMode {
  Standalone
  Host(String, ReplicaId)
  Join(BootstrapData, @container.Document)
}

///|
/// Tagged transport messages for this demo only.
enum CollabMessage {
  Join(PeerId)
  Bootstrap(
    PeerId,
    PeerId,
    @core.CollaborativeSheetId,
    @typed_spreadsheet.SheetId,
    @domain.DocumentGeneration,
    @container.TreeNodeId,
    @container.SyncMessage
  )
  Ops(PeerId, PeerId, @container.SyncMessage)
}

///|
/// Bootstrap state retained by the pure reducer.
struct BootstrapData {
  identity : @core.CollaborativeSheetId
  sheet_id : @typed_spreadsheet.SheetId
  generation : @domain.DocumentGeneration
  node : @container.TreeNodeId
  sync : @container.SyncMessage
}

///|
/// Collaboration lifecycle phases.
enum CollabPhase {
  StartingHost
  Hosting
  AwaitingBootstrap
  Attaching
  Attached
  Failed
  Closed
} derive(Eq, Debug)

///|
/// Events entering the collaboration reducer.
enum CollabEvent {
  Incoming(CollabMessage)
  LocalCommitted(@container.SyncMessage)
  HostStartSucceeded(BootstrapData)
  HostStartFailed(String)
  AttachSucceeded
  AttachFailed(String)
  TransportFailed(String)
  RemoteApplySucceeded
  RemoteApplyFailed(String)
  CloseRequested
}

///|
/// Effects emitted by the pure collaboration reducer.
enum CollabDecision {
  NoEffect
  Send(CollabMessage)
  Attach(BootstrapData)
  Apply(@container.SyncMessage)
  Mount
  Fail(String)
  Stop
}

///|
/// Reducer state. No DOM, channel, runtime, or mutable adapter is retained.
struct CollabState {
  phase : CollabPhase
  local_peer : PeerId
  remote_peer : PeerId?
  bootstrap : BootstrapData?
}

///|
/// Constructs a host reducer before its local adapter starts.
fn CollabState::starting_host(local_peer : PeerId) -> CollabState {
  {
    phase: CollabPhase::StartingHost,
    local_peer,
    remote_peer: None,
    bootstrap: None,
  }
}

///|
/// Constructs a join reducer that cannot mount before bootstrap.
fn CollabState::join(local_peer : PeerId) -> CollabState {
  {
    phase: CollabPhase::AwaitingBootstrap,
    local_peer,
    remote_peer: None,
    bootstrap: None,
  }
}

///|
/// Applies one deterministic collaboration event and emits one shell effect.
fn reduce_collab(
  state : CollabState,
  event : CollabEvent,
) -> (CollabState, CollabDecision) {
  match (state.phase, event) {
    (CollabPhase::Closed, CollabEvent::CloseRequested) =>
      (state, CollabDecision::NoEffect)
    (_, CollabEvent::CloseRequested) =>
      ({ ..state, phase: CollabPhase::Closed }, CollabDecision::Stop)
    (CollabPhase::Failed, CollabEvent::TransportFailed(_))
    | (CollabPhase::Closed, CollabEvent::TransportFailed(_)) =>
      (state, CollabDecision::NoEffect)
    (_, CollabEvent::TransportFailed(error)) =>
      ({ ..state, phase: CollabPhase::Failed }, CollabDecision::Fail(error))
    (CollabPhase::StartingHost, CollabEvent::HostStartSucceeded(bootstrap)) =>
      (
        { ..state, phase: CollabPhase::Hosting, bootstrap: Some(bootstrap) },
        CollabDecision::Mount,
      )
    (CollabPhase::StartingHost, CollabEvent::HostStartFailed(error)) =>
      ({ ..state, phase: CollabPhase::Failed }, CollabDecision::Fail(error))
    (CollabPhase::Hosting, CollabEvent::Incoming(CollabMessage::Join(peer))) =>
      match state.bootstrap {
        Some(payload) => {
          let message = CollabMessage::Bootstrap(
            peer,
            state.local_peer,
            payload.identity,
            payload.sheet_id,
            payload.generation,
            payload.node,
            payload.sync,
          )
          (
            { ..state, phase: CollabPhase::Attached, remote_peer: Some(peer) },
            CollabDecision::Send(message),
          )
        }
        None =>
          (
            { ..state, phase: CollabPhase::Failed },
            CollabDecision::Fail("host bootstrap is missing"),
          )
      }
    (
      CollabPhase::AwaitingBootstrap,
      CollabEvent::Incoming(
        CollabMessage::Bootstrap(
          target,
          source,
          identity,
          sheet_id,
          generation,
          node,
          sync
        )
      ),
    ) if target == state.local_peer => {
      let payload = BootstrapData::{
        identity,
        sheet_id,
        generation,
        node,
        sync,
      }
      (
        {
          ..state,
          phase: CollabPhase::Attaching,
          remote_peer: Some(source),
          bootstrap: None,
        },
        CollabDecision::Attach(payload),
      )
    }
    (
      CollabPhase::AwaitingBootstrap,
      CollabEvent::Incoming(CollabMessage::Ops(_, _, _)),
    ) => (state, CollabDecision::NoEffect)
    (
      CollabPhase::AwaitingBootstrap,
      CollabEvent::Incoming(CollabMessage::Bootstrap(_, _, _, _, _, _, _)),
    ) => (state, CollabDecision::NoEffect)
    (CollabPhase::Hosting, CollabEvent::LocalCommitted(sync)) =>
      match state.bootstrap {
        Some(bootstrap) =>
          (
            { ..state, bootstrap: Some({ ..bootstrap, sync, }) },
            CollabDecision::NoEffect,
          )
        None =>
          (
            { ..state, phase: CollabPhase::Failed },
            CollabDecision::Fail("host bootstrap is missing"),
          )
      }
    (CollabPhase::Attaching, CollabEvent::AttachSucceeded) =>
      ({ ..state, phase: CollabPhase::Attached }, CollabDecision::Mount)
    (CollabPhase::Attaching, CollabEvent::AttachFailed(error)) =>
      ({ ..state, phase: CollabPhase::Failed }, CollabDecision::Fail(error))
    (
      CollabPhase::Attached,
      CollabEvent::Incoming(CollabMessage::Ops(target, source, sync)),
    ) if target == state.local_peer && state.remote_peer == Some(source) =>
      (state, CollabDecision::Apply(sync))
    (CollabPhase::Attached, CollabEvent::LocalCommitted(sync)) =>
      match state.remote_peer {
        Some(peer) =>
          (
            state,
            CollabDecision::Send(
              CollabMessage::Ops(peer, state.local_peer, sync),
            ),
          )
        None => (state, CollabDecision::NoEffect)
      }
    (CollabPhase::Attached, CollabEvent::RemoteApplySucceeded) =>
      (state, CollabDecision::NoEffect)
    (CollabPhase::Attached, CollabEvent::RemoteApplyFailed(error)) =>
      ({ ..state, phase: CollabPhase::Failed }, CollabDecision::Fail(error))
    (
      CollabPhase::Attached,
      CollabEvent::Incoming(CollabMessage::Bootstrap(_, _, _, _, _, _, _)),
    ) => (state, CollabDecision::NoEffect)
    (CollabPhase::Hosting, CollabEvent::Incoming(CollabMessage::Ops(_, _, _))) =>
      (state, CollabDecision::NoEffect)
    (CollabPhase::StartingHost, CollabEvent::Incoming(_))
    | (
      CollabPhase::Hosting,
      CollabEvent::Incoming(CollabMessage::Bootstrap(_, _, _, _, _, _, _)),
    ) => (state, CollabDecision::NoEffect)
    (
      CollabPhase::AwaitingBootstrap,
      CollabEvent::Incoming(CollabMessage::Join(_)),
    )
    | (CollabPhase::Attaching, CollabEvent::Incoming(_))
    | (CollabPhase::Attached, CollabEvent::Incoming(CollabMessage::Join(_)))
    | (CollabPhase::Attached, CollabEvent::Incoming(CollabMessage::Ops(_, _, _))
    ) => (state, CollabDecision::NoEffect)
    (CollabPhase::Failed, _) | (CollabPhase::Closed, _) =>
      (state, CollabDecision::NoEffect)
    (_, CollabEvent::RemoteApplySucceeded)
    | (_, CollabEvent::RemoteApplyFailed(_))
    | (_, CollabEvent::LocalCommitted(_))
    | (_, CollabEvent::HostStartSucceeded(_))
    | (_, CollabEvent::HostStartFailed(_))
    | (_, CollabEvent::AttachSucceeded)
    | (_, CollabEvent::AttachFailed(_)) => (state, CollabDecision::NoEffect)
  }
}

///|
/// Parses a non-empty transport identity.
fn parse_peer_id(value : String) -> Result[PeerId, StartupConfigError] {
  let trimmed = value.trim()
  if trimmed.is_empty() {
    Err(StartupConfigError::EmptyValue("peer"))
  } else {
    Ok(PeerId(trimmed.to_owned()))
  }
}

///|
/// Parses the independent EGW replica identity.
fn parse_replica_id(value : String) -> Result[ReplicaId, StartupConfigError] {
  let trimmed = value.trim()
  if trimmed.is_empty() {
    Err(StartupConfigError::EmptyValue("replica"))
  } else {
    Ok(ReplicaId(trimmed.to_owned()))
  }
}

///|
/// Parses the intentionally small `/collab` query contract.
fn parse_startup(raw : String) -> Result[StartupMode, StartupConfigError] {
  if raw == "/" || raw.is_empty() {
    return Ok(StartupMode::Standalone)
  }
  if raw == "/collab" {
    return Ok(StartupMode::RoomChooser)
  }
  let (path, query) = match raw.split_once("?") {
    Some(parts) => parts
    None => (raw, "")
  }
  if path != "/collab" {
    return Err(StartupConfigError::InvalidPath(path.to_owned()))
  }
  let mut role : String? = None
  let mut room : String? = None
  let mut peer : String? = None
  let mut transport : String? = None
  for pair in query.split("&") {
    if pair.is_empty() {
      continue
    }
    let (key, value) = match pair.split_once("=") {
      Some(parts) => parts
      None =>
        return Err(StartupConfigError::UnexpectedParameter(pair.to_owned()))
    }
    match key {
      "role" =>
        match role {
          Some(_) => return Err(StartupConfigError::DuplicateParameter("role"))
          None => role = Some(value.to_owned())
        }
      "room" =>
        match room {
          Some(_) => return Err(StartupConfigError::DuplicateParameter("room"))
          None => room = Some(value.to_owned())
        }
      "peer" =>
        match peer {
          Some(_) => return Err(StartupConfigError::DuplicateParameter("peer"))
          None => peer = Some(value.to_owned())
        }
      "transport" =>
        match transport {
          Some(_) =>
            return Err(StartupConfigError::DuplicateParameter("transport"))
          None => transport = Some(value.to_owned())
        }
      _ => return Err(StartupConfigError::UnexpectedParameter(key.to_owned()))
    }
  }
  let role = match role {
    Some(value) => value
    None => return Err(StartupConfigError::MissingRole)
  }
  let room = match room {
    Some(value) if !value.trim().is_empty() => value
    Some(_) => return Err(StartupConfigError::MissingRoom)
    None => return Err(StartupConfigError::MissingRoom)
  }
  let peer = match peer {
    Some(value) =>
      match parse_peer_id(value) {
        Ok(peer) => peer
        Err(error) => return Err(error)
      }
    None => return Err(StartupConfigError::MissingPeer)
  }
  let transport = match transport {
    None | Some("broadcast") => CollabTransportKind::Broadcast
    Some("websocket") => CollabTransportKind::WebSocket
    Some(value) => return Err(StartupConfigError::InvalidTransport(value))
  }
  let room = room.trim().to_owned()
  if transport is CollabTransportKind::WebSocket {
    match @collab_core.validate_room_capability(room) {
      Err(_) => return Err(StartupConfigError::InvalidRoomCapability)
      Ok(_) => ()
    }
  }
  match role {
    "host" => Ok(StartupMode::Host(peer, room, transport))
    "join" => Ok(StartupMode::Join(peer, room, transport))
    value => Err(StartupConfigError::InvalidRole(value))
  }
}

///|
/// Returns a tagged JSON-array transport envelope.
fn message_to_json(message : CollabMessage) -> String {
  let schema = Json::string("typed-sheet-collab/1")
  match message {
    CollabMessage::Join(peer) =>
      Json::array([schema, Json::string("join"), Json::string(peer.0)]).stringify()
    CollabMessage::Bootstrap(
      target,
      source,
      identity,
      _sheet_id,
      _generation,
      node,
      sync
    ) =>
      Json::array([
        schema,
        Json::string("bootstrap"),
        Json::string(target.0),
        Json::string(source.0),
        Json::string(identity.value()),
        Json::number(1.0),
        Json::string("initial"),
        Json::array([
          Json::string(node.replica_id()),
          Json::number(node.sequence().to_double()),
        ]),
        Json::string(sync.to_json_string()),
      ]).stringify()
    CollabMessage::Ops(target, source, sync) =>
      Json::array([
        schema,
        Json::string("ops"),
        Json::string(target.0),
        Json::string(source.0),
        Json::string(sync.to_json_string()),
      ]).stringify()
  }
}

///|
/// Reads one required JSON string while retaining a typed protocol error.
fn required_string(
  values : Array[Json],
  index : Int,
) -> String raise CollabProtocolError {
  guard index >= 0 && index < values.length() else {
    raise CollabProtocolError::InvalidShape
  }
  match values[index] {
    Json::String(value) => value
    _ => raise CollabProtocolError::InvalidShape
  }
}

///|
/// Decodes the tagged JSON-array transport envelope exactly once.
fn message_from_json(
  raw : String,
) -> Result[CollabMessage, CollabProtocolError] {
  let root = @json.parse(raw) catch {
    _ => return Err(CollabProtocolError::InvalidJson("malformed JSON"))
  }
  let values = match root {
    Json::Array(values) => values
    _ => return Err(CollabProtocolError::InvalidShape)
  }
  if values.length() < 2 {
    return Err(CollabProtocolError::InvalidShape)
  }
  let schema = match values[0] {
    Json::String(value) => value
    _ => return Err(CollabProtocolError::WrongSchema)
  }
  if schema != "typed-sheet-collab/1" {
    return Err(CollabProtocolError::WrongSchema)
  }
  let tag = match values[1] {
    Json::String(value) => value
    _ => return Err(CollabProtocolError::InvalidShape)
  }
  match tag {
    "join" => {
      if values.length() != 3 {
        return Err(CollabProtocolError::InvalidShape)
      }
      let peer_text : String = required_string(values, 2) catch {
        _ => return Err(CollabProtocolError::InvalidShape)
      }
      match parse_peer_id(peer_text) {
        Ok(peer) => Ok(CollabMessage::Join(peer))
        Err(_) => Err(CollabProtocolError::InvalidPeer("join"))
      }
    }
    "ops" => {
      if values.length() != 5 {
        return Err(CollabProtocolError::InvalidShape)
      }
      let target_text : String = required_string(values, 2) catch {
        _ => return Err(CollabProtocolError::InvalidShape)
      }
      let source_text : String = required_string(values, 3) catch {
        _ => return Err(CollabProtocolError::InvalidShape)
      }
      let sync_json : String = required_string(values, 4) catch {
        _ => return Err(CollabProtocolError::InvalidShape)
      }
      let sync = @container.SyncMessage::from_json_string(sync_json) catch {
        _ => return Err(CollabProtocolError::InvalidSync("invalid sync"))
      }
      let target = match parse_peer_id(target_text) {
        Ok(peer) => peer
        Err(_) => return Err(CollabProtocolError::InvalidPeer("target"))
      }
      let source = match parse_peer_id(source_text) {
        Ok(peer) => peer
        Err(_) => return Err(CollabProtocolError::InvalidPeer("source"))
      }
      Ok(CollabMessage::Ops(target, source, sync))
    }
    "bootstrap" => {
      if values.length() != 9 {
        return Err(CollabProtocolError::InvalidShape)
      }
      let target_text : String = required_string(values, 2) catch {
        _ => return Err(CollabProtocolError::InvalidShape)
      }
      let source_text : String = required_string(values, 3) catch {
        _ => return Err(CollabProtocolError::InvalidShape)
      }
      let identity : String = required_string(values, 4) catch {
        _ => return Err(CollabProtocolError::InvalidShape)
      }
      let generation : String = required_string(values, 6) catch {
        _ => return Err(CollabProtocolError::InvalidShape)
      }
      if generation != "initial" {
        return Err(CollabProtocolError::InvalidGeneration(generation))
      }
      let sheet_id = match values[5] {
        Json::Number(value, ..) if value == 1.0 => @typed_spreadsheet.SheetId(1)
        _ => return Err(CollabProtocolError::InvalidSheet)
      }
      let node_values = match values[7] {
        Json::Array(values) if values.length() == 2 => values
        _ => return Err(CollabProtocolError::InvalidNode)
      }
      let replica = match node_values[0] {
        Json::String(value) => value
        _ => return Err(CollabProtocolError::InvalidNode)
      }
      let sequence = match node_values[1] {
        Json::Number(value, ..) if value == value.to_int().to_double() =>
          value.to_int()
        _ => return Err(CollabProtocolError::InvalidNode)
      }
      let node = @container.TreeNodeId::TreeNodeId(replica, sequence) catch {
        _ => return Err(CollabProtocolError::InvalidNode)
      }
      let sync_json : String = required_string(values, 8) catch {
        _ => return Err(CollabProtocolError::InvalidShape)
      }
      let sync = @container.SyncMessage::from_json_string(sync_json) catch {
        _ => return Err(CollabProtocolError::InvalidSync("invalid sync"))
      }
      let target = match parse_peer_id(target_text) {
        Ok(peer) => peer
        Err(_) => return Err(CollabProtocolError::InvalidPeer("target"))
      }
      let source = match parse_peer_id(source_text) {
        Ok(peer) => peer
        Err(_) => return Err(CollabProtocolError::InvalidPeer("source"))
      }
      if identity.trim().is_empty() {
        return Err(CollabProtocolError::InvalidRoom(identity))
      }
      Ok(
        CollabMessage::Bootstrap(
          target,
          source,
          @core.CollaborativeSheetId::CollaborativeSheetId(identity),
          sheet_id,
          @domain.DocumentGeneration::initial(),
          node,
          sync,
        ),
      )
    }
    value => Err(CollabProtocolError::InvalidTag(value))
  }
}
