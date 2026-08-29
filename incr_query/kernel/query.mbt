///|
/// The epoch at which a Store mutation or Region close occurred.
type ChangeEpoch = Int

///|
/// Identity is local to one QueryCore; it is never shared through a registry.
priv struct MemoId {
  value : Int
} derive(Eq, Debug)

///|
/// A last-successful value for one typed Query key.
priv struct MemoEntry[V] {
  value : V
  memo_id : MemoId
  verified_at : ChangeEpoch
  changed_at : ChangeEpoch
  trace : TrackingFrame
}

///|
priv enum CutoffMode[V] {
  AlwaysChanged
  Compare((V, V) -> Bool)
}

///|
/// An opaque optional propagation-equivalence policy.
pub struct Cutoff[V] {
  priv mode : CutoffMode[V]
}

///|
fn[V] Cutoff::always_changed() -> Cutoff[V] {
  { mode: AlwaysChanged }
}

///|
/// Uses structural equality as propagation equivalence.
pub fn[V : Eq] Cutoff::equal() -> Cutoff[V] {
  { mode: Compare((old, next) => old == next) }
}

///|
fn[V] Cutoff::equivalent(self : Cutoff[V], old : V, next : V) -> Bool {
  match self.mode {
    AlwaysChanged => false
    Compare(equal) => equal(old, next)
  }
}

///|
/// Query-local typed memo storage with last-successful forward traces.
priv struct QueryCore[K, V] {
  owner : StoreId
  id : QueryId
  definition_site : String
  generation : RegionGeneration
  epoch : RegionEpoch
  compute : Ref[((QueryContext, K) -> Result[V, ReadError])?]
  cutoff : Ref[Cutoff[V]]
  active : Map[K, Int]
  memo : Map[K, MemoEntry[V]]
  next_memo_id : Ref[Int]
  compute_count : Ref[Int]
  cache_hit_count : Ref[Int]
  verification_count : Ref[Int]
  green_count : Ref[Int]
  red_count : Ref[Int]
  cutoff_count : Ref[Int]
  dependency_check_count : Ref[Int]
  unavailable_count : Ref[Int]
}

///|
/// A typed keyed Query recipe.
pub struct Query[K, V] {
  priv core : QueryCore[K, V]
  priv make_view : (K) -> View[V]
}

///|
fn[K, V] QueryCore::verify(
  self : QueryCore[K, V],
  _key : K,
  entry : MemoEntry[V],
  context : QueryContext,
) -> Bool {
  let prior = entry.verified_at
  entry.trace.fold(init=true, (green, dependency) => {
    self.dependency_check_count.val = self.dependency_check_count.val + 1
    match (dependency.verifier)(context) {
      Available(changed_at~) if changed_at <= prior => green
      Available(_) => false
      RecomputeRequired => {
        self.unavailable_count.val = self.unavailable_count.val + 1
        false
      }
    }
  })
}

///|
fn[K : Hash + Eq, V] QueryContext::compute_query(
  self : QueryContext,
  core : QueryCore[K, V],
  key : K,
  epoch : ChangeEpoch,
) -> Result[V, ReadError] {
  match core.compute.val {
    None => Err(read_closed_region())
    Some(compute) => {
      core.compute_count.val = core.compute_count.val + 1
      let invocation = self.child()
      let callback_result = compute(invocation, key)
      let result = match invocation.first_failure.val {
        Some(error) => Err(error)
        None => callback_result
      }
      match result {
        Ok(value) => {
          let trace = invocation.take_frame()
          invocation.expire()
          let previous = core.memo.get(key)
          let memo_id = match previous {
            Some(entry) => entry.memo_id
            None => {
              let next_id = core.next_memo_id.val
              core.next_memo_id.val = next_id + 1
              MemoId::{ value: next_id }
            }
          }
          let changed_at = match previous {
            Some(entry) => {
              core.cutoff_count.val = core.cutoff_count.val + 1
              if core.cutoff.val.equivalent(entry.value, value) {
                entry.changed_at
              } else {
                epoch
              }
            }
            None => epoch
          }
          core.memo.set(key, {
            value,
            memo_id,
            verified_at: epoch,
            changed_at,
            trace,
          })
          Ok(value)
        }
        Err(error) => {
          invocation.expire()
          Err(error)
        }
      }
    }
  }
}

///|
fn[K : Hash + Eq, V] QueryContext::eval_query_slow(
  self : QueryContext,
  core : QueryCore[K, V],
  key : K,
  epoch : ChangeEpoch,
) -> Result[V, ReadError] {
  match self.session.max_active_queries {
    Some(limit) if self.session.active_stack.length().reinterpret_as_uint() >=
      limit => Err(read_evaluation_limit_exceeded(limit))
    _ => {
      let start = self.session.active_stack.length()
      core.active.set(key, start)
      self.session.active_stack.push({
        id: core.id,
        definition_site: core.definition_site,
      })
      let result = match core.memo.get(key) {
        Some(entry) => {
          core.verification_count.val = core.verification_count.val + 1
          if core.verify(key, entry, self) {
            core.green_count.val = core.green_count.val + 1
            core.memo.set(key, {
              value: entry.value,
              memo_id: entry.memo_id,
              verified_at: epoch,
              changed_at: entry.changed_at,
              trace: entry.trace,
            })
            Ok(entry.value)
          } else {
            core.red_count.val = core.red_count.val + 1
            self.compute_query(core, key, epoch)
          }
        }
        None => self.compute_query(core, key, epoch)
      }
      ignore(self.session.active_stack.pop())
      core.active.remove(key)
      result
    }
  }
}

