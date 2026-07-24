///|
/// PRODUCTION SKELETON: Worker and Durable Object route boundary.
fn room_name(request : Request) -> String? {
  match request_url(request).split_once("/api/rooms/") {
    Some((_, suffix)) if !suffix.is_empty() => Some(suffix.to_owned())
    _ => None
  }
}

///|
fn worker_fetch(
  request : Request,
  env : Env,
  _ctx : ExecutionContext,
) -> JsPromise[Response] {
  let url = request_url(request)
  if url.contains("/health") {
    return promise_response(response_text("cloudflare worker skeleton", 200))
  }
  match room_name(request) {
    Some(room) => {
      let stub = namespace_get_by_name(room_namespace(env), room)
      stub_fetch(stub, request)
    }
    None => promise_response(response_text("not found", 404))
  }
}

///|
extern "js" fn promise_response(response : Response) -> JsPromise[Response] =
  #| response => Promise.resolve(response)

///|
fn room_fetch(_state : DurableObjectState, _request : Request) -> Response {
  response_text("cloudflare room skeleton", 200)
}

///|
fn main {
  install_handlers(worker_fetch, room_fetch)
}
