///|
/// Committed Source state. Its payload is released by Region.close.
priv struct SourceCore[T] {
  owner : StoreId
  source_id : SourceId
  generation : RegionGeneration
  epoch : RegionEpoch
  value : Ref[T?]
}

///|
/// A typed Source with one canonical View and no direct setter.
pub struct Source[T] {
  priv core : SourceCore[T]
  priv canonical_view : View[T]
}

///|
fn[T] make_source(
  owner : StoreId,
  source_id : SourceId,
  epoch : RegionEpoch,
  generation : RegionGeneration,
  value : T,
) -> Source[T] {
  let core : SourceCore[T] = {
    owner,
    source_id,
    generation,
    epoch,
    value: Ref(Some(value)),
  }
  let view : View[T] = {
    owner,
    generation,
    recipe: ctx => ctx.eval_source(core),
  }
  { core, canonical_view: view }
}

///|
fn[T] QueryContext::eval_source(
  self : QueryContext,
  core : SourceCore[T],
) -> Result[T, ReadError] {
  match self.expired() {
    Some(error) => Err(error)
    None =>
      if core.owner != self.session.owner {
        Err(
          ReadError::CrossStore(
            view_store=core.owner,
            reader_store=self.session.owner,
          ),
        )
      } else if !core.epoch.accepts(core.generation) {
        Err(ReadError::ClosedRegion(generation=core.generation))
      } else {
        match core.value.val {
          Some(value) => Ok(value)
          None => Err(ReadError::ClosedRegion(generation=core.generation))
        }
      }
  }
}

///|
/// Creates a Source in this Region.
pub fn[T] Region::source(
  self : Region,
  initial : T,
) -> Result[Source[T], RegionError] {
  match self.check_open() {
    Some(error) => Err(error)
    None => {
      let sequence = self.next_sequence.val
      self.next_sequence.val = sequence + 1
      let source = make_source(
        self.owner,
        { owner: self.owner, sequence },
        self.epoch,
        self.epoch.snapshot(),
        initial,
      )
      self.close_actions.push(() => source.core.value.val = None)
      Ok(source)
    }
  }
}

///|
/// Returns this Source's stable canonical View.
pub fn[T] Source::view(self : Source[T]) -> View[T] {
  self.canonical_view
}
