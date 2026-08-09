///|
/// Private scheduler identity. It is intentionally not a Query or memo key.
priv enum WakeToken {
  Source(SourceId)
  RevisionClock(StoreId)
  RegionLifetime(RegionGeneration)
} derive(Eq, Hash)

///|
fn[T : Eq] append_unique(items : Array[T], item : T) -> Unit {
  if !items.contains(item) {
    items.push(item)
  }
}

///|
fn union_footprints(
  first : Array[WakeToken],
  second : Array[WakeToken],
) -> Array[WakeToken] {
  let result = first.copy()
  second.each(token => append_unique(result, token))
  result
}

///|
priv struct Evaluation[V] {
  result : Result[V, ReadError]
  successful_footprint : Array[WakeToken]
  attempted_footprint : Array[WakeToken]
}

///|
/// Evaluates one root and preserves attempted tokens on every failure path.
fn[V] evaluate_view(store : StoreCore, view : View[V]) -> Evaluation[V] {
  store.counters.root_read_attempts = store.counters.root_read_attempts + 1
  let session = EvalSession::{
    store,
    revision: store.current_revision(),
    change_epoch: store.current_change_epoch(),
    eval_id: EvalId::{ owner: store.id, sequence: store.allocate_session() },
    active: Ref(true),
    tracking: Ref(None),
    attempted_footprint: [],
    active_stack: [],
    next_active: Ref(1),
  }
  let root_token = WakeToken::RegionLifetime(view.metadata.generation)
  append_unique(session.attempted_footprint, root_token)
  match validate_root_view(store, view) {
    Some(error) => {
      store.counters.root_read_rejections = store.counters.root_read_rejections +
        1
      {
        result: Err(error),
        successful_footprint: [],
        attempted_footprint: session.attempted_footprint.copy(),
      }
    }
    None =>
      match root_read_phase_error(store.id) {
        Some(error) => {
          store.counters.root_read_rejections = store.counters.root_read_rejections +
            1
          {
            result: Err(error),
            successful_footprint: [],
            attempted_footprint: session.attempted_footprint.copy(),
          }
        }
        None => {
          execution_mode.val = ExecutionMode::Evaluating(
            store.id,
            session.eval_id,
          )
          let evaluated = (view.recipe)(make_eval_ctx(session))
          let (result, successful_footprint) = match evaluated {
            Ok(success) =>
              (
                Ok(success.value),
                union_footprints([root_token], success.footprint),
              )
            Err(error) => (Err(error), [])
          }
          store.counters.last_finished_active_depth = session.active_stack.length()
          session.active.val = false
          execution_mode.val = Idle
          {
            result,
            successful_footprint,
            attempted_footprint: session.attempted_footprint.copy(),
          }
        }
      }
  }
}

///|
priv struct MountCore[V] {
  store : StoreCore
  mount_id : MountId
  view : Ref[View[V]?]
  current : Ref[Result[V, ReadError]?]
  successful_footprint : Ref[Array[WakeToken]]
  failed_attempt_footprint : Ref[Array[WakeToken]]
  active_footprint : Ref[Array[WakeToken]]
  disposed : Ref[Bool]
  evaluation_count : Ref[Int]
  wake_count : Ref[Int]
  success_count : Ref[Int]
  failure_count : Ref[Int]
}

///|
/// An active typed observer of one root View recipe.
pub(all) struct Mount[V] {
  priv core : MountCore[V]
}

///|
fn StoreCore::allocate_mount(self : StoreCore) -> MountId {
  let id = MountId::{ owner: self.id, sequence: self.next_mount.val }
  self.next_mount.val = self.next_mount.val + 1
  id
}

///|
fn StoreCore::remove_mount_edges(
  self : StoreCore,
  id : MountId,
  tokens : Array[WakeToken],
) -> Unit {
  tokens.each(token => {
    match self.mount_index.val.get(token) {
      None => ()
      Some(ids) => {
        ids.remove(id)
        if ids.length() == 0 {
          self.mount_index.val.remove(token)
        }
      }
    }
  })
}

///|
fn StoreCore::add_mount_edges(
  self : StoreCore,
  id : MountId,
  tokens : Array[WakeToken],
) -> Unit {
  tokens.each(token => {
    match self.mount_index.val.get(token) {
      Some(ids) => ids[id] = ()
      None => self.mount_index.val[token] = Map([(id, ())])
    }
  })
}

///|
fn StoreCore::wake_selected_mounts(
  self : StoreCore,
  touched : Array[WakeToken],
) -> Unit {
  let touched_map : Map[WakeToken, Unit] = Map([])
  touched.each(token => touched_map[token] = ())
  self.mounts.val.to_array().each(pair => {
    let (id, runner) = pair
    let selected = touched_map
      .to_array()
      .fold(init=false, (found, pair) => {
        if found {
          true
        } else {
          match self.mount_index.val.get(pair.0) {
            Some(ids) => ids.contains(id)
            None => false
          }
        }
      })
    if selected {
      runner()
    }
  })
}

