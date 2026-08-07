///|
pub(all) enum ViewOrigin {
  Source(SourceId)
  Query(QueryId)
} derive(Eq, Debug)

///|
priv struct ViewMetadata {
  owner : StoreId
  generation : RegionGeneration
  epoch : RegionEpoch
  handle_id : ViewHandleId
  origin : ViewOrigin
}

///|
/// The only successful recipe result is private so callers cannot invoke or
/// manufacture a recipe, and dependency recording remains a kernel operation.
priv struct RecipeSuccess[V] {
  value : V
  dependency : Dependency
}

///|
/// A memo-local erased dependency verifier. It captures the active session and
/// can verify an upstream Query directly without recording into its parent.
priv struct Dependency {
  verify : (EvalCtx, ChangeEpoch) -> Verification
}

///|
/// Opaque recipe-backed View. There is deliberately no public get/read/call API.
pub(all) struct View[V] {
  priv metadata : ViewMetadata
  priv recipe : (EvalCtx) -> Result[RecipeSuccess[V], ReadError]
}

///|
priv struct RevisionClock {
  store : StoreCore
}

///|
fn RevisionClock::dependency(self : RevisionClock) -> Dependency {
  {
    verify: (_ctx, epoch) => {
      let changed_at = self.store.revision_changed_at.val
      if changed_at.value > epoch.value {
        RecomputeRequired
      } else {
        ProvenUnchanged(changed_at)
      }
    },
  }
}

///|
priv struct TrackingFrame {
  deps : Array[Dependency]
}

///| Session-local operational identity for one active invocation.
priv struct ActiveInvocationId {
  sequence : Int
} derive(Eq)

///| Key-free frame used only to construct a copied QueryId witness.
priv struct ActiveFrame {
  active_id : ActiveInvocationId
  query_id : QueryId
}

///| Typed QueryCore map payload; the key remains in that QueryCore's Map.
priv struct ActiveInvocation {
  eval_id : EvalId
  active_id : ActiveInvocationId
  stack_index : Int
}

///|
priv struct EvalSession {
  store : StoreCore
  revision : Revision
  change_epoch : ChangeEpoch
  eval_id : EvalId
  active : Ref[Bool]
  tracking : Ref[TrackingFrame?]
  active_stack : Array[ActiveFrame]
  next_active : Ref[Int]
}

///|
/// Kernel-created capability valid for one root evaluation only.
pub(all) struct EvalCtx {
  priv session : EvalSession
}

///|
fn[V] make_view(
  store : StoreCore,
  epoch : RegionEpoch,
  generation : RegionGeneration,
  origin : ViewOrigin,
  recipe : (EvalCtx) -> Result[RecipeSuccess[V], ReadError],
) -> View[V] {
  {
    metadata: {
      owner: store.id,
      generation,
      epoch,
      handle_id: ViewHandleId::{
        owner: store.id,
        sequence: store.allocate_view(),
      },
      origin,
    },
    recipe,
  }
}

///|
fn make_eval_ctx(session : EvalSession) -> EvalCtx {
  { session, }
}

///| Enters one key-sensitive slow-path invocation after active lookup succeeds.
fn EvalCtx::enter_active(
  self : EvalCtx,
  query_id : QueryId,
) -> ActiveInvocation {
  let active_id = ActiveInvocationId::{ sequence: self.session.next_active.val }
  self.session.next_active.val = self.session.next_active.val + 1
  let result = ActiveInvocation::{
    eval_id: self.session.eval_id,
    active_id,
    stack_index: self.session.active_stack.length(),
  }
  self.session.active_stack.push(ActiveFrame::{ active_id, query_id })
  result
}

///| Copies the cycle segment and appends its closing QueryId.
fn EvalCtx::cycle_witness(
  self : EvalCtx,
  active : ActiveInvocation,
  closing : QueryId,
) -> CycleWitness {
  let path = match self.session.active_stack.get_view(start=active.stack_index) {
    Some(view) => view.map(frame => frame.query_id)
    None => []
  }
  path.push(closing)
  CycleWitness::{ path, }
}

///| Pops exactly the frame entered by this invocation.
fn EvalCtx::leave_active(
  self : EvalCtx,
  active : ActiveInvocation,
) -> Unit {
  match self.session.active_stack.pop() {
    Some(frame) =>
      if frame.active_id != active.active_id {
        abort("active invocation stack mismatch")
      }
    None => abort("active invocation stack underflow")
  }
}

///|
fn[V] validate_root_view(store : StoreCore, view : View[V]) -> ReadError? {
  if view.metadata.owner != store.id {
    Some(ReadError::CrossStore(
      view_store=view.metadata.owner,
      reader_store=store.id,
    ))
  } else if !view.metadata.epoch.accepts(view.metadata.generation) {
    Some(ReadError::ClosedRegion(generation=view.metadata.generation))
  } else {
    None
  }
}

///|
fn[V] EvalCtx::validate(self : EvalCtx, view : View[V]) -> ReadError? {
  if !self.session.active.val {
    Some(ReadError::ExpiredEvalContext(eval_id=self.session.eval_id))
  } else if view.metadata.owner != self.session.store.id {
    Some(ReadError::CrossStore(
      view_store=view.metadata.owner,
      reader_store=self.session.store.id,
    ))
  } else if !view.metadata.epoch.accepts(view.metadata.generation) {
    Some(ReadError::ClosedRegion(generation=view.metadata.generation))
  } else {
    None
  }
}

///|
fn EvalCtx::validate_definition(
  self : EvalCtx,
  owner : StoreId,
  epoch : RegionEpoch,
  generation : RegionGeneration,
) -> ReadError? {
  if !self.session.active.val {
    Some(ReadError::ExpiredEvalContext(eval_id=self.session.eval_id))
  } else if owner != self.session.store.id {
    Some(ReadError::CrossStore(
      view_store=owner,
      reader_store=self.session.store.id,
    ))
  } else if !epoch.accepts(generation) {
    Some(ReadError::ClosedRegion(generation~))
  } else {
    None
  }
}

///|
fn EvalCtx::current_change_epoch(self : EvalCtx) -> ChangeEpoch {
  self.session.change_epoch
}

///|
fn EvalCtx::record(self : EvalCtx, dependency : Dependency) -> Unit {
  match self.session.tracking.val {
    Some(frame) => frame.deps.push(dependency)
    None => ()
  }
}

///|
/// Reads a nested View and records its dependency only after the recipe returns
/// a successful value. Root Store::read bypasses this method and records none.
pub fn[V] EvalCtx::read(self : EvalCtx, view : View[V]) -> Result[V, ReadError] {
  match self.validate(view) {
    Some(error) => Err(error)
    None =>
      match (view.recipe)(self) {
        Ok(success) => {
          self.record(success.dependency)
          Ok(success.value)
        }
        Err(error) => Err(error)
      }
  }
}

///|
/// Returns the Revision captured for this root. A query that calls this method
/// also depends on the Store's RevisionClock, so unrelated Region close remains
/// green while a committed write invalidates it.
pub fn EvalCtx::revision(self : EvalCtx) -> Revision {
  match self.session.tracking.val {
    Some(_) => self.record(RevisionClock::{
      store: self.session.store,
    }.dependency())
    None => ()
  }
  self.session.revision
}

///|
pub fn[V] View::handle_id(self : View[V]) -> ViewHandleId {
  self.metadata.handle_id
}

///|
pub fn[V] View::origin(self : View[V]) -> ViewOrigin {
  self.metadata.origin
}

///|
pub fn[V] View::generation(self : View[V]) -> RegionGeneration {
  self.metadata.generation
}
