///|
/// Sealed runtime-owned evaluation strategy bundle.
///
/// The default bundle delegates to the existing kernel state machine.
/// Alternate internal bundles may wrap those paths to record diagnostics,
/// but event data must not influence scheduling decisions.
pub struct EvaluationStrategies {
  priv pull_rebuilder : PullRebuilderStrategy
  priv push_scheduler : PushSchedulerStrategy
}

///|
/// Counter snapshot captured by an internal tracing strategy bundle.
pub(all) struct EvaluationTraceSummary {
  derived_pull_verification_count : Int
  derived_rebuild_count : Int
  derived_rebuild_abort_count : Int
  eager_derived_evaluation_count : Int
  effect_execution_count : Int
  push_queue_skip_count : Int
  push_propagation_count : Int
  changed_source_count : Int
  fixpoint_run_count : Int
} derive(Debug)

///|
/// Internal recorder used by tracing strategy bundles.
pub struct EvaluationTraceRecorder {
  priv events : Array[RuntimeEvaluationEvent]
  priv mut derived_pull_verification_count : Int
  priv mut derived_rebuild_count : Int
  priv mut derived_rebuild_abort_count : Int
  priv mut eager_derived_evaluation_count : Int
  priv mut effect_execution_count : Int
  priv mut push_queue_skip_count : Int
  priv mut push_propagation_count : Int
  priv mut changed_source_count : Int
  priv mut fixpoint_run_count : Int
}

///|
/// Creates an empty internal evaluation trace recorder.
pub fn EvaluationTraceRecorder::EvaluationTraceRecorder() -> EvaluationTraceRecorder {
  {
    events: [],
    derived_pull_verification_count: 0,
    derived_rebuild_count: 0,
    derived_rebuild_abort_count: 0,
    eager_derived_evaluation_count: 0,
    effect_execution_count: 0,
    push_queue_skip_count: 0,
    push_propagation_count: 0,
    changed_source_count: 0,
    fixpoint_run_count: 0,
  }
}

///|
/// Returns a defensive copy of recorded runtime evaluation events.
pub fn EvaluationTraceRecorder::events(
  self : EvaluationTraceRecorder,
) -> Array[RuntimeEvaluationEvent] {
  self.events.copy()
}

///|
/// Returns the current counter snapshot.
pub fn EvaluationTraceRecorder::summary(
  self : EvaluationTraceRecorder,
) -> EvaluationTraceSummary {
  {
    derived_pull_verification_count: self.derived_pull_verification_count,
    derived_rebuild_count: self.derived_rebuild_count,
    derived_rebuild_abort_count: self.derived_rebuild_abort_count,
    eager_derived_evaluation_count: self.eager_derived_evaluation_count,
    effect_execution_count: self.effect_execution_count,
    push_queue_skip_count: self.push_queue_skip_count,
    push_propagation_count: self.push_propagation_count,
    changed_source_count: self.changed_source_count,
    fixpoint_run_count: self.fixpoint_run_count,
  }
}

///|
fn EvaluationTraceRecorder::record_derived_pull_verification(
  self : EvaluationTraceRecorder,
  core : RuntimeCore,
  cell_id : CellId,
) -> Unit {
  guard cell_id.runtime_id == core.runtime_id &&
    cell_id.id >= 0 &&
    cell_id.id < core.cell_index.length() else {
    return
  }
  match core.cell_index[cell_id.id] {
    PullMemo(_) | HybridMemo(_) =>
      self.derived_pull_verification_count = self.derived_pull_verification_count +
        1
    _ => ()
  }
}

///|
fn EvaluationTraceRecorder::record_fixpoint_run(
  self : EvaluationTraceRecorder,
) -> Unit {
  self.fixpoint_run_count = self.fixpoint_run_count + 1
}

