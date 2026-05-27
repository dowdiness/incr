///|
pub(all) enum DerivedRebuildDisposition {
  RecomputedChanged
  RecomputedBackdated
} derive(Eq, Debug)

///|
pub(all) struct DerivedRebuildSummary {
  cell_id : CellId
  disposition : DerivedRebuildDisposition
  dependency_count_before : Int
  dependency_count_after : Int
  changed_at_before : Revision
  changed_at_after : Revision
  verified_at : Revision
  had_synthetic_accumulator_reads : Bool
} derive(Debug)

///|
pub(all) struct DerivedRebuildAbortSummary {
  cell_id : CellId
  dependency_count_before : Int
  changed_at_before : Revision
  verified_at_before : Revision
  error : String
} derive(Debug)

///|
pub(all) enum EagerDerivedEvaluationDisposition {
  RecomputedChanged
  RecomputedUnchanged
} derive(Eq, Debug)

///|
pub(all) struct EagerDerivedEvaluationSummary {
  cell_id : CellId
  disposition : EagerDerivedEvaluationDisposition
  level_before : Int
  level_after : Int
  dependency_count_before : Int
  dependency_count_after : Int
  changed_at_before : Revision
  changed_at_after : Revision
} derive(Debug)

///|
pub(all) struct EffectExecutionSummary {
  cell_id : CellId
  level_before : Int
  level_after : Int
  dependency_count_before : Int
  dependency_count_after : Int
} derive(Debug)

///|
pub(all) enum PushQueueSkipReason {
  StaleLevel
  DisposedOrKindMismatch
  NotDirty
} derive(Eq, Debug)

///|
pub(all) struct PushQueueSkipSummary {
  cell_id : CellId
  queued_level : Int
  current_level : Int
  reason : PushQueueSkipReason
} derive(Debug)

///|
pub(all) struct PushPropagationSummary {
  changed_source_count : Int
  eager_derived_evaluation_count : Int
  effect_execution_count : Int
  skipped_queue_entry_count : Int
} derive(Debug)

///|
pub(all) enum RuntimeEvaluationEvent {
  DerivedRebuilt(DerivedRebuildSummary)
  DerivedRebuildAborted(DerivedRebuildAbortSummary)
  EagerDerivedEvaluated(EagerDerivedEvaluationSummary)
  EffectExecuted(EffectExecutionSummary)
  PushQueueSkipped(PushQueueSkipSummary)
  PushPropagationCompleted(PushPropagationSummary)
} derive(Debug)