///|
fn cycle_definition_path(
  stack : Array[ActiveQuery],
  start : Int,
  current_site : String,
) -> String {
  let sites = stack[start:].map(active => active.definition_site)
  sites.push(current_site)
  sites.join("\n→ ")
}

///|
fn[K : Hash + Eq, V] QueryContext::eval_query(
  self : QueryContext,
  core : QueryCore[K, V],
  key : K,
) -> Result[V, ReadError] {
  match self.expired() {
    Some(error) => Err(error)
    None =>
      if core.owner != self.session.owner {
        Err(read_query_context_cross_store())
      } else if !core.epoch.accepts(core.generation) {
        Err(read_closed_region())
      } else {
        match core.active.get(key) {
          Some(start) =>
            Err(
              read_cycle(
                cycle_definition_path(
                  self.session.active_stack,
                  start,
                  core.definition_site,
                ),
              ),
            )
          None => {
            let epoch = self.session.change_epoch
            match core.memo.get(key) {
              Some(entry) if entry.verified_at == epoch => {
                core.cache_hit_count.val = core.cache_hit_count.val + 1
                Ok(entry.value)
              }
              _ => self.eval_query_slow(core, key, epoch)
            }
          }
        }
      }
  }
}

///|
fn[K : Hash + Eq, V] Region::query_with_cutoff(
  self : Region,
  compute : (QueryContext, K) -> Result[V, ReadError],
  cutoff : Cutoff[V],
  definition_site : String,
) -> Result[Query[K, V], RegionError] {
  match self.check_open() {
    Some(error) => Err(error)
    None => {
      let sequence = self.next_sequence.val
      self.next_sequence.val = sequence + 1
      let id : QueryId = { value: sequence }
      let core : QueryCore[K, V] = {
        owner: self.owner,
        id,
        definition_site,
        generation: self.epoch.snapshot(),
        epoch: self.epoch,
        compute: Ref(Some(compute)),
        cutoff: Ref(cutoff),
        active: Map([]),
        memo: Map([]),
        next_memo_id: Ref(0),
        compute_count: Ref(0),
        cache_hit_count: Ref(0),
        verification_count: Ref(0),
        green_count: Ref(0),
        red_count: Ref(0),
        cutoff_count: Ref(0),
        dependency_check_count: Ref(0),
        unavailable_count: Ref(0),
      }
      let query : Query[K, V] = {
        core,
        make_view: key => {
          owner: core.owner,
          generation: core.generation,
          dependency_kind: Query,
          verifier: query_dependency(core, key).verifier,
          recipe: ctx => ctx.eval_query(core, key),
        },
      }
      self.close_actions.push(() => {
        query.core.active.clear()
        query.core.memo.clear()
        query.core.compute.val = None
        query.core.cutoff.val = Cutoff::always_changed()
      })
      Ok(query)
    }
  }
}

///|
/// Creates one tracked Derived Value with conservative propagation by default.
#callsite(autofill(loc))
pub fn[V] Region::derived(
  self : Region,
  compute : (QueryContext) -> V raise ReadError,
  cutoff? : Cutoff[V] = Cutoff::always_changed(),
  loc~ : SourceLoc,
) -> View[V] raise RegionError {
  let query = self
    .query_with_cutoff(
      (context, _unit : Unit) => {
        Ok(compute(context)) catch {
          error => Err(error)
        }
      },
      cutoff,
      loc.to_string(),
    )
    .unwrap_or_error()
  query.view(())
}

///|
/// Creates a key-indexed family of tracked Derived Values.
#callsite(autofill(loc))
pub fn[K : Hash + Eq, V] Region::query(
  self : Region,
  compute : (QueryContext, K) -> V raise ReadError,
  cutoff? : Cutoff[V] = Cutoff::always_changed(),
  loc~ : SourceLoc,
) -> Query[K, V] raise RegionError {
  self
  .query_with_cutoff(
    (context, key) => Ok(compute(context, key)) catch { error => Err(error) },
    cutoff,
    loc.to_string(),
  )
  .unwrap_or_error()
}

///|
/// Captures a typed key in one opaque, non-callable View.
pub fn[K, V] Query::view(self : Query[K, V], key : K) -> View[V] {
  (self.make_view)(key)
}

///|
/// Removes one key's last-successful memo evidence without changing clocks.
fn[K : Hash + Eq, V] Query::drop_memo_evidence(
  self : Query[K, V],
  key : K,
) -> Result[Unit, RegionError] {
  match phase_region_error() {
    Some(error) => Err(error)
    None =>
      if !self.core.epoch.accepts(self.core.generation) {
        Err(region_closed())
      } else {
        ignore(self.core.memo.remove(key))
        Ok(())
      }
  }
}
