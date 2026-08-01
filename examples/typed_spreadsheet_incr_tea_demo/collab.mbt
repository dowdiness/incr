///|
/// Opaque transport owned by one collaboration shell.
#cfg(target="js")
#external
priv type CollabTransport

///|
/// Opaque page-lifecycle listener owned by one collaboration shell.
#cfg(target="js")
#external
priv type LifecycleHandle

///|
/// Opaque initial join retry timer owned by one collaboration shell.
#cfg(target="js")
#external
priv type JoinRetryHandle

///|
/// Read the startup URL once at the imperative boundary.
#cfg(target="js")
extern "js" fn js_collab_startup_input() -> String =
  #| () => `${globalThis.location.pathname}${globalThis.location.search}`

///|
/// Generate one browser-owned room capability without server coordination.
#cfg(target="js")
extern "js" fn js_collab_room_capability() -> String =
  #| () => globalThis.typedSpreadsheetCollabRoomShell.generateCapability()

///|
/// Generate a transport peer id independently from the document replica id.
#cfg(target="js")
extern "js" fn js_collab_peer_uuid() -> String =
  #| () => globalThis.typedSpreadsheetCollabRoomShell.generatePeerId()

///|
/// Normalize a same-origin invitation before the pure startup parser sees it.
#cfg(target="js")
extern "js" fn js_collab_normalize_invite_url(raw : String) -> String =
  #| raw => globalThis.typedSpreadsheetCollabRoomShell.normalizeInviteUrl(raw)

///|
/// Build one canonical same-origin WebSocket collaboration URL.
#cfg(target="js")
extern "js" fn js_collab_build_websocket_url(
  role : String,
  room : String,
  peer : String,
) -> String =
  #| (role, room, peer) => globalThis.typedSpreadsheetCollabRoomShell.buildWebSocketCollabUrl(role, room, peer)

///|
/// Mount the room chooser shell with keyboard-equivalent form callbacks.
#cfg(target="js")
extern "js" fn js_collab_mount_room_chooser(
  on_create : () -> Unit,
  on_join : (String) -> Unit,
) -> Unit =
  #| (onCreate, onJoin) => globalThis.typedSpreadsheetCollabRoomShell.mountRoomChooser(onCreate, onJoin)

///|
/// Reveal a generated invitation and its host navigation target.
#cfg(target="js")
extern "js" fn js_collab_present_created_room(
  host_url : String,
  invite_url : String,
) -> Unit =
  #| (hostUrl, inviteUrl) => globalThis.typedSpreadsheetCollabRoomShell.presentCreatedRoom(hostUrl, inviteUrl)

///|
/// Surface a chooser error at the action that caused it.
#cfg(target="js")
extern "js" fn js_collab_show_room_error(
  message : String,
  join_target : Bool,
) -> Unit =
  #| (message, joinTarget) => globalThis.typedSpreadsheetCollabRoomShell.showRoomChooserError(message, joinTarget)

///|
/// Navigate only to a URL reconstructed from validated startup data.
#cfg(target="js")
extern "js" fn js_collab_navigate(url : String) -> Unit =
  #| url => globalThis.typedSpreadsheetCollabRoomShell.navigate(url)

///|
/// Generate an EGW replica id independently from transport routing.
#cfg(target="js")
extern "js" fn js_collab_replica_uuid() -> String =
  #| () => globalThis.crypto.randomUUID()

///|
/// Display a startup/lifecycle status without creating an app.
#cfg(target="js")
extern "js" fn js_collab_show_status(text : String) -> Unit =
  #| text => {
  #|   const node = document.getElementById("app-status");
  #|   if (node) node.textContent = String(text);
  #| }

