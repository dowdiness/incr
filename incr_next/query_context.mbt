///|
/// The private state captured by one root evaluation.
priv struct EvalSession {
  owner : StoreId
  revision : Revision
  change_epoch : ChangeEpoch
  active : Ref[Bool]
}

///|
/// A tracked read capability valid only during one Query invocation.
pub struct QueryContext {
  priv session : EvalSession
  priv invocation : Ref[Bool]
}

///|
fn QueryContext::root(session : EvalSession) -> QueryContext {
  { session, invocation: Ref(true) }
}

///|
fn QueryContext::child(self : QueryContext) -> QueryContext {
  { session: self.session, invocation: Ref(true) }
}

///|
fn QueryContext::expire(self : QueryContext) -> Unit {
  self.invocation.val = false
}

///|
fn QueryContext::expired(self : QueryContext) -> ReadError? {
  if !self.session.active.val || !self.invocation.val {
    Some(ReadError::ExpiredQueryContext)
  } else {
    None
  }
}

///|
/// Reads a nested Source or Query View and propagates structural errors.
pub fn[V] QueryContext::read(
  self : QueryContext,
  view : View[V],
) -> Result[V, ReadError] {
  match self.expired() {
    Some(error) => Err(error)
    None =>
      if view.owner != self.session.owner {
        Err(
          ReadError::CrossStore(
            view_store=view.owner,
            reader_store=self.session.owner,
          ),
        )
      } else {
        (view.recipe)(self)
      }
  }
}

///|
/// Returns the committed Revision captured by the root read.
///
/// An expired invocation context returns `ExpiredQueryContext`.
pub fn QueryContext::revision(
  self : QueryContext,
) -> Result[Revision, ReadError] {
  match self.expired() {
    Some(error) => Err(error)
    None => Ok(self.session.revision)
  }
}
