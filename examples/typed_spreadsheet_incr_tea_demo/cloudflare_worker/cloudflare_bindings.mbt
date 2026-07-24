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
/// JavaScript Promise returned by a Cloudflare fetch call.
#external
pub type JsPromise[X]

///|
/// Read the request URL.
extern "js" fn request_url(request : Request) -> String =
  #| request => request.url

///|
/// Read the room Durable Object namespace binding.
extern "js" fn room_namespace(env : Env) -> DurableObjectNamespace =
  #| env => env.ROOMS

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
/// Install the MoonBit handlers consumed by the module adapter.
extern "js" fn install_handlers(
  worker : (Request, Env, ExecutionContext) -> JsPromise[Response],
  room_fetch : (DurableObjectState, Request) -> Response,
) -> Unit =
  #| (worker, roomFetch) => {
  #|   globalThis.__typedSpreadsheetCloudflareWorker = { worker, roomFetch };
  #| }