///|
/// Open either the local BroadcastChannel provider or the hosted WebSocket.
#cfg(target="js")
extern "js" fn js_collab_open(
  room : String,
  use_websocket : Bool,
  on_message : (String) -> Unit,
  on_failure : (String) -> Unit,
  on_close : () -> Unit,
) -> CollabTransport =
  #| (room, useWebSocket, onMessage, onFailure, onClose) => {
  #|   if (!useWebSocket) {
  #|     const channel = new BroadcastChannel(`typed-sheet-collab/${String(room)}`);
  #|     const listener = event => onMessage(String(event.data));
  #|     channel.addEventListener("message", listener);
  #|     let closed = false;
  #|     return {
  #|       send(message) { if (!closed) channel.postMessage(String(message)); },
  #|       retryIfOpen(message) { if (!closed) channel.postMessage(String(message)); },
  #|       close() {
  #|         if (closed) return;
  #|         closed = true;
  #|         channel.removeEventListener("message", listener);
  #|         channel.close();
  #|       },
  #|     };
  #|   }
  #|   const protocol = globalThis.location.protocol === "https:" ? "wss:" : "ws:";
  #|   const socket = new WebSocket(
  #|     `${protocol}//${globalThis.location.host}/api/rooms/${encodeURIComponent(String(room))}`,
  #|   );
  #|   const pending = [];
  #|   let closed = false;
  #|   const flush = () => {
  #|     while (socket.readyState === WebSocket.OPEN && pending.length > 0) {
  #|       socket.send(pending.shift());
  #|     }
  #|   };
  #|   socket.addEventListener("open", flush);
  #|   socket.addEventListener("message", event => onMessage(String(event.data)));
  #|   socket.addEventListener("error", () => onFailure("WebSocket transport failed."));
  #|   socket.addEventListener("close", () => onClose());
  #|   return {
  #|     send(message) {
  #|       if (closed) return;
  #|       if (socket.readyState === WebSocket.OPEN) socket.send(String(message));
  #|       else if (pending.length < 128) pending.push(String(message));
  #|       else {
  #|         closed = true;
  #|         pending.length = 0;
  #|         socket.close();
  #|         onFailure("WebSocket transport queue limit exceeded.");
  #|       }
  #|     },
  #|     retryIfOpen(message) {
  #|       if (!closed && socket.readyState === WebSocket.OPEN) socket.send(String(message));
  #|     },
  #|     close() {
  #|       if (closed) return;
  #|       closed = true;
  #|       pending.length = 0;
  #|       socket.close();
  #|     },
  #|   };
  #| }

///|
/// Send one already-encoded protocol envelope.
#cfg(target="js")
extern "js" fn js_collab_send(
  transport : CollabTransport,
  message : String,
) -> Unit =
  #| (transport, message) => transport.send(message)

///|
/// Stop transport delivery before releasing application state.
#cfg(target="js")
extern "js" fn js_collab_close(transport : CollabTransport) -> Unit =
  #| transport => transport.close()

///|
/// Retry an initial join only while its WebSocket is open.
#cfg(target="js")
extern "js" fn js_collab_start_join_retry(
  transport : CollabTransport,
  message : String,
  on_failure : (String) -> Unit,
) -> JoinRetryHandle =
  #| (transport, message, onFailure) => {
  #|   let attempts = 0;
  #|   const timer = globalThis.setInterval(() => {
  #|     attempts += 1;
  #|     if (attempts > 20) {
  #|       globalThis.clearInterval(timer);
  #|       onFailure("Host bootstrap timed out.");
  #|       return;
  #|     }
  #|     transport.retryIfOpen(message);
  #|   }, 250);
  #|   return { stop() { globalThis.clearInterval(timer); } };
  #| }

///|
/// Stop an initial join retry timer.
#cfg(target="js")
extern "js" fn js_collab_stop_join_retry(handle : JoinRetryHandle) -> Unit =
  #| handle => handle.stop()

///|
/// Install one close callback that can be removed during disposal.
#cfg(target="js")
extern "js" fn js_collab_install_lifecycle(
  on_close : () -> Unit,
) -> LifecycleHandle =
  #| onClose => {
  #|   const handler = () => onClose();
  #|   globalThis.addEventListener("pagehide", handler, { once: true });
  #|   return { remove() { globalThis.removeEventListener("pagehide", handler); } };
  #| }

///|
/// Remove the close listener before disposing app state.
#cfg(target="js")
extern "js" fn js_collab_remove_lifecycle(handle : LifecycleHandle) -> Unit =
  #| handle => handle.remove()

