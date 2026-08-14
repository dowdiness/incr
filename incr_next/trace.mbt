///|
/// The kind of one forward dependency in a successful Query invocation.
priv enum DependencyKind {
  Source
  Query
  Revision
} derive(Eq, Debug)

///|
/// The result of asking one dependency whether its last value is available.
priv enum Verification {
  Available(changed_at~ : ChangeEpoch)
  RecomputeRequired
} derive(Eq, Debug)

///|
/// A typed-erased verifier retained by a last-successful memo trace.
priv struct Dependency {
  kind : DependencyKind
  verifier : (QueryContext) -> Verification
}

///|
/// A temporary or installed forward trace.
type TrackingFrame = Array[Dependency]

///|
fn dependency(
  kind : DependencyKind,
  verifier : (QueryContext) -> Verification,
) -> Dependency {
  { kind, verifier }
}

///|
fn[T] source_dependency(core : SourceCore[T]) -> Dependency {
  dependency(Source, _ctx => {
    if core.epoch.accepts(core.generation) && core.value.val is Some(_) {
      Available(changed_at=core.changed_at.val)
    } else {
      RecomputeRequired
    }
  })
}

///|
fn[K : Hash + Eq, V] query_dependency(
  core : QueryCore[K, V],
  key : K,
) -> Dependency {
  dependency(Query, ctx => {
    match ctx.eval_query(core, key) {
      Ok(_) =>
        match core.memo.get(key) {
          Some(entry) => Available(changed_at=entry.changed_at)
          None => RecomputeRequired
        }
      Err(_) => RecomputeRequired
    }
  })
}

///|
fn revision_dependency(changed_at : Ref[ChangeEpoch]) -> Dependency {
  dependency(Revision, _ctx => Available(changed_at=changed_at.val))
}
