///|
priv struct ActiveQuery {
  id : QueryId
  definition_site : String
}

///|
/// The private state captured by one root evaluation.
priv struct EvalSession {
  owner : StoreId
  change_epoch : ChangeEpoch
  active_stack : Array[ActiveQuery]
  max_active_queries : UInt?
  active : Ref[Bool]
}

///|
/// A tracked read capability valid only during one Query invocation.
pub struct QueryContext {
  priv session : EvalSession
  priv invocation : Ref[Bool]
  priv frame : Ref[TrackingFrame?]
  priv first_failure : Ref[ReadError?]
}

///|
fn QueryContext::root(session : EvalSession) -> QueryContext {
  { session, invocation: Ref(true), frame: Ref(None), first_failure: Ref(None) }
}

///|
fn QueryContext::child(self : QueryContext) -> QueryContext {
  {
    session: self.session,
    invocation: Ref(true),
    frame: Ref(Some([])),
    first_failure: Ref(None),
  }
}

///|
fn QueryContext::expire(self : QueryContext) -> Unit {
  self.invocation.val = false
  self.frame.val = None
  self.first_failure.val = None
}

///|
fn QueryContext::take_frame(self : QueryContext) -> TrackingFrame {
  match self.frame.val {
    Some(frame) => {
      self.frame.val = None
      frame
    }
    None => []
  }
}

///|
fn QueryContext::expired(self : QueryContext) -> ReadError? {
  if !self.session.active.val || !self.invocation.val {
    Some(read_expired_context())
  } else {
    None
  }
}

///|
fn[T] QueryContext::poison(
  self : QueryContext,
  error : ReadError,
) -> T raise ReadError {
  if self.first_failure.val is None {
    self.first_failure.val = Some(error)
  }
  raise error
}

///|
/// Gets a nested View, records its dependency, and raises structural failure.
pub fn[V] QueryContext::get(
  self : QueryContext,
  view : View[V],
) -> V raise ReadError {
  match self.expired() {
    Some(error) => raise error
    None =>
      match self.first_failure.val {
        Some(error) => raise error
        None =>
          match self.get_result(view) {
            Ok(value) => value
            Err(error) => self.poison(error)
          }
      }
  }
}

///|
/// Gets a nested View as a Result for the kernel's memoization shell.
fn[V] QueryContext::get_result(
  self : QueryContext,
  view : View[V],
) -> Result[V, ReadError] {
  match self.expired() {
    Some(error) => Err(error)
    None =>
      if view.owner != self.session.owner {
        Err(read_query_context_cross_store())
      } else {
        match (view.recipe)(self) {
          Ok(value) => {
            match self.frame.val {
              Some(frame) =>
                frame.push({
                  kind: view.dependency_kind,
                  verifier: view.verifier,
                })
              None => ()
            }
            Ok(value)
          }
          Err(error) => Err(error)
        }
      }
  }
}
