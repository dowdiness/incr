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
  active : Ref[Bool]
}

///|
/// A tracked read capability valid only during one Query invocation.
pub struct QueryContext {
  priv session : EvalSession
  priv invocation : Ref[Bool]
  priv frame : Ref[TrackingFrame?]
}

///|
fn QueryContext::root(session : EvalSession) -> QueryContext {
  { session, invocation: Ref(true), frame: Ref(None) }
}

///|
fn QueryContext::child(self : QueryContext) -> QueryContext {
  { session: self.session, invocation: Ref(true), frame: Ref(Some([])) }
}

///|
fn QueryContext::expire(self : QueryContext) -> Unit {
  self.invocation.val = false
  self.frame.val = None
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
/// Gets a nested View, records its dependency, and raises structural failure.
pub fn[V] QueryContext::get(
  self : QueryContext,
  view : View[V],
) -> V raise ReadError {
  self.get_result(view).unwrap_or_error()
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
        Err(read_cross_store())
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