///|
/// Production owner for one page's app, renderer, callbacks, and lifecycle.
struct CollabOwner {
  mut state : CollabState
  transport : CollabTransport
  lifecycle : LifecycleHandle
  mut app : TypedSheetApplication?
  remote_apply : Ref[
    ((@container.SyncMessage) -> Result[Unit, ApplicationRemoteError])?,
  ]
  application_failure : Ref[((String) -> Unit)?]
  mut session_transport : SessionTransport?
  mut join_retry : JoinRetryHandle?
  mut transport_closed : Bool
  mut disposed : Bool
}

///|
/// Format a typed startup error at the user-visible boundary.
fn format_startup_error(error : StartupConfigError) -> String {
  match error {
    InvalidPath(path) => "Invalid collaboration path: \{path}."
    MissingRole => "Collaboration requires role=host or role=join."
    InvalidRole(role) => "Unsupported collaboration role: \{role}."
    InvalidTransport(transport) =>
      "Unsupported collaboration transport: \{transport}."
    MissingRoom => "Collaboration requires a non-empty room."
    InvalidRoomCapability => "Collaboration requires a valid room capability."
    MissingPeer => "Collaboration requires a non-empty peer id."
    EmptyValue(name) => "Collaboration value is empty: \{name}."
    DuplicateParameter(name) => "Duplicate collaboration parameter: \{name}."
    UnexpectedParameter(name) => "Unexpected collaboration parameter: \{name}."
  }
}

///|
/// Format a typed protocol failure without allowing it to escape a callback.
fn format_protocol_error(error : CollabProtocolError) -> String {
  match error {
    InvalidJson(_) => "Malformed collaboration message."
    InvalidShape => "Malformed collaboration message shape."
    InvalidTag(tag) => "Unknown collaboration message: \{tag}."
    InvalidPeer(_) => "Collaboration message has an invalid peer."
    InvalidRoom(_) => "Collaboration message has an invalid room."
    InvalidSheet => "Collaboration message has an invalid sheet."
    InvalidGeneration(_) => "Only the initial generation is supported."
    InvalidNode => "Collaboration bootstrap has an invalid node."
    InvalidSync(_) => "Collaboration bootstrap has invalid sync data."
    WrongSchema => "Unsupported collaboration message schema."
  }
}

///|
/// Format a typed chooser rejection only at the user-visible shell boundary.
fn format_room_selection_rejection(
  rejection : RoomSelectionRejection,
) -> String {
  match rejection {
    RoomSelectionRejection::SecureRoomCreationFailed =>
      "A secure room could not be created. Please try again."
    RoomSelectionRejection::InvalidWebSocketInvitation =>
      "Enter a valid WebSocket invitation link from this site."
  }
}

///|
/// Build a URL only from a validated WebSocket startup mode.
fn room_mode_url(mode : StartupMode) -> String {
  match mode {
    StartupMode::Host(peer, room, CollabTransportKind::WebSocket) =>
      js_collab_build_websocket_url("host", room, peer.0)
    StartupMode::Join(peer, room, CollabTransportKind::WebSocket) =>
      js_collab_build_websocket_url("join", room, peer.0)
    _ => ""
  }
}

///|
/// Execute one pure chooser decision at the browser boundary.
fn apply_room_selection_event(
  owner : Ref[RoomSelectionState],
  event : RoomSelectionEvent,
  join_target : Bool,
) -> Unit {
  let (state, decision) = reduce_room_selection(owner.val, event)
  owner.val = state
  match decision {
    RoomSelectionDecision::PresentCreated(host, invite) => {
      let host_url = room_mode_url(host)
      let invite_url = room_mode_url(invite)
      if host_url.is_empty() || invite_url.is_empty() {
        js_collab_show_room_error(
          "A secure room could not be created. Please try again.", false,
        )
      } else {
        js_collab_present_created_room(host_url, invite_url)
      }
    }
    RoomSelectionDecision::Navigate(mode) => {
      let url = room_mode_url(mode)
      if url.is_empty() {
        js_collab_show_room_error(
          "Enter a valid WebSocket invitation link from this site.", true,
        )
      } else {
        js_collab_navigate(url)
      }
    }
    RoomSelectionDecision::Reject(rejection) =>
      js_collab_show_room_error(
        format_room_selection_rejection(rejection),
        join_target,
      )
  }
}

