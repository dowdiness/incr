///|
/// Definition identity represented by one View recipe.
pub(all) enum ViewOrigin {
  Source(SourceId)
  Query(QueryId)
} derive(Eq, Debug)

///|
/// Private metadata checked before every recipe invocation.
priv struct ViewMetadata {
  owner : StoreId
  generation : RegionGeneration
  epoch : RegionEpoch
  handle_id : ViewHandleId
  origin : ViewOrigin
}

///|
/// Opaque recipe. It has no public get/read/call surface.
pub(all) struct View[V] {
  priv metadata : ViewMetadata
  priv recipe : (EvalCtx) -> Result[V, ReadError]
}

///|
/// One root evaluation session.
priv struct EvalSession {
  store : StoreCore
  revision : Revision
  eval_id : EvalId
  active : Ref[Bool]
}

///|
/// Kernel-created capability valid for one root evaluation only.
pub(all) struct EvalCtx {
  priv session : EvalSession
}

///|
/// Creates one View inside the provider package.
fn[V] make_view(
  store : StoreCore,
  epoch : RegionEpoch,
  generation : RegionGeneration,
  origin : ViewOrigin,
  recipe : (EvalCtx) -> Result[V, ReadError],
) -> View[V] {
  {
    metadata: {
      owner: store.id,
      generation,
      epoch,
      handle_id: ViewHandleId::{ owner: store.id, sequence: store.allocate() },
      origin,
    },
    recipe,
  }
}

///|
/// Creates a private evaluation capability.
fn make_eval_ctx(session : EvalSession) -> EvalCtx {
  { session, }
}

///|
/// Validates a View against a Store before a root recipe runs.
fn[V] validate_root_view(store : StoreCore, view : View[V]) -> ReadError? {
  if view.metadata.owner != store.id {
    Some(
      ReadError::CrossStore(
        view_store=view.metadata.owner,
        reader_store=store.id,
      ),
    )
  } else if !view.metadata.epoch.accepts(view.metadata.generation) {
    Some(ReadError::ClosedRegion(generation=view.metadata.generation))
  } else {
    None
  }
}

///|
/// Validates a nested View against one active EvalCtx.
fn[V] EvalCtx::validate(self : EvalCtx, view : View[V]) -> ReadError? {
  if !self.session.active.val {
    Some(ReadError::ExpiredEvalContext(eval_id=self.session.eval_id))
  } else if view.metadata.owner != self.session.store.id {
    Some(
      ReadError::CrossStore(
        view_store=view.metadata.owner,
        reader_store=self.session.store.id,
      ),
    )
  } else if !view.metadata.epoch.accepts(view.metadata.generation) {
    Some(ReadError::ClosedRegion(generation=view.metadata.generation))
  } else {
    None
  }
}

///|
/// Validates one Source or Query definition against the active session.
fn EvalCtx::validate_definition(
  self : EvalCtx,
  owner : StoreId,
  epoch : RegionEpoch,
  generation : RegionGeneration,
) -> ReadError? {
  if !self.session.active.val {
    Some(ReadError::ExpiredEvalContext(eval_id=self.session.eval_id))
  } else if owner != self.session.store.id {
    Some(
      ReadError::CrossStore(
        view_store=owner,
        reader_store=self.session.store.id,
      ),
    )
  } else if !epoch.accepts(generation) {
    Some(ReadError::ClosedRegion(generation~))
  } else {
    None
  }
}

///|
/// Reads one nested View through the active evaluation capability.
pub fn[V] EvalCtx::read(self : EvalCtx, view : View[V]) -> Result[V, ReadError] {
  match self.validate(view) {
    Some(error) => Err(error)
    None => (view.recipe)(self)
  }
}

///|
/// Returns the immutable revision captured for this root evaluation.
pub fn EvalCtx::revision(self : EvalCtx) -> Revision {
  self.session.revision
}

///|
/// Returns the session identity for evidence output.
pub fn EvalCtx::eval_id(self : EvalCtx) -> EvalId {
  self.session.eval_id
}

///|
/// Returns the stable View handle identity.
pub fn[V] View::handle_id(self : View[V]) -> ViewHandleId {
  self.metadata.handle_id
}

///|
/// Returns the Source or Query definition represented by this View.
pub fn[V] View::origin(self : View[V]) -> ViewOrigin {
  self.metadata.origin
}

///|
/// Returns the Region generation captured by this View.
pub fn[V] View::generation(self : View[V]) -> RegionGeneration {
  self.metadata.generation
}