///|
/// Records one runtime evaluation event and updates event-derived counters.
pub fn EvaluationTraceRecorder::record_event(
  self : EvaluationTraceRecorder,
  event : RuntimeEvaluationEvent,
) -> Unit {
  self.events.push(event)
  match event {
    DerivedRebuilt(_) =>
      self.derived_rebuild_count = self.derived_rebuild_count + 1
    DerivedRebuildAborted(_) =>
      self.derived_rebuild_abort_count = self.derived_rebuild_abort_count + 1
    EagerDerivedEvaluated(_) =>
      self.eager_derived_evaluation_count = self.eager_derived_evaluation_count +
        1
    EffectExecuted(_) =>
      self.effect_execution_count = self.effect_execution_count + 1
    PushQueueSkipped(_) =>
      self.push_queue_skip_count = self.push_queue_skip_count + 1
    PushPropagationCompleted(summary) => {
      self.push_propagation_count = self.push_propagation_count + 1
      self.changed_source_count = self.changed_source_count +
        summary.changed_source_count
    }
  }
}

///|
fn EvaluationTraceRecorder::recording_sink(
  self : EvaluationTraceRecorder,
  downstream : ((RuntimeEvaluationEvent) -> Unit)?,
) -> (RuntimeEvaluationEvent) -> Unit {
  fn(event) {
    self.record_event(event)
    match downstream {
      Some(emit) => emit(event)
      None => ()
    }
  }
}

///|
priv enum PullRebuilderStrategy {
  DefaultPullRebuilder
  TracingPullRebuilder(EvaluationTraceRecorder)
}

///|
priv enum PushSchedulerStrategy {
  DefaultPushScheduler
  TracingPushScheduler(EvaluationTraceRecorder)
}

///|
/// Returns the default strategy bundle that preserves current behavior.
pub fn EvaluationStrategies::default() -> EvaluationStrategies {
  { pull_rebuilder: DefaultPullRebuilder, push_scheduler: DefaultPushScheduler }
}

///|
/// Returns a tracing strategy bundle that records internal counters while
/// delegating evaluation behavior to the default strategies.
pub fn EvaluationStrategies::tracing(
  recorder : EvaluationTraceRecorder,
) -> EvaluationStrategies {
  {
    pull_rebuilder: TracingPullRebuilder(recorder),
    push_scheduler: TracingPushScheduler(recorder),
  }
}

///|
/// Returns the tracing recorder for a tracing bundle, if one is installed.
pub fn EvaluationStrategies::trace_recorder(
  self : EvaluationStrategies,
) -> EvaluationTraceRecorder? {
  match self.pull_rebuilder {
    TracingPullRebuilder(recorder) => Some(recorder)
    DefaultPullRebuilder =>
      match self.push_scheduler {
        TracingPushScheduler(recorder) => Some(recorder)
        DefaultPushScheduler => None
      }
  }
}

///|
/// Runs pull verification through the selected strategy.
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
/// Publishes ordinary source changes through the selected push scheduler.
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
/// Publishes kernel-originated cell changes through the selected push scheduler.
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
/// Runs level-ordered push propagation from changed source cells.
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
/// Commits the current batch through the selected push scheduler.
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
/// Runs fixpoint evaluation through the selected scheduler.
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
    TracingPullRebuilder(recorder) => {
      recorder.record_derived_pull_verification(core, cell_id)
      pull_verify(core, pull, slot_snapshots, cell_id)
    }
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
    TracingPushScheduler(recorder) =>
      propagate_changes_with_events(
        core,
        pull,
        push,
        datalog,
        changed_ids,
        durability,
        Some(recorder.recording_sink(event_sink)),
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
    TracingPushScheduler(recorder) =>
      publish_cell_changes_with_events(
        core,
        pull,
        push,
        datalog,
        changed_ids,
        durability,
        Some(recorder.recording_sink(event_sink)),
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
    TracingPushScheduler(recorder) =>
      push_propagate_from_with_events(
        core,
        pull,
        push,
        datalog,
        changed_sources,
        Some(recorder.recording_sink(event_sink)),
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
    TracingPushScheduler(recorder) =>
      commit_batch_with_events(
        core,
        pull,
        push,
        datalog,
        Some(recorder.recording_sink(event_sink)),
      )
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
    TracingPushScheduler(recorder) => {
      recorder.record_fixpoint_run()
      run_fixpoint(core, datalog)
    }
  }
}
