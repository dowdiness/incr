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
) -> JoinRetryHandle =
  #| (transport, message) => {
  #|   const timer = globalThis.setInterval(() => transport.retryIfOpen(message), 250);
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
  mut app : TypedSheetApp?
  mut renderer : @tea.BrowserRenderer[Msg]?
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
    MissingPeer => "Collaboration requires a non-empty peer id."
    EmptyValue(name) => "Collaboration value is empty: \{name}."
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
/// Update a mounted status through its reactive root, never by DOM mutation.
fn collab_show_owner_status(owner : Ref[CollabOwner], text : String) -> Unit {
  match owner.val.app {
    Some(app) => {
      app._state.val.status.set(text)
      match owner.val.renderer {
        Some(renderer) => renderer.flush_all()
        None => ()
      }
    }
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
  match (owner.val.app, owner.val.renderer) {
    (Some(app), Some(renderer)) => {
      mount_typed_sheet_app("app", app, renderer)
      renderer.flush_all()
    }
    _ => js_collab_show_status("Collaboration is not ready to mount.")
  }
}

///|
/// Install local publication after app creation, never for remote apply.
fn collab_install_app(owner : Ref[CollabOwner], app : TypedSheetApp) -> Unit {
  owner.val.app = Some(app)
  match owner.val.app {
    Some(app) =>
      app.set_publisher(sync => {
        collab_reduce(owner, CollabEvent::LocalCommitted(sync))
      })
    None => ()
  }
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
      collab_stop_join_retry(owner)
      match owner.val.app {
        Some(app) => app._state.val.publish_sync = None
        None => ()
      }
      collab_show_owner_status(
        owner,
        "Collaboration unavailable; edits are now local only: \{error}",
      )
      if !owner.val.transport_closed {
        js_collab_close(owner.val.transport)
        owner.val.transport_closed = true
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
      let runtime = @incr.Runtime()
      let app = Ok(
        TypedSheetApp::with_mode(
          runtime,
          SheetStartMode::Join(payload, document),
        ),
      ) catch {
        _ => Err("The joiner could not attach the synchronized document.")
      }
      match app {
        Err(error) => collab_reduce(owner, CollabEvent::AttachFailed(error))
        Ok(app) => {
          let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
          owner.val.renderer = Some(renderer)
          collab_install_app(owner, app)
          collab_reduce(owner, CollabEvent::AttachSucceeded)
        }
      }
    }
  }
}

///|
/// Apply a remote message and fail closed if projection cannot complete.
fn collab_apply_remote(
  owner : Ref[CollabOwner],
  message : @container.SyncMessage,
) -> Unit {
  match owner.val.app {
    Some(app) => {
      let applied : Result[Unit, String] = try {
        let result = app.apply_remote(message)
        match result.adapter_result() {
          @egw_adapter.AdapterApplyResult::ProjectionFailed(_) =>
            Err("Remote projection failed; collaboration stopped.")
          @egw_adapter.AdapterApplyResult::MutationNotLanded =>
            Err("Remote mutation did not land; collaboration stopped.")
          _ => Ok(())
        }
      } catch {
        _ => Err("Remote synchronization failed; collaboration stopped.")
      }
      match applied {
        Ok(_) => {
          collab_reduce(owner, CollabEvent::RemoteApplySucceeded)
          match owner.val.renderer {
            Some(renderer) => renderer.flush_all()
            None => ()
          }
        }
        Err(error) =>
          collab_reduce(owner, CollabEvent::RemoteApplyFailed(error))
      }
    }
    None =>
      collab_reduce(
        owner,
        CollabEvent::RemoteApplyFailed("Remote update arrived before attach."),
      )
  }
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
  collab_stop_join_retry(owner)
  if !owner.val.transport_closed {
    js_collab_close(owner.val.transport)
    owner.val.transport_closed = true
  }
  js_collab_remove_lifecycle(owner.val.lifecycle)
  match owner.val.renderer {
    Some(renderer) => {
      renderer.flush_all()
      renderer.dispose()
    }
    None => ()
  }
  match owner.val.app {
    Some(app) => app.dispose()
    None => ()
  }
  owner.val.renderer = None
  owner.val.app = None
}

///|
/// Start the fixed same-origin two-page collaboration prototype.
fn start_collaboration(mode : StartupMode) -> Unit {
  let (local_peer, room, transport_kind) = match mode {
    StartupMode::Host(peer, room, transport)
    | StartupMode::Join(peer, room, transport) => (peer, room, transport)
    StartupMode::Standalone => return
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
    StartupMode::Standalone => return
  }
  let owner = Ref(CollabOwner::{
    state: initial_state,
    transport,
    lifecycle,
    app: None,
    renderer: None,
    join_retry: None,
    transport_closed: false,
    disposed: false,
  })
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
      let runtime = @incr.Runtime()
      let app = Ok(
        TypedSheetApp::with_mode(runtime, SheetStartMode::Host(room, replica)),
      ) catch {
        _ => Err("Host bootstrap failed.")
      }
      match app {
        Err(error) => collab_reduce(owner, CollabEvent::HostStartFailed(error))
        Ok(app) => {
          let sync = Ok(app._state.val.adapter.export_all()) catch {
            _ => Err("Host export failed.")
          }
          match sync {
            Err(error) => {
              app.dispose()
              collab_reduce(owner, CollabEvent::HostStartFailed(error))
            }
            Ok(sync) => {
              let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
              let bootstrap = BootstrapData::{
                identity: @core.CollaborativeSheetId::CollaborativeSheetId(room),
                sheet_id: @typed_spreadsheet.SheetId(1),
                generation: app._state.val.adapter.generation(),
                node: app._state.val.adapter.node(),
                sync,
              }
              owner.val.renderer = Some(renderer)
              collab_install_app(owner, app)
              collab_reduce(owner, CollabEvent::HostStartSucceeded(bootstrap))
            }
          }
        }
      }
    }
    StartupMode::Join(peer, _, transport_kind) => {
      js_collab_show_status("Waiting for host bootstrap…")
      collab_send(owner, CollabMessage::Join(peer))
      if transport_kind is CollabTransportKind::WebSocket {
        let retry_message = message_to_json(CollabMessage::Join(peer))
        owner.val.join_retry = Some(
          js_collab_start_join_retry(owner.val.transport, retry_message),
        )
      }
    }
    StartupMode::Standalone => ()
  }
}
