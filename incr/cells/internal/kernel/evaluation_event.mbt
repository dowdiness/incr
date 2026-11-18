///|
#derive(Eq, Debug)
pub(all) enum DerivedRebuildDisposition {
  RecomputedChanged
  RecomputedBackdated
}

///|
pub extend DerivedRebuildDisposition with Eq::{not_equal, equal}

///|
pub extend DerivedRebuildDisposition with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct DerivedRebuildSummary {
  cell_id : CellId
  disposition : DerivedRebuildDisposition
  dependency_count_before : Int32
  dependency_count_after : Int32
  changed_at_before : Revision
  changed_at_after : Revision
  verified_at : Revision
  had_synthetic_accumulator_reads : Bool
}

///|
pub extend DerivedRebuildSummary with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct DerivedRebuildAbortSummary {
  cell_id : CellId
  dependency_count_before : Int32
  changed_at_before : Revision
  verified_at_before : Revision
  error : String
}

///|
pub extend DerivedRebuildAbortSummary with Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum EagerDerivedEvaluationDisposition {
  RecomputedChanged
  RecomputedUnchanged
}

///|
pub extend EagerDerivedEvaluationDisposition with Eq::{not_equal, equal}

///|
pub extend EagerDerivedEvaluationDisposition with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct EagerDerivedEvaluationSummary {
  cell_id : CellId
  disposition : EagerDerivedEvaluationDisposition
  level_before : Int32
  level_after : Int32
  dependency_count_before : Int32
  dependency_count_after : Int32
  changed_at_before : Revision
  changed_at_after : Revision
}

///|
pub extend EagerDerivedEvaluationSummary with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct EffectExecutionSummary {
  cell_id : CellId
  level_before : Int32
  level_after : Int32
  dependency_count_before : Int32
  dependency_count_after : Int32
}

///|
pub extend EffectExecutionSummary with Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum PushQueueSkipReason {
  StaleLevel
  DisposedOrKindMismatch
  NotDirty
}

///|
pub extend PushQueueSkipReason with Eq::{not_equal, equal}

///|
pub extend PushQueueSkipReason with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct PushQueueSkipSummary {
  cell_id : CellId
  queued_level : Int32
  current_level : Int32
  reason : PushQueueSkipReason
}

///|
pub extend PushQueueSkipSummary with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct PushPropagationSummary {
  changed_source_count : Int32
  eager_derived_evaluation_count : Int32
  effect_execution_count : Int32
  skipped_queue_entry_count : Int32
}

///|
pub extend PushPropagationSummary with Debug::{to_repr}

///|
#derive(Debug)
pub(all) enum RuntimeEvaluationEvent {
  DerivedRebuilt(DerivedRebuildSummary)
  DerivedRebuildAborted(DerivedRebuildAbortSummary)
  EagerDerivedEvaluated(EagerDerivedEvaluationSummary)
  EffectExecuted(EffectExecutionSummary)
  PushQueueSkipped(PushQueueSkipSummary)
  PushPropagationCompleted(PushPropagationSummary)
}

///|
pub extend RuntimeEvaluationEvent with Debug::{to_repr}
