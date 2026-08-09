///|
/// Committed Source state. It owns no View or RegionCore edge.
priv struct SourceCore[T] {
  owner : StoreId
  generation : RegionGeneration
  epoch : RegionEpoch
  source_id : SourceId
  committed : Ref[T?]
  read_count : Ref[Int]
}

///|
/// Source definition plus its single stable read View.
pub(all) struct Source[T] {
  priv core : SourceCore[T]
  priv canonical_view : View[T]
}

///|
/// Creates one Source and one stable recipe View.
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
    source_id: SourceId::{ owner: store.id, sequence: store.allocate() },
    committed: Ref(Some(value)),
    read_count: Ref(0),
  }
  let view = make_view(
    store,
    epoch,
    generation,
    ViewOrigin::Source(core.source_id),
    ctx => ctx.eval_source(core),
  )
  { core, canonical_view: view }
}

///|
/// Reads one committed Source value through EvalCtx.
fn[T] EvalCtx::eval_source(
  self : EvalCtx,
  core : SourceCore[T],
) -> Result[T, ReadError] {
  self.record_token(WakeToken::RegionLifetime(core.generation))
  match self.validate_definition(core.owner, core.epoch, core.generation) {
    Some(error) => Err(error)
    None =>
      match core.committed.val {
        None => Err(ReadError::ClosedRegion(generation=core.generation))
        Some(value) => {
          core.read_count.val = core.read_count.val + 1
          self.record_token(WakeToken::Source(core.source_id))
          Ok(value)
        }
      }
  }
}

///|
/// Applies one already-validated committed value.
fn[T] SourceCore::commit(self : SourceCore[T], value : T) -> Unit {
  self.committed.val = Some(value)
}

///|
/// Releases the committed payload during Region close.
fn[T] SourceCore::close(self : SourceCore[T]) -> Unit {
  self.committed.val = None
}

///|
/// Returns the one canonical View allocated with this Source.
pub fn[T] Source::view(self : Source[T]) -> View[T] {
  self.canonical_view
}

///|
/// Returns this Source's stable identity.
pub fn[T] Source::id(self : Source[T]) -> SourceId {
  self.core.source_id
}

///|
/// Returns an immutable Source state snapshot.
pub fn[T] Source::debug(self : Source[T]) -> SourceDebug {
  {
    source_id: self.core.source_id,
    generation: self.core.generation,
    committed: self.core.committed.val is Some(_),
    read_count: self.core.read_count.val,
  }
}