///|
/// Mount the room selection shell before any document or transport exists.
fn show_room_chooser() -> Unit {
  let owner = Ref(RoomSelectionState::Choosing)
  js_collab_mount_room_chooser(
    () => {
      apply_room_selection_event(
        owner,
        RoomSelectionEvent::CreateGenerated(
          js_collab_room_capability(),
          js_collab_peer_uuid(),
          js_collab_peer_uuid(),
        ),
        false,
      )
    },
    raw => {
      apply_room_selection_event(
        owner,
        RoomSelectionEvent::JoinSubmitted(js_collab_normalize_invite_url(raw)),
        true,
      )
    },
  )
}

///|
/// Update a mounted status through its reactive root, never by DOM mutation.
fn collab_show_owner_status(owner : Ref[CollabOwner], text : String) -> Unit {
  match owner.val.app {
    Some(app) => app.record_collaboration_status(text)
    None => js_collab_show_status(text)
  }
}

///|
/// Send a reducer decision without touching reducer state.
fn collab_send(owner : Ref[CollabOwner], message : CollabMessage) -> Unit {
  if owner.val.disposed {
    return
  }
  js_collab_send(owner.val.transport, message_to_json(message))
}

///|
/// Mount an app only after the reducer reaches a mounted phase.
fn collab_mount(owner : Ref[CollabOwner]) -> Unit {
  let app = match owner.val.app {
    Some(app) => app
    None => {
      js_collab_show_status("Collaboration is not ready to mount.")
      return
    }
  }
  let hosts = match resolve_typed_sheet_hosts("app") {
    Ok(hosts) => hosts
    Err(MissingRegion(id)) => {
      js_collab_show_status("Collaboration region is missing: \{id}.")
      return
    }
  }
  match app.mount(hosts) {
    Ok(_) => ignore(app.flush_presentation())
    Err(_) => js_collab_show_status("Collaboration is not ready to mount.")
  }
}

///|
/// Install local publication after app creation, never for remote apply.
fn collab_install_app(
  owner : Ref[CollabOwner],
  app : TypedSheetApplication,
) -> Unit {
  owner.val.app = Some(app)
}

///|
/// Stop the initial join retry once bootstrap or failure resolves it.
fn collab_stop_join_retry(owner : Ref[CollabOwner]) -> Unit {
  match owner.val.join_retry {
    Some(handle) => {
      js_collab_stop_join_retry(handle)
      owner.val.join_retry = None
    }
    None => ()
  }
}

///|
fn collab_session_transport(
  owner : Ref[CollabOwner],
  receiver : Ref[(String) -> Unit],
  failure_handler : Ref[(String) -> Unit],
  close_handler : Ref[() -> Unit],
) -> SessionTransport {
  let stopped = Ref(false)
  SessionTransport::SessionTransport(
    (remote_apply, application_failure) => {
      if !stopped.val {
        owner.val.remote_apply.val = Some(remote_apply)
        owner.val.application_failure.val = Some(application_failure)
      }
    },
    sync => {
      if !stopped.val && !owner.val.disposed {
        collab_reduce(owner, CollabEvent::LocalCommitted(sync))
      }
    },
    () => {
      if stopped.val {
        return
      }
      stopped.val = true
      owner.val.remote_apply.val = None
      owner.val.application_failure.val = None
      receiver.val = _ => ()
      failure_handler.val = _ => ()
      close_handler.val = () => ()
      collab_stop_join_retry(owner)
      if !owner.val.transport_closed {
        js_collab_close(owner.val.transport)
        owner.val.transport_closed = true
      }
    },
  )
}

///|
/// Execute one reducer decision at the imperative shell boundary.
fn collab_decision(owner : Ref[CollabOwner], decision : CollabDecision) -> Unit {
  if owner.val.disposed {
    return
  }
  match decision {
    CollabDecision::NoEffect => ()
    CollabDecision::Send(message) => collab_send(owner, message)
    CollabDecision::Mount => collab_mount(owner)
    CollabDecision::Fail(error) => {
      match owner.val.application_failure.val {
        Some(application_failure) => application_failure(error)
        None =>
          js_collab_show_status(
            "Collaboration unavailable; edits are now local only: \{error}",
          )
      }
      match owner.val.session_transport {
        Some(transport) => (transport.stop)()
        None => ()
      }
    }
    CollabDecision::Attach(payload) => {
      collab_stop_join_retry(owner)
      collab_attach(owner, payload)
    }
    CollabDecision::Apply(message) => collab_apply_remote(owner, message)
    CollabDecision::Stop => ()
  }
}

