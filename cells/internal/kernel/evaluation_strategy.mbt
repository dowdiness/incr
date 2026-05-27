///|
/// Sealed runtime-owned evaluation strategy bundle.
///
/// Phase 3 installs only the default bundle: each arm delegates to the
/// existing kernel state machine. The event sink is forwarded as data; it
/// does not influence scheduling decisions.
pub struct EvaluationStrategies {
  priv pull_rebuilder : PullRebuilderStrategy
  priv push_scheduler : PushSchedulerStrategy
}

///|
priv enum PullRebuilderStrategy {
  DefaultPullRebuilder
}

///|
priv enum PushSchedulerStrategy {
  DefaultPushScheduler
}

///|
/// Returns the default strategy bundle that preserves current behavior.
pub fn EvaluationStrategies::default() -> EvaluationStrategies {
  { pull_rebuilder: DefaultPullRebuilder, push_scheduler: DefaultPushScheduler }
}

///|
/// Runs the default pull verification strategy.
pub fn EvaluationStrategies::pull_verify(
  self : EvaluationStrategies,
  core : RuntimeCore,
  pull : PullState,
  slot_snapshots : Array[&@shared.SlotSnapshot],
  cell_id : CellId,
) -> Result[Unit, @incr_types.CycleError] raise Failure {
  self.pull_rebuilder.pull_verify(core, pull, slot_snapshots, cell_id)
}

///|
/// Publishes ordinary source changes through the default push scheduler.
pub fn EvaluationStrategies::propagate_changes(
  self : EvaluationStrategies,
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_ids : Array[CellId],
  durability : Durability,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  self.push_scheduler.propagate_changes(
    core, pull, push, datalog, changed_ids, durability, event_sink,
  )
}

///|
/// Publishes kernel-originated cell changes through the default push scheduler.
pub fn EvaluationStrategies::publish_cell_changes(
  self : EvaluationStrategies,
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_ids : Array[CellId],
  durability : Durability,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  self.push_scheduler.publish_cell_changes(
    core, pull, push, datalog, changed_ids, durability, event_sink,
  )
}

///|
/// Runs default level-ordered push propagation from changed source cells.
pub fn EvaluationStrategies::push_propagate_from(
  self : EvaluationStrategies,
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_sources : Array[CellId],
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  self.push_scheduler.push_propagate_from(
    core, pull, push, datalog, changed_sources, event_sink,
  )
}

///|
/// Commits the current batch with the default batch scheduler.
pub fn EvaluationStrategies::commit_batch(
  self : EvaluationStrategies,
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  self.push_scheduler.commit_batch(core, pull, push, datalog, event_sink)
}

///|
/// Runs the default fixpoint evaluator.
pub fn EvaluationStrategies::run_fixpoint(
  self : EvaluationStrategies,
  core : RuntimeCore,
  datalog : DatalogState,
) -> Array[CellId] {
  self.push_scheduler.run_fixpoint(core, datalog)
}

///|
fn PullRebuilderStrategy::pull_verify(
  self : PullRebuilderStrategy,
  core : RuntimeCore,
  pull : PullState,
  slot_snapshots : Array[&@shared.SlotSnapshot],
  cell_id : CellId,
) -> Result[Unit, @incr_types.CycleError] raise Failure {
  match self {
    DefaultPullRebuilder => pull_verify(core, pull, slot_snapshots, cell_id)
  }
}

///|
fn PushSchedulerStrategy::propagate_changes(
  self : PushSchedulerStrategy,
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_ids : Array[CellId],
  durability : Durability,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  match self {
    DefaultPushScheduler =>
      propagate_changes_with_events(
        core, pull, push, datalog, changed_ids, durability, event_sink,
      )
  }
}

///|
fn PushSchedulerStrategy::publish_cell_changes(
  self : PushSchedulerStrategy,
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_ids : Array[CellId],
  durability : Durability,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  match self {
    DefaultPushScheduler =>
      publish_cell_changes_with_events(
        core, pull, push, datalog, changed_ids, durability, event_sink,
      )
  }
}

///|
fn PushSchedulerStrategy::push_propagate_from(
  self : PushSchedulerStrategy,
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  changed_sources : Array[CellId],
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  match self {
    DefaultPushScheduler =>
      push_propagate_from_with_events(
        core, pull, push, datalog, changed_sources, event_sink,
      )
  }
}

///|
fn PushSchedulerStrategy::commit_batch(
  self : PushSchedulerStrategy,
  core : RuntimeCore,
  pull : PullState,
  push : PushState,
  datalog : DatalogState,
  event_sink : ((RuntimeEvaluationEvent) -> Unit)?,
) -> Unit {
  match self {
    DefaultPushScheduler =>
      commit_batch_with_events(core, pull, push, datalog, event_sink)
  }
}

///|
fn PushSchedulerStrategy::run_fixpoint(
  self : PushSchedulerStrategy,
  core : RuntimeCore,
  datalog : DatalogState,
) -> Array[CellId] {
  match self {
    DefaultPushScheduler => run_fixpoint(core, datalog)
  }
}
