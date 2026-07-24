/// PRODUCTION SKELETON: self-owned Cloudflare Worker binding surface.

///|
/// Request received by a Worker or Durable Object.
#external
pub type Request

///|
/// Response returned by a Worker or Durable Object.
#external
pub type Response

///|
/// Worker environment bindings.
#external
pub type Env

///|
/// Worker execution context.
#external
pub type ExecutionContext

///|
/// Durable Object state.
#external
pub type DurableObjectState

///|
/// Durable Object namespace binding.
#external
pub type DurableObjectNamespace

///|
/// Durable Object stub.
#external
pub type DurableObjectStub

///|
/// Cloudflare WebSocket pair.
#external
pub type WebSocketPair

///|
/// Cloudflare WebSocket connection.
#external
pub type WebSocket

///|
/// JavaScript Promise returned by a Cloudflare fetch call.
#external
pub type JsPromise[X]

///|
/// Read the normalized request pathname.
extern "js" fn request_pathname(request : Request) -> String =
  #| request => new URL(request.url).pathname

///|
/// Read the request method.
extern "js" fn request_method(request : Request) -> String =
  #| request => request.method

///|
/// Read the browser Origin header, or an empty string when absent.
extern "js" fn request_origin(request : Request) -> String =
  #| request => request.headers.get("Origin") ?? ""

///|
/// Read the request URL origin for same-site checks.
extern "js" fn request_url_origin(request : Request) -> String =
  #| request => new URL(request.url).origin

///|
/// Read the room Durable Object namespace binding.
extern "js" fn room_namespace(env : Env) -> DurableObjectNamespace =
  #| env => env.ROOMS

///|
/// Forward non-API requests to Workers Static Assets.
extern "js" fn assets_fetch(
  env : Env,
  request : Request,
) -> JsPromise[Response] =
  #| (env, request) => env.ASSETS.fetch(request)

///|
/// Resolve a Durable Object by its canonical room name.
extern "js" fn namespace_get_by_name(
  room_namespace : DurableObjectNamespace,
  name : String,
) -> DurableObjectStub =
  #| (roomNamespace, name) => roomNamespace.getByName(name)

///|
/// Forward a request to a Durable Object.
extern "js" fn stub_fetch(
  stub : DurableObjectStub,
  request : Request,
) -> JsPromise[Response] =
  #| (stub, request) => stub.fetch(request)

///|
/// Construct a plain text response.
extern "js" fn response_text(body : String, status : Int) -> Response =
  #| (body, status) => new Response(body, { status })

///|
/// Check whether a request asks for a WebSocket upgrade.
extern "js" fn is_websocket_upgrade(request : Request) -> Bool =
  #| request => request.headers.get("Upgrade")?.toLowerCase() === "websocket"

///|
/// Create the server/client pair used by a Durable Object upgrade.
extern "js" fn new_websocket_pair() -> WebSocketPair =
  #| () => new WebSocketPair()

///|
/// Get the client side of a WebSocket pair.
extern "js" fn pair_client(pair : WebSocketPair) -> WebSocket =
  #| pair => pair[0]

///|
/// Get the server side of a WebSocket pair.
extern "js" fn pair_server(pair : WebSocketPair) -> WebSocket =
  #| pair => pair[1]

///|
/// Accept a server WebSocket through the Hibernation API.
extern "js" fn accept_websocket(
  state : DurableObjectState,
  socket : WebSocket,
) -> Unit =
  #| (state, socket) => state.acceptWebSocket(socket)

///|
/// Construct the 101 response for the client side of a WebSocket pair.
extern "js" fn response_websocket(socket : WebSocket) -> Response =
  #| socket => new Response(null, { status: 101, webSocket: socket })

///|
/// Count active room sockets using the Hibernation API.
extern "js" fn websocket_count(state : DurableObjectState) -> Int =
  #| state => state.getWebSockets().length

///|
/// Forward one bounded opaque text frame to every other room socket.
extern "js" fn broadcast_text(
  state : DurableObjectState,
  sender : WebSocket,
  message : String,
  max_bytes : Int,
) -> Bool =
  #| (state, sender, message, maxBytes) => {
  #|   if (new TextEncoder().encode(message).byteLength > maxBytes) return false;
  #|   for (const socket of state.getWebSockets()) {
  #|     if (socket !== sender) socket.send(message);
  #|   }
  #|   return true;
  #| }

///|
/// Initialize bounded per-connection rate metadata for Hibernation.
extern "js" fn initialize_rate_state(socket : WebSocket) -> Unit =
  #| socket => socket.serializeAttachment({ windowStart: Date.now(), count: 0 })

///|
/// Consume one message from a bounded per-connection rate window.
extern "js" fn allow_rate_message(
  socket : WebSocket,
  window_ms : Int,
  max_messages : Int,
) -> Bool =
  #| (socket, windowMs, maxMessages) => {
  #|   const now = Date.now();
  #|   const previous = socket.deserializeAttachment() ?? { windowStart: now, count: 0 };
  #|   const state = now - previous.windowStart >= windowMs
  #|     ? { windowStart: now, count: 0 }
  #|     : previous;
  #|   if (state.count >= maxMessages) {
  #|     socket.serializeAttachment(state);
  #|     return false;
  #|   }
  #|   state.count += 1;
  #|   socket.serializeAttachment(state);
  #|   return true;
  #| }

///|
/// Close a WebSocket with a protocol/size/rate error.
extern "js" fn close_websocket(
  socket : WebSocket,
  code : Int,
  reason : String,
) -> Unit =
  #| (socket, code, reason) => socket.close(code, reason)

///|
/// Install the MoonBit handlers consumed by the module adapter.
extern "js" fn install_handlers(
  worker : (Request, Env, ExecutionContext) -> JsPromise[Response],
  room_fetch : (DurableObjectState, Request) -> Response,
  room_message : (DurableObjectState, WebSocket, String) -> Unit,
) -> Unit =
  #| (worker, roomFetch, roomMessage) => {
  #|   globalThis.__typedSpreadsheetCloudflareWorker = {
  #|     worker,
  #|     roomFetch,
  #|     roomMessage,
  #|   };
  #| }