///|
/// Replaces the scheduler edges without retaining any previous failure history.
fn[V] MountCore::replace_footprint(
  self : MountCore[V],
  successful : Array[WakeToken],
  failed : Array[WakeToken],
) -> Unit {
  let active = union_footprints(successful, failed)
  self.store.remove_mount_edges(self.mount_id, self.active_footprint.val)
  self.store.add_mount_edges(self.mount_id, active)
  self.successful_footprint.val = successful.copy()
  self.failed_attempt_footprint.val = failed.copy()
  self.active_footprint.val = active
}

///|
fn[V] MountCore::rerun(self : MountCore[V]) -> Unit {
  if !self.disposed.val {
    match self.view.val {
      None => ()
      Some(view) => {
        self.evaluation_count.val = self.evaluation_count.val + 1
        self.wake_count.val = self.wake_count.val + 1
        let outcome = evaluate_view(self.store, view)
        if !self.disposed.val {
          match outcome.result {
            Ok(value) => {
              self.current.val = Some(Ok(value))
              self.success_count.val = self.success_count.val + 1
              self.replace_footprint(outcome.successful_footprint, [])
            }
            Err(error) => {
              self.current.val = Some(Err(error))
              self.failure_count.val = self.failure_count.val + 1
              self.replace_footprint(
                self.successful_footprint.val,
                outcome.attempted_footprint,
              )
            }
          }
        }
      }
    }
  }
}

///|
/// Validates all mount metadata and phase before allocation or registration.
fn[V] StoreCore::mount_error(self : StoreCore, view : View[V]) -> MountError? {
  if view.metadata.owner != self.id {
    Some(
      MountError::CrossStore(
        view_store=view.metadata.owner,
        mount_store=self.id,
      ),
    )
  } else if !view.metadata.epoch.accepts(view.metadata.generation) {
    Some(MountError::ClosedRegion(generation=view.metadata.generation))
  } else {
    match execution_mode.val {
      Idle => None
      Evaluating(active_store, _) =>
        Some(
          MountError::MountDuringEvaluation(
            active_store~,
            requested_store=self.id,
          ),
        )
      Transacting(active_store, _) =>
        Some(
          MountError::MountDuringTransaction(
            active_store~,
            requested_store=self.id,
          ),
        )
    }
  }
}

///|
/// Creates and evaluates a mount exactly once after atomic validation.
pub fn[V] Store::mount(
  self : Store,
  view : View[V],
) -> Result[Mount[V], MountError] {
  match self.core.mount_error(view) {
    Some(error) => Err(error)
    None => {
      let id = self.core.allocate_mount()
      let core : MountCore[V] = {
        store: self.core,
        mount_id: id,
        view: Ref(Some(view)),
        current: Ref(None),
        successful_footprint: Ref([]),
        failed_attempt_footprint: Ref([]),
        active_footprint: Ref([]),
        disposed: Ref(false),
        evaluation_count: Ref(0),
        wake_count: Ref(0),
        success_count: Ref(0),
        failure_count: Ref(0),
      }
      self.core.mounts.val[id] = () => core.rerun()
      core.rerun()
      Ok(Mount::{ core, })
    }
  }
}

///|
pub fn[V] Mount::id(self : Mount[V]) -> MountId {
  self.core.mount_id
}

///|
/// Returns the latest outcome, or a typed disposed error after disposal.
pub fn[V] Mount::current(
  self : Mount[V],
) -> Result[Result[V, ReadError], MountError] {
  match self.core.current.val {
    Some(value) => Ok(value)
    None => Err(MountError::DisposedMount(self.core.mount_id))
  }
}

///|
/// Removes the runner, index edges, recipe, and typed current value.
pub fn[V] Mount::dispose(self : Mount[V]) -> Unit {
  if !self.core.disposed.val {
    self.core.disposed.val = true
    self.core.store.remove_mount_edges(
      self.core.mount_id,
      self.core.active_footprint.val,
    )
    self.core.store.mounts.val.remove(self.core.mount_id)
    self.core.active_footprint.val.clear()
    self.core.successful_footprint.val.clear()
    self.core.failed_attempt_footprint.val.clear()
    self.core.view.val = None
    self.core.current.val = None
  }
}

///|
pub fn[V] Mount::debug(self : Mount[V]) -> MountDebug {
  {
    mount_id: self.core.mount_id,
    disposed: self.core.disposed.val,
    runner_registered: self.core.store.mounts.val.contains(self.core.mount_id),
    evaluation_count: self.core.evaluation_count.val,
    wake_count: self.core.wake_count.val,
    success_count: self.core.success_count.val,
    failure_count: self.core.failure_count.val,
    successful_footprint_length: self.core.successful_footprint.val.length(),
    failed_attempt_footprint_length: self.core.failed_attempt_footprint.val.length(),
    active_token_count: self.core.active_footprint.val.length(),
  }
}

///|
fn StoreCore::debug_mounts(self : StoreCore) -> (Int, Int) {
  (
    self.mounts.val.length(),
    self.mount_index.val
    .to_array()
    .fold(init=0, (count, pair) => count + pair.1.length()),
  )
}