///|
/// Reduce one event; this is the only path that advances lifecycle phase.
fn collab_reduce(owner : Ref[CollabOwner], event : CollabEvent) -> Unit {
  if owner.val.disposed {
    return
  }
  let (state, decision) = reduce_collab(owner.val.state, event)
  owner.val.state = state
  collab_decision(owner, decision)
}

///|
/// Fail closed on a join bootstrap before app or renderer creation.
fn collab_attach(owner : Ref[CollabOwner], payload : BootstrapData) -> Unit {
  let replica = match parse_replica_id(js_collab_replica_uuid()) {
    Ok(replica) => replica
    Err(error) => {
      collab_reduce(
        owner,
        CollabEvent::AttachFailed(format_startup_error(error)),
      )
      return
    }
  }
  let document = try {
    let document = @container.Document::new(replica.0)
    ignore(document.sync().apply(payload.sync))
    Ok(document)
  } catch {
    _ => Err("The host bootstrap could not be applied.")
  }
  match document {
    Err(error) => collab_reduce(owner, CollabEvent::AttachFailed(error))
    Ok(document) => {
      let transport = match owner.val.session_transport {
        Some(transport) => transport
        None => {
          collab_reduce(
            owner,
            CollabEvent::AttachFailed("The session transport is unavailable."),
          )
          return
        }
      }
      let app = TypedSheetApplication::start(
        @incr.Runtime(),
        SheetStartMode::Join(payload, document),
        Some(transport),
        AiContextPublisher::production(),
      )
      match app {
        Err(_) =>
          collab_reduce(
            owner,
            CollabEvent::AttachFailed(
              "The joiner could not attach the synchronized document.",
            ),
          )
        Ok(app) => {
          collab_install_app(owner, app)
          collab_reduce(owner, CollabEvent::AttachSucceeded)
        }
      }
    }
  }
}

///|
fn format_application_remote_error(error : ApplicationRemoteError) -> String {
  match error {
    ApplicationRemoteError::ProjectionFailed =>
      "Remote projection failed; collaboration stopped."
    ApplicationRemoteError::MutationNotLanded =>
      "Remote mutation did not land; collaboration stopped."
    ApplicationRemoteError::SynchronizationFailed(_) =>
      "Remote synchronization failed; collaboration stopped."
    ApplicationRemoteError::Disposed => "Remote update arrived before attach."
  }
}

///|
fn collab_remote_apply_event(
  result : Result[Unit, ApplicationRemoteError],
) -> CollabEvent {
  match result {
    Ok(_) => CollabEvent::RemoteApplySucceeded
    Err(error) =>
      CollabEvent::RemoteApplyFailed(format_application_remote_error(error))
  }
}

///|
fn collab_invoke_remote_apply(
  remote_apply : (@container.SyncMessage) -> Result[
    Unit,
    ApplicationRemoteError,
  ],
  message : @container.SyncMessage,
) -> CollabEvent {
  collab_remote_apply_event(remote_apply(message))
}

///|
/// Apply a remote message through the application callback exactly once.
fn collab_apply_remote(
  owner : Ref[CollabOwner],
  message : @container.SyncMessage,
) -> Unit {
  let event = match owner.val.remote_apply.val {
    Some(remote_apply) => collab_invoke_remote_apply(remote_apply, message)
    None => collab_remote_apply_event(Err(ApplicationRemoteError::Disposed))
  }
  collab_reduce(owner, event)
}

///|
/// Parse and dispatch one untrusted BroadcastChannel payload.
fn collab_receive(owner : Ref[CollabOwner], raw : String) -> Unit {
  if owner.val.disposed {
    return
  }
  match message_from_json(raw) {
    Ok(message) => collab_reduce(owner, CollabEvent::Incoming(message))
    Err(error) => collab_show_owner_status(owner, format_protocol_error(error))
  }
}

