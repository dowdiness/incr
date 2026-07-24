///|
/// PRODUCTION SKELETON: Worker and Durable Object route boundary.

///|
fn worker_fetch(
  request : Request,
  env : Env,
  _ctx : ExecutionContext,
) -> JsPromise[Response] {
  let pathname = request_pathname(request)
  if pathname == "/health" {
    return promise_response(response_text("cloudflare worker skeleton", 200))
  }
  if !is_room_path(pathname) {
    return assets_fetch(env, request)
  }
  match
    room_request_allowed(
      pathname,
      request_method(request),
      request_origin(request),
      request_url_origin(request),
    ) {
    Ok(room) => {
      let stub = namespace_get_by_name(room_namespace(env), room)
      stub_fetch(stub, request)
    }
    Err(error) => promise_response(response_text(error, 400))
  }
}

///|
extern "js" fn promise_response(response : Response) -> JsPromise[Response] =
  #| response => Promise.resolve(response)

///|
const MAX_ROOM_CONNECTIONS : Int = 2

///|
const MAX_MESSAGE_BYTES : Int = 256 * 1024

///|
const RATE_WINDOW_MS : Int = 10_000

///|
const MAX_MESSAGES_PER_WINDOW : Int = 60

///|
fn room_fetch(state : DurableObjectState, request : Request) -> Response {
  if !is_websocket_upgrade(request) {
    return response_text("cloudflare room skeleton", 200)
  }
  if websocket_count(state) >= MAX_ROOM_CONNECTIONS {
    return response_text("room is full", 429)
  }
  let pair = new_websocket_pair()
  let client = pair_client(pair)
  let server = pair_server(pair)
  accept_websocket(state, server)
  initialize_rate_state(server)
  response_websocket(client)
}

///|
fn room_message(
  state : DurableObjectState,
  sender : WebSocket,
  message : String,
) -> Unit {
  if !allow_rate_message(sender, RATE_WINDOW_MS, MAX_MESSAGES_PER_WINDOW) {
    close_websocket(sender, 1013, "rate limit exceeded")
    return
  }
  if !broadcast_text(state, sender, message, MAX_MESSAGE_BYTES) {
    close_websocket(sender, 1009, "message too large")
  }
}

///|
fn main {
  install_handlers(worker_fetch, room_fetch, room_message)
}
