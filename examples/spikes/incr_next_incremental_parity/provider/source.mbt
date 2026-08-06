///|
priv struct SourceCore[T] {
  owner : StoreId
  generation : RegionGeneration
  epoch : RegionEpoch
  source_id : SourceId
  committed : Ref[T?]
  changed_at : Ref[ChangeEpoch]
  read_count : Ref[Int]
  verification_count : Ref[Int]
}

///|
pub(all) struct Source[T] {
  priv core : SourceCore[T]
  priv canonical_view : View[T]
}

///|
fn[T] make_source(
  store : StoreCore,
  epoch : RegionEpoch,
  generation : RegionGeneration,
  value : T,
) -> Source[T] {
  let core : SourceCore[T] = {
    owner: store.id,
    generation,
    epoch,
    source_id: SourceId::{
      owner: store.id,
      sequence: store.allocate_definition(),
    },
    committed: Ref(Some(value)),
    changed_at: Ref(store.current_change_epoch()),
    read_count: Ref(0),
    verification_count: Ref(0),
  }
  let view = make_view(
    store,
    epoch,
    generation,
    ViewOrigin::Source(core.source_id),
    ctx => match ctx.eval_source(core) {
      Ok(value) => Ok({
        value,
        dependency: {
          verify: (_ctx, verified_at) => core.verify_dependency(verified_at),
        },
      })
      Err(error) => Err(error)
    },
  )
  { core, canonical_view: view }
}

///|
fn[T] EvalCtx::eval_source(
  self : EvalCtx,
  core : SourceCore[T],
) -> Result[T, ReadError] {
  match self.validate_definition(core.owner, core.epoch, core.generation) {
    Some(error) => Err(error)
    None =>
      match core.committed.val {
        None => Err(ReadError::ClosedRegion(generation=core.generation))
        Some(value) => {
          core.read_count.val = core.read_count.val + 1
          Ok(value)
        }
      }
  }
}

///|
fn[T] SourceCore::verify_dependency(
  self : SourceCore[T],
  verified_at : ChangeEpoch,
) -> Verification {
  self.verification_count.val = self.verification_count.val + 1
  match self.committed.val {
    None => RecomputeRequired
    Some(_) =>
      if self.changed_at.val.value > verified_at.value {
        RecomputeRequired
      } else {
        ProvenUnchanged(self.changed_at.val)
      }
  }
}

///|
fn[T] SourceCore::commit(
  self : SourceCore[T],
  value : T,
  target_epoch : ChangeEpoch,
) -> Unit {
  self.committed.val = Some(value)
  self.changed_at.val = target_epoch
}

///|
fn[T] SourceCore::close(self : SourceCore[T]) -> Unit {
  self.committed.val = None
}

///|
pub fn[T] Source::view(self : Source[T]) -> View[T] {
  self.canonical_view
}

///|
pub fn[T] Source::id(self : Source[T]) -> SourceId {
  self.core.source_id
}

///|
pub fn[T] Source::debug(self : Source[T]) -> SourceDebug {
  {
    source_id: self.core.source_id,
    generation: self.core.generation,
    committed: self.core.committed.val is Some(_),
    read_count: self.core.read_count.val,
    verification_count: self.core.verification_count.val,
    changed_at: self.core.changed_at.val,
  }
}
