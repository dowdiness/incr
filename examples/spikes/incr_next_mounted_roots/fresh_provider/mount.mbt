///|
/// Private active-root scheduler. Fresh deliberately has no token index.
priv struct MountCore[V] {
  store : StoreCore
  mount_id : MountId
  view : Ref[View[V]?]
  current : Ref[Result[V, ReadError]?]
  successful_footprint : Ref[Array[WakeToken]]
  failed_attempt_footprint : Ref[Array[WakeToken]]
  disposed : Ref[Bool]
  evaluation_count : Ref[Int]
  wake_count : Ref[Int]
  success_count : Ref[Int]
  failure_count : Ref[Int]
}

///|
fn StoreCore::allocate_mount(self : StoreCore) -> MountId {
  let id = MountId::{ owner: self.id, sequence: self.next_mount.val }
  self.next_mount.val = self.next_mount.val + 1
  id
}

///|
/// Fresh re-runs every active mount; no selective token index exists.
fn StoreCore::wake_all_mounts(self : StoreCore) -> Unit {
  self.mounts.val.to_array().each(pair => (pair.1)())
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
/// Reruns one Fresh root and records both successful and failed footprints.
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
              self.successful_footprint.val = outcome.successful_footprint
              self.failed_attempt_footprint.val.clear()
            }
            Err(error) => {
              self.current.val = Some(Err(error))
              self.failure_count.val = self.failure_count.val + 1
              self.failed_attempt_footprint.val = outcome.attempted_footprint
            }
          }
        }
      }
    }
  }
}

///|
/// An active typed observer of one root View recipe.
pub(all) struct Mount[V] {
  priv core : MountCore[V]
}

///|
/// Creates and evaluates a Fresh mount after atomic validation.
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
/// Returns this mount's stable identity.
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
/// Removes the runner and releases the recipe/current value; idempotent.
pub fn[V] Mount::dispose(self : Mount[V]) -> Unit {
  if !self.core.disposed.val {
    self.core.disposed.val = true
    self.core.store.mounts.val.remove(self.core.mount_id)
    self.core.successful_footprint.val.clear()
    self.core.failed_attempt_footprint.val.clear()
    self.core.view.val = None
    self.core.current.val = None
  }
}

///|
/// Returns immutable evidence for one Fresh mount.
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
    active_token_count: union_footprints(
      self.core.successful_footprint.val,
      self.core.failed_attempt_footprint.val,
    ).length(),
  }
}

///|
/// Fresh exposes runner count but intentionally no token-index edges.
fn StoreCore::debug_mounts(self : StoreCore) -> (Int, Int) {
  (self.mounts.val.length(), 0)
}