///|
/// Stop callbacks/channel first, then renderer/programs/adapter/scope.
fn collab_dispose(owner : Ref[CollabOwner]) -> Unit {
  if owner.val.disposed {
    return
  }
  let (closed_state, _) = reduce_collab(
    owner.val.state,
    CollabEvent::CloseRequested,
  )
  owner.val.state = closed_state
  owner.val.disposed = true
  match owner.val.session_transport {
    Some(transport) => (transport.stop)()
    None => ()
  }
  js_collab_remove_lifecycle(owner.val.lifecycle)
  match owner.val.app {
    Some(app) => app.dispose()
    None => ()
  }
  owner.val.app = None
  owner.val.session_transport = None
}

///|
/// Start the fixed same-origin two-page collaboration prototype.
fn start_collaboration(mode : StartupMode) -> Unit {
  let (local_peer, room, transport_kind) = match mode {
    StartupMode::Host(peer, room, transport)
    | StartupMode::Join(peer, room, transport) => (peer, room, transport)
    StartupMode::Standalone | StartupMode::RoomChooser => return
  }
  let receiver : Ref[(String) -> Unit] = Ref(_ => ())
  let failure_handler : Ref[(String) -> Unit] = Ref(_ => ())
  let close_handler : Ref[() -> Unit] = Ref(() => ())
  let transport = js_collab_open(
    room,
    transport_kind is CollabTransportKind::WebSocket,
    raw => (receiver.val)(raw),
    error => (failure_handler.val)(error),
    () => (failure_handler.val)("WebSocket transport closed."),
  )
  let lifecycle = js_collab_install_lifecycle(() => (close_handler.val)())
  let initial_state = match mode {
    StartupMode::Host(_, _, _) => CollabState::starting_host(local_peer)
    StartupMode::Join(_, _, _) => CollabState::join(local_peer)
    StartupMode::Standalone | StartupMode::RoomChooser => return
  }
  let owner = Ref(CollabOwner::{
    state: initial_state,
    transport,
    lifecycle,
    app: None,
    remote_apply: Ref(None),
    application_failure: Ref(None),
    session_transport: None,
    join_retry: None,
    transport_closed: false,
    disposed: false,
  })
  let session_transport = collab_session_transport(
    owner, receiver, failure_handler, close_handler,
  )
  owner.val.session_transport = Some(session_transport)
  receiver.val = raw => collab_receive(owner, raw)
  failure_handler.val = error => {
    collab_reduce(owner, CollabEvent::TransportFailed(error))
  }
  close_handler.val = () => collab_dispose(owner)
  let replica = match parse_replica_id(js_collab_replica_uuid()) {
    Ok(replica) => replica
    Err(error) => {
      collab_dispose(owner)
      js_collab_show_status(format_startup_error(error))
      return
    }
  }
  match mode {
    StartupMode::Host(_, room, _) => {
      let app = TypedSheetApplication::start(
        @incr.Runtime(),
        SheetStartMode::Host(room, replica),
        Some(session_transport),
        AiContextPublisher::production(),
      )
      match app {
        Err(_) =>
          collab_reduce(
            owner,
            CollabEvent::HostStartFailed("Host bootstrap failed."),
          )
        Ok(app) => {
          let bootstrap = match app.observe().collaboration {
            ApplicationCollaborationResult::BootstrapReady(bootstrap) =>
              bootstrap
            _ => {
              app.dispose()
              collab_reduce(
                owner,
                CollabEvent::HostStartFailed("Host export failed."),
              )
              return
            }
          }
          collab_install_app(owner, app)
          collab_reduce(owner, CollabEvent::HostStartSucceeded(bootstrap))
        }
      }
    }
    StartupMode::Join(peer, _, transport_kind) => {
      js_collab_show_status("Waiting for host bootstrap…")
      collab_send(owner, CollabMessage::Join(peer))
      if transport_kind is CollabTransportKind::WebSocket {
        let retry_message = message_to_json(CollabMessage::Join(peer))
        owner.val.join_retry = Some(
          js_collab_start_join_retry(owner.val.transport, retry_message, error => {
            (failure_handler.val)(error)
          }),
        )
      }
    }
    StartupMode::Standalone | StartupMode::RoomChooser => ()
  }
}
